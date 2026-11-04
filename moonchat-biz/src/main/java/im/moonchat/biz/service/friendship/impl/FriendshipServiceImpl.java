package im.moonchat.biz.service.friendship.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.moonchat.biz.entity.Friendship;
import im.moonchat.biz.mapper.friendship.FriendshipMapper;
import im.moonchat.biz.service.friendship.FriendshipService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class FriendshipServiceImpl implements FriendshipService {

    private static final String ACCEPTED = "accepted";

    private final FriendshipMapper friendshipMapper;

    @Override
    public boolean areFriends(long one, long another) {
        long lower = Math.min(one, another);
        long higher = Math.max(one, another);
        return friendshipMapper.selectCount(new LambdaQueryWrapper<Friendship>()
                .eq(Friendship::getAccountId, lower)
                .eq(Friendship::getPeerAccountId, higher)
                .eq(Friendship::getStatus, ACCEPTED)
                .isNull(Friendship::getDeletedAt)) > 0;
    }
}
