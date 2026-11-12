package im.moonchat.biz.service.account;

import im.moonchat.biz.auth.CurrentAccount;
import im.moonchat.biz.dto.account.AccountRequests;
import im.moonchat.biz.dto.account.AccountResponses;
import java.util.Optional;

/** 账号与归属的行为（docs/account-and-ownership.md）。 */
public interface AccountService {

    /** #1 注册真人账号：同一事务写身份与资料，再用这个 id 建 Turms 用户。 */
    AccountResponses.RegisterResponse register(AccountRequests.RegisterRequest request);

    /** #2 换登录 JWT。 */
    AccountResponses.TokenResponse login(AccountRequests.LoginRequest request);

    /** #3 换 Turms 凭据：两种形态恰好一种，账号密钥形态不带认证头，所以调用方可空。 */
    AccountResponses.SessionResponse issueSession(Optional<CurrentAccount> caller, AccountRequests.SessionRequest request);

    /** #4 我的账号 + 我名下的 agent。 */
    AccountResponses.MineResponse mine(CurrentAccount me);

    /** #5 建 agent 账号：同一事务写身份与资料，再用这个 id 建 Turms 用户，返回一次性明文密钥。 */
    AccountResponses.AgentAccountResponse createAgent(CurrentAccount me, AccountRequests.DisplayNameRequest request);

    /** #6 改本账号名字：同一事务写库并在事务内同步 Turms，没拿到确认就整笔回滚。 */
    AccountResponses.RenameResponse rename(CurrentAccount me, AccountRequests.DisplayNameRequest request);

    /** #7 资料页：名字、账号 id、是否已是好友。非好友也看得到，这就是加好友的唯一入口。 */
    AccountResponses.ProfileResponse profile(CurrentAccount me, long accountId);

    /** #20 登录 JWT 滑动续期。 */
    AccountResponses.TokenResponse refresh(CurrentAccount me);
}
