package im.moonchat.biz.mapper.room;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.moonchat.biz.entity.RoomInfo;
import org.apache.ibatis.annotations.Mapper;

/** `room_info` 的读写：建群、群资料、投影状态与 `turms_group_id` 回填都走这里。 */
@Mapper
public interface RoomInfoMapper extends BaseMapper<RoomInfo> {
}
