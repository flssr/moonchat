package im.moonchat.biz.mapper.friendship;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.moonchat.biz.entity.FriendshipReverse;
import org.apache.ibatis.annotations.Mapper;

/** `friendship_reverse`（查询镜像）的读写：只服务「按较大账号 id 查列表」，不参与授权。 */
@Mapper
public interface FriendshipReverseMapper extends BaseMapper<FriendshipReverse> {
}
