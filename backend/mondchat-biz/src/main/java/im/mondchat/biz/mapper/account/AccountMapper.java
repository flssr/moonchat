package im.mondchat.biz.mapper.account;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.mondchat.biz.entity.Account;
import org.apache.ibatis.annotations.Mapper;

/** `account` 表的读写。S1 的条件全是简单等值，用 BaseMapper + Wrapper 就够。 */
@Mapper
public interface AccountMapper extends BaseMapper<Account> {
}
