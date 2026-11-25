package im.mondchat.biz.service.account;

import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.dto.account.AccountRequests;
import im.mondchat.biz.dto.account.AccountResponses;
import java.util.Optional;

/** 账号与归属的行为（docs/truth/backend/identity.md）。 */
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

    /** #6 改本账号资料（PUT 全量语义）：同一事务写库，名字变了才在事务内同步 Turms。 */
    AccountResponses.AccountProfileResponse updateProfile(CurrentAccount me,
            AccountRequests.UpdateProfileRequest request);

    /** 改本账号头像（PUT 语义：整枚替换，`null` = 清回生成的首字头像）。 */
    AccountResponses.AvatarResponse updateAvatar(CurrentAccount me, AccountRequests.AvatarRequest request);

    /** #24 本人完整资料：编辑页回填用，与 #6 的响应同形。 */
    AccountResponses.AccountProfileResponse myProfile(CurrentAccount me);

    /** #7 资料页：名字、账号 id、是否已是好友。非好友也看得到，这就是加好友的唯一入口。 */
    AccountResponses.ProfileResponse profile(CurrentAccount me, long accountId);

    /** #20 登录 JWT 滑动续期。 */
    AccountResponses.TokenResponse refresh(CurrentAccount me);

    /** 认证入口统一确认账号仍存在；硬删后旧 JWT 与账号密钥都不能再进业务层。 */
    void requireExists(long accountId);

    /** 注销真人账号：校验密码、拒绝群主、级联清理名下 agent，并写远端删除事件。 */
    void deleteMe(CurrentAccount me, AccountRequests.DeleteAccountRequest request);
}
