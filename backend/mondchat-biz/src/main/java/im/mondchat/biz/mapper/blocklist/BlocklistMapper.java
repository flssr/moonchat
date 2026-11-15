package im.mondchat.biz.mapper.blocklist;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.mondchat.biz.entity.Blocklist;
import org.apache.ibatis.annotations.Mapper;

/** `blocklist` 的读写：拉黑、取消拉黑与「这个方向是否被拉黑」的判定都走这里。 */
@Mapper
public interface BlocklistMapper extends BaseMapper<Blocklist> {
}
