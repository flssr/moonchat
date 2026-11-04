package im.moonchat.biz.mapper.friendship;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.moonchat.biz.entity.Friendship;
import org.apache.ibatis.annotations.Mapper;

/** `friendship`（主表）的读写：申请、同意、拒绝、删除与授权判定都走这里。 */
@Mapper
public interface FriendshipMapper extends BaseMapper<Friendship> {
}
