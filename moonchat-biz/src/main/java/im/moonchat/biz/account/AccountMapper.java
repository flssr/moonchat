package im.moonchat.biz.account;

import java.util.List;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

/**
 * 身份聚合的读写（`account` + `account_info`）。S1 只需要这几条 SQL，不建实体类。
 * 结果直接映射到 record：列别名用双引号驼峰，避免 PG 把未加引号的别名折成小写。
 */
@Mapper
public interface AccountMapper {

    @Select("select count(*) from account_info where email = #{email}")
    long countByEmail(@Param("email") String email);

    @Select("insert into account (type) values ('human') returning id")
    long insertHumanAccount();

    @Insert("""
            insert into account_info (account_id, display_name, email, credential_hash)
            values (#{accountId}, #{displayName}, #{email}, #{credentialHash})
            """)
    void insertHumanInfo(@Param("accountId") long accountId,
            @Param("displayName") String displayName,
            @Param("email") String email,
            @Param("credentialHash") String credentialHash);

    @Update("update account set turms_sync_state = 'synced', updated_at = now() where id = #{accountId}")
    void markSynced(@Param("accountId") long accountId);

    @Select("""
            select a.id as "accountId", a.type as "type", i.display_name as "displayName",
                   i.credential_hash as "credentialHash", i.status as "status"
            from account a
            join account_info i on i.account_id = a.id
            where i.email = #{email}
            """)
    LoginRow findByEmail(@Param("email") String email);

    @Select("""
            select a.id as "accountId", a.type as "type", i.display_name as "displayName",
                   a.owner_account_id as "ownerAccountId", i.status as "status"
            from account a
            join account_info i on i.account_id = a.id
            where a.id = #{accountId}
            """)
    AccountRow findById(@Param("accountId") long accountId);

    @Select("""
            select a.id as "accountId", a.type as "type", i.display_name as "displayName"
            from account a
            join account_info i on i.account_id = a.id
            where a.id = #{me} or a.owner_account_id = #{me}
            order by (a.id = #{me}) desc, a.created_at asc
            """)
    List<AccountSummaryRow> findMine(@Param("me") long me);

    record LoginRow(long accountId, String type, String displayName, String credentialHash, String status) {
    }

    record AccountRow(long accountId, String type, String displayName, Long ownerAccountId, String status) {
    }

    record AccountSummaryRow(long accountId, String type, String displayName) {
    }
}
