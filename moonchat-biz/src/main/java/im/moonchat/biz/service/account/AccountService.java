package im.moonchat.biz.service.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.account.AccountRequests;
import im.moonchat.biz.dto.account.AccountResponses;

/** 账号与归属的行为（docs/account-and-ownership.md）。 */
public interface AccountService {

    /** #1 注册真人账号：同一事务写身份与资料，再用这个 id 建 Turms 用户。 */
    AccountResponses.RegisterResponse register(AccountRequests.RegisterRequest request);

    /** #2 换登录 JWT。 */
    AccountResponses.TokenResponse login(AccountRequests.LoginRequest request);

    /** #3 换 Turms 凭据（S1 只有归属者形态）。 */
    AccountResponses.SessionResponse issueSession(CurrentAccount me, AccountRequests.SessionRequest request);

    /** #4 我的账号 + 我名下的 agent。 */
    AccountResponses.MineResponse mine(CurrentAccount me);

    /** #20 登录 JWT 滑动续期。 */
    AccountResponses.TokenResponse refresh(CurrentAccount me);
}
