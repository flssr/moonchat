package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

/**
 * `/v3/api-docs` 的运行时校验：接口文档由 controller 与 DTO 生成，不写入仓库。
 */
class OpenApiDocTest extends ApiTestSupport {

    @Test
    void 运行时OpenAPI包含全部业务路由() throws Exception {
        String body = mockMvc.perform(get("/v3/api-docs"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        ObjectMapper mapper = new ObjectMapper();
        JsonNode paths = mapper.readTree(body).path("paths");
        int operations = 0;
        for (JsonNode path : paths) {
            for (JsonNode operation : path) {
                if (operation.isObject()) {
                    operations++;
                }
            }
        }
        assertThat(operations).isEqualTo(24);
    }
}
