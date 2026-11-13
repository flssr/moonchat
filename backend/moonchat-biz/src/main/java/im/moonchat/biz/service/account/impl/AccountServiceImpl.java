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
import im.moonchat.biz.entity.TurmsSyncState;
import im.moonchat.biz.mapper.account.AccountInfoMapper;
import im.moonchat.biz.mapper.account.AccountMapper;
import im.moonchat.biz.service.account.AccountKeyService;
import im.moonchat.biz.service.account.AccountService;
import im.moonchat.biz.service.account.CredentialHasher;
import im.moonchat.biz.service.auth.LoginTokenService;
import im.moonchat.biz.service.friendship.FriendshipService;
import im.moonchat.biz.service.turms.TurmsCredentialService;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class AccountServiceImpl implements AccountService {

    private static final String HUMAN = "human";
    private static final String AGENT = "agent";
    private static final String FROZEN = "frozen";

    private final AccountMapper accountMapper;
    private final AccountInfoMapper accountInfoMapper;
    private final CredentialHasher hasher;
    private final AccountKeyService accountKeys;
    private final FriendshipService friendships;
    private final TurmsAdminClient turmsAdmin;
    private final TurmsCredentialService turmsCredentials;
    private final LoginTokenService loginTokens;
    private final TurmsProperties turmsProperties;

    /**
     * 同一事务写 `account` 与 `account_info`，并在事务内用这个 id 建 Turms 用户；
     * 建用户失败就回滚整笔——不留孤儿账号（docs/DDD.md「创建顺序」）。
     */
    @Override
    @Transactional
    public AccountResponses.RegisterResponse register(AccountRequests.RegisterRequest request) {
        if (accountInfoMapper.selectCount(new LambdaQueryWrapper<AccountInfo>()
                .eq(AccountInfo::getEmail, request.email())) > 0) {
            throw ApiException.conflict("这个邮箱已经注册过");
        }

        Account account = createAccount(HUMAN, null, request.email(), request.displayName(),
                hasher.hashPassword(request.password()));
        return new AccountResponses.RegisterResponse(account.getId(), request.displayName(), HUMAN);
    }

    /**
     * agent 账号与真人账号同构，只多一个不可转移的归属者（docs/DDD.md）；
     * 明文密钥只在这个响应里出现一次，库里只有它的确定性哈希。
     */
    @Override
    @Transactional
    public AccountResponses.AgentAccountResponse createAgent(CurrentAccount me,
            AccountRequests.DisplayNameRequest request) {
        if (me.source() == CurrentAccount.Source.AGENT) {
            throw ApiException.forbidden("agent 不能再建 agent");
        }

        String accountKey = UUID.randomUUID().toString();
        Account account = createAccount(AGENT, me.accountId(), null, request.displayName(),
                hasher.hashAccountKey(accountKey));
        return new AccountResponses.AgentAccountResponse(account.getId(), request.displayName(), accountKey);
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

    /** 归属关系本身就是授权：没有授权表，也没有临时凭据。账号密钥形态只换密钥所属账号的凭据。 */
    @Override
    public AccountResponses.SessionResponse issueSession(Optional<CurrentAccount> caller,
            AccountRequests.SessionRequest request) {
        boolean keyShape = request.accountKey() != null;
        boolean idShape = request.accountId() != null;
        // 无主体、两种都给、或密钥形态却带了认证头：都不是契约里的两种形态（§3.3）
        if (keyShape == idShape || (keyShape && caller.isPresent())) {
            throw ApiException.validationFailed(keyShape ? "account_key" : "account_id",
                    keyShape ? "account_key 与 account_id 只能给一个" : "account_id 不能为空");
        }

        Account account;
        if (keyShape) {
            account = accountMapper.selectById(accountKeys.authenticate(request.accountKey()));
        } else {
            account = ownedAccount(caller.orElseThrow(ApiException::unauthenticated), request.accountId());
        }
        AccountInfo info = accountInfoMapper.selectById(account.getId());
        if (FROZEN.equals(info.getStatus())) {
            throw ApiException.accountFrozen();
        }

        TurmsCredentialService.Credential credential = turmsCredentials.sign(account.getId());
        // 归属者切账号时顺带签一份该账号的登录 JWT：没有它，切进去之后连 /api 都调不了
        LoginTokenService.Issued loginToken = keyShape ? null : loginTokens.issue(account.getId());
        return new AccountResponses.SessionResponse(account.getId(), info.getDisplayName(), account.getType(),
                loginToken == null ? null : loginToken.token(),
                loginToken == null ? null : loginToken.expiresAt(),
                new AccountResponses.SessionResponse.Turms(account.getId(), credential.token(),
                        turmsProperties.gatewayUrl()),
                credential.expiresAt());
    }

    /**
     * 名字只是展示，不参与任何判定；但 Turms 那边也存了一份，所以要同步。
     * 同步失败就整笔回滚（名字与状态都不变），不留永远 `pending` 的账号。
     */
    @Override
    @Transactional
    public AccountResponses.RenameResponse rename(CurrentAccount me, AccountRequests.DisplayNameRequest request) {
        AccountInfo info = accountInfoMapper.selectById(me.accountId());
        if (FROZEN.equals(info.getStatus())) {
            throw ApiException.accountFrozen();
        }

        OffsetDateTime now = OffsetDateTime.now();
        accountInfoMapper.updateById(AccountInfo.builder()
                .accountId(me.accountId())
                .displayName(request.displayName())
                .updatedAt(now)
                .build());

        turmsAdmin.updateUserName(me.accountId(), request.displayName());

        accountMapper.updateById(Account.builder()
                .id(me.accountId())
                .turmsSyncState(TurmsSyncState.SYNCED)
                .updatedAt(now)
                .build());

        return new AccountResponses.RenameResponse(me.accountId(), request.displayName(), now.toInstant());
    }

    /** 资料页只返回名字、账号 id、是否已是好友；`type`、`email`、归属与时间列一概不出门。 */
    @Override
    public AccountResponses.ProfileResponse profile(CurrentAccount me, long accountId) {
        AccountInfo info = accountInfoMapper.selectById(accountId);
        if (info == null) {
            throw ApiException.notFound("账号不存在");
        }
        return new AccountResponses.ProfileResponse(accountId, info.getDisplayName(),
                friendships.areFriends(me.accountId(), accountId));
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

    /**
     * 注册与建 agent 共用的一次建号：身份行 + 资料行 + Turms 用户 + 同步标记，
     * 全部在调用方的事务里完成（失败整笔回滚）。
     */
    private Account createAccount(String type, Long ownerAccountId, String email, String displayName,
            String credentialHash) {
        Account account = Account.builder()
                .type(type)
                .ownerAccountId(ownerAccountId)
                .turmsSyncState(TurmsSyncState.PENDING)
                .build();
        accountMapper.insert(account);

        accountInfoMapper.insert(AccountInfo.builder()
                .accountId(account.getId())
                .displayName(displayName)
                .email(email)
                .credentialHash(credentialHash)
                .build());

        turmsAdmin.createUser(account.getId(), displayName);

        accountMapper.updateById(Account.builder()
                .id(account.getId())
                .turmsSyncState(TurmsSyncState.SYNCED)
                .updatedAt(OffsetDateTime.now())
                .build());
        return account;
    }

    /** `account_id` 形态只能换自己或自己名下 agent 的凭据：归属关系本身就是授权。 */
    private Account ownedAccount(CurrentAccount me, long accountId) {
        Account account = accountMapper.selectById(accountId);
        if (account == null) {
            throw ApiException.notFound("账号不存在");
        }
        if (account.getId() != me.accountId() && !Objects.equals(account.getOwnerAccountId(), me.accountId())) {
            throw ApiException.forbidden("这个账号不在你名下");
        }
        return account;
    }

    private AccountResponses.TokenResponse tokenResponse(long accountId, String type, String displayName) {        LoginTokenService.Issued token = loginTokens.issue(accountId);
        return new AccountResponses.TokenResponse(token.token(), token.expiresAt(),
                new AccountResponses.AccountSummary(accountId, type, displayName));
    }

    private static AccountResponses.AccountSummary summary(Account account, Map<Long, String> names) {
        return new AccountResponses.AccountSummary(account.getId(), account.getType(),
                names.get(account.getId()));
    }
}
