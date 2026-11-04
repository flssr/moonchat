package im.moonchat.biz.mapper.account;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.moonchat.biz.entity.AccountInfo;
import org.apache.ibatis.annotations.Mapper;

/** `account_info` 表的读写。邮箱与认证哈希的唯一性由 DDL 兜底，这里只做查询。 */
@Mapper
public interface AccountInfoMapper extends BaseMapper<AccountInfo> {
}
