package im.mondchat.biz.mapper.room;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.mondchat.biz.entity.RoomMember;
import org.apache.ibatis.annotations.Mapper;

/** `room_member` 的读写：成员列表、发送授权与 Turms 投影的唯一读取源。 */
@Mapper
public interface RoomMemberMapper extends BaseMapper<RoomMember> {
}
