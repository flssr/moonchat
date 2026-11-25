package im.mondchat.biz.service.account;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import im.mondchat.biz.common.ApiException;
import im.mondchat.biz.entity.Account;
import im.mondchat.biz.mapper.account.AccountMapper;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/** 写入口按账号 id 加行锁，和注销硬删串行；多账号时固定顺序，避免互相死锁。 */
@Component
@RequiredArgsConstructor
public class AccountLockService {

    private final AccountMapper accounts;

    public Account lock(long accountId) {
        return accounts.selectOne(new LambdaQueryWrapper<Account>()
                .eq(Account::getId, accountId)
                .last("for update"));
    }

    public Account require(long accountId) {
        Account account = lock(accountId);
        if (account == null) {
            throw ApiException.notFound("账号不存在");
        }
        return account;
    }

    public Map<Long, Account> lockAll(Collection<Long> accountIds) {
        Map<Long, Account> locked = new LinkedHashMap<>();
        accountIds.stream().distinct().sorted().forEach(accountId -> locked.put(accountId, require(accountId)));
        return locked;
    }
}
