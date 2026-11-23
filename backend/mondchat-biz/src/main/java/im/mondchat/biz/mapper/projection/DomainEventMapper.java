package im.mondchat.biz.mapper.projection;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import im.mondchat.biz.entity.DomainEvent;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Options;

/** `domain_event` 的读写：派发、重试、清理与对账补事件都走这里。 */
@Mapper
public interface DomainEventMapper extends BaseMapper<DomainEvent> {

    /**
     * 显式 `cast(#{payload} as jsonb)`：JDBC 把 String 当 varchar，PostgreSQL 不接受隐式转 jsonb。
     * 用自定义 insert 而不是 `BaseMapper.insert`，只为这一处转换，其余读写仍用 Wrapper。
     */
    @Insert("""
            insert into domain_event (aggregate_type, aggregate_id, event_type, payload,
                                      created_at, attempt_count, next_attempt_at)
            values (#{aggregateType}, #{aggregateId}, #{eventType}, cast(#{payload} as jsonb),
                    #{createdAt}, #{attemptCount}, #{nextAttemptAt})
            """)
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insertEvent(DomainEvent event);
}
