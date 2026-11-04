package im.moonchat.biz.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.auth.LoginTokenService;
import im.moonchat.biz.imfacade.TurmsAdminClient;
import im.moonchat.biz.imfacade.TurmsCredentialSigner;
import im.moonchat.biz.imfacade.TurmsProperties;
import im.moonchat.biz.web.ApiException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 账号与归属的行为（docs/account-and-ownership.md）：身份真相在 `account`，Turms 用户由 im-facade 建。 */
@Service
public class AccountService {

    private static final String HUMAN = "human";
    private static final String FROZEN = "frozen";

    private final AccountMapper accounts;
    private final CredentialHasher hasher;
    private final TurmsAdminClient turmsAdmin;
    private final TurmsCredentialSigner turmsCredentials;
    private final LoginTokenService loginTokens;
    private final String turmsGatewayUrl;

    AccountService(AccountMapper accounts, CredentialHasher hasher, TurmsAdminClient turmsAdmin,
            TurmsCredentialSigner turmsCredentials, LoginTokenService loginTokens, TurmsProperties turmsProperties) {
        this.accounts = accounts;
        this.hasher = hasher;
        this.turmsAdmin = turmsAdmin;
        this.turmsCredentials = turmsCredentials;
        this.loginTokens = loginTokens;
        this.turmsGatewayUrl = turmsProperties.gatewayUrl();
    }

    /**
     * #1：同一事务写 `account` 与 `account_info`，再用这个 id 建 Turms 用户；
     * 建用户失败就回滚 PG 行——不留孤儿账号（docs/v1-construction-plan.md §4 S1）。
     */
    @Transactional
    public AccountDtos.RegisterResponse register(AccountDtos.RegisterRequest request) {
        if (accounts.countByEmail(request.email()) > 0) {
            throw ApiException.conflict("这个邮箱已经注册过");
        }
        long accountId = accounts.insertHumanAccount();
        accounts.insertHumanInfo(accountId, request.displayName(), request.email(),
                hasher.hashPassword(request.password()));
        turmsAdmin.createUser(accountId, request.displayName());
        accounts.markSynced(accountId);
        return new AccountDtos.RegisterResponse(accountId, request.displayName(), HUMAN);
    }

    /** #2：账号不存在与密码错误返回同一个码，不给账号枚举留信号。 */
    public AccountDtos.TokenResponse login(AccountDtos.LoginRequest request) {
        AccountMapper.LoginRow row = accounts.findByEmail(request.email());
        if (row == null || !hasher.matchesPassword(request.password(), row.credentialHash())) {
            throw ApiException.unauthenticated();
        }
        return tokenResponse(row.accountId(), row.type(), row.displayName());
    }

    /** #3 的归属者形态：归属关系本身就是授权，没有授权表，也没有临时凭据。 */
    public AccountDtos.SessionResponse issueSession(CurrentAccount me, AccountDtos.SessionRequest request) {
        if (request.accountKey() != null) {
            // 账号密钥形态要等 S2 建出 agent 账号与密钥才存在：此刻没有任何密钥能查到账号。
            throw ApiException.unauthenticated();
        }
        if (request.accountId() == null) {
            throw ApiException.validationFailed("account_id", "account_id 不能为空");
        }
        AccountMapper.AccountRow row = accounts.findById(request.accountId());
        if (row == null) {
            throw ApiException.notFound("账号不存在");
        }
        boolean mine = row.accountId() == me.accountId()
                || (row.ownerAccountId() != null && row.ownerAccountId() == me.accountId());
        if (!mine) {
            throw ApiException.forbidden("这个账号不在你名下");
        }
        if (FROZEN.equals(row.status())) {
            throw ApiException.accountFrozen();
        }
        TurmsCredentialSigner.Credential credential = turmsCredentials.sign(row.accountId());
        return new AccountDtos.SessionResponse(row.accountId(), row.displayName(), row.type(),
                new AccountDtos.SessionResponse.Turms(row.accountId(), credential.token(), turmsGatewayUrl),
                credential.expiresAt());
    }

    /** #4：自己排第一，名下的 agent 按创建时间升序。 */
    public AccountDtos.MineResponse mine(CurrentAccount me) {
        return new AccountDtos.MineResponse(accounts.findMine(me.accountId()).stream()
                .map(row -> new AccountDtos.AccountSummary(row.accountId(), row.type(), row.displayName()))
                .toList());
    }

    /** #20：只换登录凭据，不签发 Turms 凭据；无状态，不写 PG。 */
    public AccountDtos.TokenResponse refresh(CurrentAccount me) {
        AccountMapper.AccountRow row = accounts.findById(me.accountId());
        if (row == null) {
            throw ApiException.unauthenticated();
        }
        if (FROZEN.equals(row.status())) {
            throw ApiException.accountFrozen();
        }
        return tokenResponse(row.accountId(), row.type(), row.displayName());
    }

    private AccountDtos.TokenResponse tokenResponse(long accountId, String type, String displayName) {
        LoginTokenService.Issued token = loginTokens.issue(accountId);
        return new AccountDtos.TokenResponse(token.token(), token.expiresAt(),
                new AccountDtos.AccountSummary(accountId, type, displayName));
    }
}
