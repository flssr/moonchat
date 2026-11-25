package im.mondchat.biz.service.account.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import im.mondchat.biz.auth.CurrentAccount;
import im.mondchat.biz.client.turms.TurmsAdminClient;
import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.config.ProjectionProperties;
import im.mondchat.biz.config.TurmsProperties;
import im.mondchat.biz.dto.account.AccountRequests;
import im.mondchat.biz.dto.account.AccountResponses;
import im.mondchat.biz.entity.Account;
import im.mondchat.biz.entity.AccountInfo;
import im.mondchat.biz.entity.AccountRoom;
import im.mondchat.biz.entity.Blocklist;
import im.mondchat.biz.entity.Friendship;
import im.mondchat.biz.entity.FriendshipReverse;
import im.mondchat.biz.entity.RoomInfo;
import im.mondchat.biz.entity.RoomMember;
import im.mondchat.biz.entity.TurmsSyncState;
import im.mondchat.biz.mapper.account.AccountInfoMapper;
import im.mondchat.biz.mapper.account.AccountMapper;
import im.mondchat.biz.mapper.blocklist.BlocklistMapper;
import im.mondchat.biz.mapper.friendship.FriendshipMapper;
import im.mondchat.biz.mapper.friendship.FriendshipReverseMapper;
import im.mondchat.biz.mapper.room.AccountRoomMapper;
import im.mondchat.biz.mapper.room.RoomInfoMapper;
import im.mondchat.biz.mapper.room.RoomMemberMapper;
import im.mondchat.biz.service.account.AccountKeyService;
import im.mondchat.biz.service.account.AccountLockService;
import im.mondchat.biz.service.account.AccountService;
import im.mondchat.biz.service.account.CredentialHasher;
import im.mondchat.biz.service.auth.LoginTokenService;
import im.mondchat.biz.service.friendship.FriendshipService;
import im.mondchat.biz.service.limiter.AccountDeletionRateLimiter;
import im.mondchat.biz.service.projection.ProjectionEvents;
import im.mondchat.biz.service.turms.TurmsCredentialService;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class AccountServiceImpl implements AccountService {

    private static final String HUMAN = "human";
    private static final String AGENT = "agent";
    private static final String FROZEN = "frozen";

    /** 平台默认头像：真人 6 张、agent 3 张（issue #10）。key 与客户端资源同名，存 key 不存 URL。 */
    private static final List<String> HUMAN_AVATARS = List.of(
            "female_01", "female_02", "female_03", "male_01", "male_02", "male_03");
    private static final List<String> AGENT_AVATARS = List.of("agent_blue", "agent_pink", "agent_gold");

    private final AccountMapper accountMapper;
    private final AccountInfoMapper accountInfoMapper;
    private final CredentialHasher hasher;
    private final AccountKeyService accountKeys;
    private final FriendshipService friendships;
    private final TurmsAdminClient turmsAdmin;
    private final TurmsCredentialService turmsCredentials;
    private final LoginTokenService loginTokens;
    private final TurmsProperties turmsProperties;
    private final ProjectionEvents projectionEvents;
    private final ProjectionProperties projectionProperties;
    private final AccountLockService accountLocks;
    private final AccountDeletionRateLimiter deletionRateLimiter;
    private final FriendshipMapper friendshipMapper;
    private final FriendshipReverseMapper friendshipReverseMapper;
    private final BlocklistMapper blocklistMapper;
    private final RoomInfoMapper roomInfoMapper;
    private final RoomMemberMapper roomMemberMapper;
    private final AccountRoomMapper accountRoomMapper;

    /**
     * 同一事务写 `account` 与 `account_info`，并在事务内用这个 id 建 Turms 用户；
     * 建用户失败就回滚整笔——不留孤儿账号（docs/truth/backend/identity.md）。
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
     * agent 账号与真人账号同构，只多一个不可转移的归属者（docs/truth/backend/identity.md）；
     * 明文密钥只在这个响应里出现一次，库里只有它的确定性哈希。
     */
    @Override
    @Transactional
    public AccountResponses.AgentAccountResponse createAgent(CurrentAccount me,
            AccountRequests.DisplayNameRequest request) {
        Account owner = accountLocks.require(me.accountId());
        if (me.source() == CurrentAccount.Source.AGENT || !HUMAN.equals(owner.getType())) {
            throw ApiException.forbidden("agent 不能再建 agent");
        }

        String accountKey = UUID.randomUUID().toString();
        Account account = createAccount(AGENT, owner.getId(), null, request.displayName(),
                hasher.hashAccountKey(accountKey));
        // 新 agent 自带一枚默认 agent 头像：按账号 id 在三张里轮换，号段固定所以结果稳定；
        // 不落一枚的话，列表与资料页只剩客户端按 id 生成的首字头像（issue #10）。
        String avatar = AGENT_AVATARS.get((int) (account.getId() % AGENT_AVATARS.size()));
        accountInfoMapper.update(null, new LambdaUpdateWrapper<AccountInfo>()
                .eq(AccountInfo::getAccountId, account.getId())
                .set(AccountInfo::getAvatar, avatar));
        // 归属者与这个 agent 创建即好友：同一事务，Turms 建用户失败就连好友两行一起回滚
        friendships.createAccepted(owner.getId(), account.getId());
        return new AccountResponses.AgentAccountResponse(account.getId(), request.displayName(), accountKey);
    }

    /**
     * 注销是硬删：先锁真人身份行并校验密码，群主直接拒绝；名下 agent、关系、群成员与镜像同事务清理。
     * Turms 用户删除只写 outbox，由投影派发器重试，避免 PG 与远端没有共同事务时留下半截状态。
     */
    @Override
    @Transactional
    public void deleteMe(CurrentAccount me, AccountRequests.DeleteAccountRequest request) {
        if (!projectionProperties.enabled()) {
            throw ApiException.projectionDisabled();
        }
        deletionRateLimiter.check(me.accountId());
        Account account = accountLocks.lock(me.accountId());
        if (account == null) {
            throw ApiException.unauthenticated();
        }
        if (!HUMAN.equals(account.getType())) {
            throw ApiException.forbidden("agent 账号不能注销");
        }
        AccountInfo info = accountInfoMapper.selectById(me.accountId());
        if (info == null || !hasher.matchesPassword(request.password(), info.getCredentialHash())) {
            throw ApiException.invalidPassword();
        }
        Set<Long> accountIdSet = new LinkedHashSet<>();
        accountIdSet.add(me.accountId());
        List<Long> accountIds = new ArrayList<>(accountIdSet);
        for (int i = 0; i < accountIds.size(); i++) {
            long parentId = accountIds.get(i);
            accountLocks.require(parentId);
            List<Account> children = accountMapper.selectList(new LambdaQueryWrapper<Account>()
                    .eq(Account::getOwnerAccountId, parentId));
            for (Account child : children) {
                accountLocks.require(child.getId());
                if (accountIdSet.add(child.getId())) {
                    accountIds.add(child.getId());
                }
            }
        }
        if (roomInfoMapper.selectCount(new LambdaQueryWrapper<RoomInfo>()
                .in(RoomInfo::getOwnerAccountId, accountIds)) > 0) {
            throw ApiException.ownerCannotDeleteAccount();
        }

        // 先记录退出事件再删 PG 行：派发器允许 member=false 在账号删除后继续清理 Turms 群成员。
        List<RoomMember> memberships = roomMemberMapper.selectList(new LambdaQueryWrapper<RoomMember>()
                .in(RoomMember::getAccountId, accountIds)
                .isNull(RoomMember::getDeletedAt));
        List<Long> roomIds = memberships.stream().map(RoomMember::getRoomId).distinct().toList();
        Map<Long, Long> turmsGroupIds = roomIds.isEmpty()
                ? Map.of()
                : roomInfoMapper.selectBatchIds(roomIds).stream()
                        .filter(room -> room.getTurmsGroupId() != null)
                        .collect(Collectors.toMap(RoomInfo::getId, RoomInfo::getTurmsGroupId));
        for (RoomMember membership : memberships) {
            Long turmsGroupId = turmsGroupIds.get(membership.getRoomId());
            if (turmsGroupId != null) {
                projectionEvents.roomMemberChanged(membership.getRoomId(), membership.getAccountId(),
                        turmsGroupId, false);
            }
        }
        projectionEvents.deleteAccountEvents(accountIds);
        accountIds.forEach(projectionEvents::accountDeleted);

        friendshipMapper.delete(new LambdaQueryWrapper<Friendship>()
                .in(Friendship::getAccountId, accountIds)
                .or().in(Friendship::getPeerAccountId, accountIds));
        friendshipReverseMapper.delete(new LambdaQueryWrapper<FriendshipReverse>()
                .in(FriendshipReverse::getAccountId, accountIds)
                .or().in(FriendshipReverse::getPeerAccountId, accountIds));
        blocklistMapper.delete(new LambdaQueryWrapper<Blocklist>()
                .in(Blocklist::getOwnerAccountId, accountIds)
                .or().in(Blocklist::getBlockedAccountId, accountIds));
        roomMemberMapper.delete(new LambdaQueryWrapper<RoomMember>()
                .in(RoomMember::getAccountId, accountIds));
        accountRoomMapper.delete(new LambdaQueryWrapper<AccountRoom>()
                .in(AccountRoom::getAccountId, accountIds));
        accountInfoMapper.delete(new LambdaQueryWrapper<AccountInfo>()
                .in(AccountInfo::getAccountId, accountIds));
        accountMapper.delete(new LambdaQueryWrapper<Account>().in(Account::getId, accountIds));
        log.info("账号注销：accountId={} deletedAccountIds={}", me.accountId(), accountIds);
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
        if (account == null) {
            throw ApiException.unauthenticated();
        }
        return tokenResponse(account.getId(), account.getType(), info.getDisplayName(), info.getAvatar());
    }

    /** 归属关系本身就是授权：没有授权表，也没有临时凭据。账号密钥形态只换密钥所属账号的凭据。 */
    @Override
    @Transactional
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
            account = accountLocks.require(accountKeys.authenticate(request.accountKey()));
        } else {
            CurrentAccount owner = caller.orElseThrow(ApiException::unauthenticated);
            accountLocks.lockAll(List.of(owner.accountId(), request.accountId()));
            account = ownedAccount(owner, request.accountId());
        }
        AccountInfo info = accountInfoMapper.selectById(account.getId());
        if (info == null) {
            throw ApiException.unauthenticated();
        }
        boolean frozen = FROZEN.equals(info.getStatus());
        // 直写打开后冻结账号仍能拿凭据（只读 + 清角标）；关闭时保持切换前的 403
        if (frozen && !turmsProperties.writeCredentialEnabled()) {
            throw ApiException.accountFrozen();
        }

        TurmsCredentialService.Credential credential = turmsCredentials.sign(account.getId(), frozen);
        // 归属者切账号时顺带签一份该账号的登录 JWT：没有它，切进去之后连 /api 都调不了
        LoginTokenService.Issued loginToken = keyShape ? null : loginTokens.issue(account.getId());
        return new AccountResponses.SessionResponse(account.getId(), info.getDisplayName(), account.getType(),
                info.getAvatar(),
                loginToken == null ? null : loginToken.token(),
                loginToken == null ? null : loginToken.expiresAt(),
                new AccountResponses.SessionResponse.Turms(account.getId(), credential.token(),
                        turmsProperties.gatewayUrl()),
                credential.expiresAt());
    }

    /**
     * 资料全量提交（`PUT`）：三列一次写，名字变了才同步 Turms——名字只是展示，不参与任何判定，
     * 但 Turms 那边也存了一份，所以变了才同步；同步失败整笔回滚（名字与状态都不变）。
     */
    @Override
    @Transactional
    public AccountResponses.AccountProfileResponse updateProfile(CurrentAccount me,
            AccountRequests.UpdateProfileRequest request) {
        accountLocks.require(me.accountId());
        AccountInfo info = accountInfoMapper.selectById(me.accountId());
        if (info == null) {
            throw ApiException.unauthenticated();
        }
        if (FROZEN.equals(info.getStatus())) {
            throw ApiException.accountFrozen();
        }
        LocalDate birthday = parseBirthday(request.birthday());
        boolean nameChanged = !Objects.equals(request.displayName(), info.getDisplayName());

        OffsetDateTime now = OffsetDateTime.now();
        // birthday 清空时必须显式写 null：updateById 会跳过 null 字段，清生日就失效了
        accountInfoMapper.update(null, new LambdaUpdateWrapper<AccountInfo>()
                .eq(AccountInfo::getAccountId, me.accountId())
                .set(AccountInfo::getDisplayName, request.displayName())
                .set(AccountInfo::getGender, request.gender())
                .set(AccountInfo::getBirthday, birthday)
                .set(AccountInfo::getUpdatedAt, now));

        if (nameChanged) {
            turmsAdmin.updateUserName(me.accountId(), request.displayName());
            accountMapper.updateById(Account.builder()
                    .id(me.accountId())
                    .turmsSyncState(TurmsSyncState.SYNCED)
                    .updatedAt(now)
                    .build());
        }

        return new AccountResponses.AccountProfileResponse(me.accountId(), request.displayName(),
                request.gender(), birthday, info.getAvatar(), now.toInstant());
    }

    /** #24 只读自己那一行：不碰 `account` 表、不查好友关系。 */
    @Override
    public AccountResponses.AccountProfileResponse myProfile(CurrentAccount me) {
        AccountInfo info = accountInfoMapper.selectById(me.accountId());
        if (info == null) {
            throw ApiException.unauthenticated();
        }
        return new AccountResponses.AccountProfileResponse(info.getAccountId(), info.getDisplayName(),
                info.getGender(), info.getBirthday(), info.getAvatar(), info.getUpdatedAt().toInstant());
    }

    /**
     * 改头像：`PUT` 语义（整枚替换），`null` = 清回生成的首字头像。
     * 合法 key 按账号类型分：真人 6 张、agent 3 张，跨表由应用层守（issue #10）。
     */
    @Override
    @Transactional
    public AccountResponses.AvatarResponse updateAvatar(CurrentAccount me,
            AccountRequests.AvatarRequest request) {
        Account account = accountLocks.require(me.accountId());
        AccountInfo info = accountInfoMapper.selectById(me.accountId());
        if (info == null) {
            throw ApiException.unauthenticated();
        }
        if (FROZEN.equals(info.getStatus())) {
            throw ApiException.accountFrozen();
        }
        String avatar = request.avatar();
        if (avatar != null) {
            List<String> allowed = AGENT.equals(account.getType()) ? AGENT_AVATARS : HUMAN_AVATARS;
            if (!allowed.contains(avatar)) {
                throw ApiException.validationFailed("avatar",
                        AGENT.equals(account.getType())
                                ? "agent 只能用 agent 的默认头像"
                                : "真人只能用真人的默认头像");
            }
        }
        // avatar 是可空列，清空时必须显式写 null：updateById 会跳过 null 字段
        accountInfoMapper.update(null, new LambdaUpdateWrapper<AccountInfo>()
                .eq(AccountInfo::getAccountId, me.accountId())
                .set(AccountInfo::getAvatar, avatar)
                .set(AccountInfo::getUpdatedAt, OffsetDateTime.now()));
        return new AccountResponses.AvatarResponse(avatar);
    }

    /** 正则只挡形状：日历上不存在的日期与未来日期都在这里挡，`field` 始终指回 `birthday`。 */
    private static LocalDate parseBirthday(String birthday) {
        if (birthday == null) {
            return null;
        }
        LocalDate parsed;
        try {
            parsed = LocalDate.parse(birthday);
        } catch (DateTimeParseException e) {
            throw ApiException.validationFailed("birthday", "birthday 不是合法日期");
        }
        if (parsed.isAfter(LocalDate.now())) {
            throw ApiException.validationFailed("birthday", "生日不能晚于今天");
        }
        return parsed;
    }

    /** 资料页只返回名字、账号 id、头像与是否已是好友；`type`、`email`、归属与时间列一概不出门。 */
    @Override
    public AccountResponses.ProfileResponse profile(CurrentAccount me, long accountId) {
        AccountInfo info = accountInfoMapper.selectById(accountId);
        if (info == null) {
            throw ApiException.notFound("账号不存在");
        }
        return new AccountResponses.ProfileResponse(accountId, info.getDisplayName(), info.getAvatar(),
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

        Map<Long, AccountInfo> infos = accountInfoMapper
                .selectList(new LambdaQueryWrapper<AccountInfo>()
                        .in(AccountInfo::getAccountId, accounts.stream().map(Account::getId).toList()))
                .stream()
                .collect(Collectors.toMap(AccountInfo::getAccountId, info -> info));

        List<AccountResponses.AccountSummary> items = new ArrayList<>(accounts.size());
        accounts.stream()
                .filter(account -> account.getId() == meId)
                .forEach(account -> items.add(summary(account, infos)));
        accounts.stream()
                .filter(account -> account.getId() != meId)
                .forEach(account -> items.add(summary(account, infos)));
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
        if (info == null) {
            throw ApiException.unauthenticated();
        }
        if (FROZEN.equals(info.getStatus())) {
            throw ApiException.accountFrozen();
        }
        return tokenResponse(account.getId(), account.getType(), info.getDisplayName(), info.getAvatar());
    }

    @Override
    public void requireExists(long accountId) {
        if (accountMapper.selectById(accountId) == null) {
            throw ApiException.unauthenticated();
        }
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
        // 建号仍在事务内同步建 Turms 用户；这条事件供读模型被 drop 后重建（派发器先查存在再建）
        projectionEvents.accountCreated(account.getId(), displayName);
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

    private AccountResponses.TokenResponse tokenResponse(long accountId, String type, String displayName,
            String avatar) {
        LoginTokenService.Issued token = loginTokens.issue(accountId);
        return new AccountResponses.TokenResponse(token.token(), token.expiresAt(),
                new AccountResponses.AccountSummary(accountId, type, displayName, avatar));
    }

    private static AccountResponses.AccountSummary summary(Account account, Map<Long, AccountInfo> infos) {
        AccountInfo info = infos.get(account.getId());
        return new AccountResponses.AccountSummary(account.getId(), account.getType(),
                info == null ? null : info.getDisplayName(), info == null ? null : info.getAvatar());
    }
}
