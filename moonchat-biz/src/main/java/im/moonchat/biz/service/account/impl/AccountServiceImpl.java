package im.moonchat.biz.service.account.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.client.turms.TurmsAdminClient;
import im.moonchat.biz.common.ApiException;
import im.moonchat.biz.config.TurmsProperties;
import im.moonchat.biz.dto.account.AccountRequests;
import im.moonchat.biz.dto.account.AccountResponses;
import im.moonchat.biz.entity.Account;
import im.moonchat.biz.entity.AccountInfo;
import im.moonchat.biz.mapper.account.AccountInfoMapper;
import im.moonchat.biz.mapper.account.AccountMapper;
import im.moonchat.biz.service.account.AccountService;
import im.moonchat.biz.service.account.CredentialHasher;
import im.moonchat.biz.service.auth.LoginTokenService;
import im.moonchat.biz.service.turms.TurmsCredentialService;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class AccountServiceImpl implements AccountService {

    private static final String HUMAN = "human";
    private static final String FROZEN = "frozen";

    private final AccountMapper accountMapper;
    private final AccountInfoMapper accountInfoMapper;
    private final CredentialHasher hasher;
    private final TurmsAdminClient turmsAdmin;
    private final TurmsCredentialService turmsCredentials;
    private final LoginTokenService loginTokens;
    private final TurmsProperties turmsProperties;

    /**
     * 同一事务写 `account` 与 `account_info`，并在事务内用这个 id 建 Turms 用户；
     * 建用户失败就回滚整笔——不留孤儿账号（docs/v1-construction-plan.md §4 的 S1）。
     */
    @Override
    @Transactional
    public AccountResponses.RegisterResponse register(AccountRequests.RegisterRequest request) {
        if (accountInfoMapper.selectCount(new LambdaQueryWrapper<AccountInfo>()
                .eq(AccountInfo::getEmail, request.email())) > 0) {
            throw ApiException.conflict("这个邮箱已经注册过");
        }

        Account account = Account.builder()
                .type(HUMAN)
                .turmsSyncState("pending")
                .build();
        accountMapper.insert(account);

        accountInfoMapper.insert(AccountInfo.builder()
                .accountId(account.getId())
                .displayName(request.displayName())
                .email(request.email())
                .credentialHash(hasher.hashPassword(request.password()))
                .build());

        turmsAdmin.createUser(account.getId(), request.displayName());

        accountMapper.updateById(Account.builder()
                .id(account.getId())
                .turmsSyncState("synced")
                .updatedAt(OffsetDateTime.now())
                .build());

        return new AccountResponses.RegisterResponse(account.getId(), request.displayName(), HUMAN);
    }

    /** 账号不存在与密码错误返回同一个码，不给账号枚举留信号。 */
    @Override
    public AccountResponses.TokenResponse login(AccountRequests.LoginRequest request) {
        AccountInfo info = accountInfoMapper.selectOne(new LambdaQueryWrapper<AccountInfo>()
                .eq(AccountInfo::getEmail, request.email()));
        if (info == null || !hasher.matchesPassword(request.password(), info.getCredentialHash())) {
            throw ApiException.unauthenticated();
        }
        Account account = accountMapper.selectById(info.getAccountId());
        return tokenResponse(account.getId(), account.getType(), info.getDisplayName());
    }

    /** 归属关系本身就是授权：没有授权表，也没有临时凭据。 */
    @Override
    public AccountResponses.SessionResponse issueSession(CurrentAccount me, AccountRequests.SessionRequest request) {
        if (request.accountKey() != null) {
            // 账号密钥形态要等 S2 建出 agent 账号与密钥才存在：此刻没有任何密钥能查到账号。
            throw ApiException.unauthenticated();
        }
        if (request.accountId() == null) {
            throw ApiException.validationFailed("account_id", "account_id 不能为空");
        }
        Account account = accountMapper.selectById(request.accountId());
        if (account == null) {
            throw ApiException.notFound("账号不存在");
        }
        long meId = me.accountId();
        boolean mine = account.getId() == meId
                || (account.getOwnerAccountId() != null && account.getOwnerAccountId() == meId);
        if (!mine) {
            throw ApiException.forbidden("这个账号不在你名下");
        }
        AccountInfo info = accountInfoMapper.selectById(account.getId());
        if (FROZEN.equals(info.getStatus())) {
            throw ApiException.accountFrozen();
        }

        TurmsCredentialService.Credential credential = turmsCredentials.sign(account.getId());
        return new AccountResponses.SessionResponse(account.getId(), info.getDisplayName(), account.getType(),
                new AccountResponses.SessionResponse.Turms(account.getId(), credential.token(),
                        turmsProperties.gatewayUrl()),
                credential.expiresAt());
    }

    /** 自己排第一，名下的 agent 按创建时间升序。 */
    @Override
    public AccountResponses.MineResponse mine(CurrentAccount me) {
        long meId = me.accountId();
        List<Account> accounts = accountMapper.selectList(new LambdaQueryWrapper<Account>()
                .eq(Account::getId, meId)
                .or()
                .eq(Account::getOwnerAccountId, meId)
                .orderByAsc(Account::getCreatedAt));

        Map<Long, String> names = accountInfoMapper
                .selectList(new LambdaQueryWrapper<AccountInfo>()
                        .in(AccountInfo::getAccountId, accounts.stream().map(Account::getId).toList()))
                .stream()
                .collect(Collectors.toMap(AccountInfo::getAccountId, AccountInfo::getDisplayName));

        List<AccountResponses.AccountSummary> items = new ArrayList<>(accounts.size());
        accounts.stream()
                .filter(account -> account.getId() == meId)
                .forEach(account -> items.add(summary(account, names)));
        accounts.stream()
                .filter(account -> account.getId() != meId)
                .forEach(account -> items.add(summary(account, names)));
        return new AccountResponses.MineResponse(items);
    }

    /** 只换登录凭据，不签发 Turms 凭据；无状态，不写 PG。 */
    @Override
    public AccountResponses.TokenResponse refresh(CurrentAccount me) {
        Account account = accountMapper.selectById(me.accountId());
        if (account == null) {
            throw ApiException.unauthenticated();
        }
        AccountInfo info = accountInfoMapper.selectById(account.getId());
        if (FROZEN.equals(info.getStatus())) {
            throw ApiException.accountFrozen();
        }
        return tokenResponse(account.getId(), account.getType(), info.getDisplayName());
    }

    private AccountResponses.TokenResponse tokenResponse(long accountId, String type, String displayName) {
        LoginTokenService.Issued token = loginTokens.issue(accountId);
        return new AccountResponses.TokenResponse(token.token(), token.expiresAt(),
                new AccountResponses.AccountSummary(accountId, type, displayName));
    }

    private static AccountResponses.AccountSummary summary(Account account, Map<Long, String> names) {
        return new AccountResponses.AccountSummary(account.getId(), account.getType(),
                names.get(account.getId()));
    }
}
