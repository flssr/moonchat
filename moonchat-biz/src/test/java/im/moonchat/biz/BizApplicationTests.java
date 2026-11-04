package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessException;

/**
 * 上下文装配与迁移结果：PG 与 Redis 都跑在容器里，迁移由 Flyway 在启动时执行。
 * 镜像版本跟 Turms 自带的 compose 对齐（Redis 8.0.3）；PostgreSQL 用 17，spec 未钉版本。
 */
class BizApplicationTests extends ApiTestSupport {

    @Test
    void 上下文装配起来() {
        assertThat(mockMvc).isNotNull();
        assertThat(jdbc).isNotNull();
    }

    @Test
    void 三个迁移文件建齐七张表() {
        List<String> tables = jdbc.queryForList("""
                select table_name from information_schema.tables
                where table_schema = 'public' and table_name <> 'flyway_schema_history'
                order by table_name
                """, String.class);

        assertThat(tables).containsExactly(
                "account", "account_info", "account_room",
                "friendship", "friendship_reverse",
                "room_info", "room_member");
    }

    @Test
    void 规范序与唯一约束真的生效() {
        // 好友主表要求小 id 在前
        assertThatThrownBy(() -> jdbc.update("""
                insert into friendship (account_id, peer_account_id, status, requested_by)
                values (9, 3, 'pending', 9)
                """))
                .isInstanceOf(DataAccessException.class);

        // 真人邮箱唯一
        jdbc.update("""
                insert into account_info (account_id, display_name, email, credential_hash)
                values (90001, '重复邮箱 a', 'dup@example.com', 'bcrypt$2a$10$dupa')
                """);
        assertThatThrownBy(() -> jdbc.update("""
                insert into account_info (account_id, display_name, email, credential_hash)
                values (90002, '重复邮箱 b', 'dup@example.com', 'bcrypt$2a$10$dupb')
                """))
                .isInstanceOf(DataAccessException.class);
    }
}
