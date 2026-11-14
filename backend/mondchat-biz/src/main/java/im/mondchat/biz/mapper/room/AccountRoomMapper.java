package im.mondchat.biz.mapper.room;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.mondchat.biz.entity.AccountRoom;
import org.apache.ibatis.annotations.Mapper;

/** `account_room` 的读写：只为「我加入的群」这条查询服务，与 `room_member` 同事务双写。 */
@Mapper
public interface AccountRoomMapper extends BaseMapper<AccountRoom> {
}
