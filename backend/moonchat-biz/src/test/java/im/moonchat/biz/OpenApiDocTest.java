package im.moonchat.biz;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.core.util.DefaultIndenter;
import com.fasterxml.jackson.core.util.DefaultPrettyPrinter;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * `docs/openapi.json` 的生成器与校验器：文件由 `/v3/api-docs` 落盘而来，不是手写的。
 *
 * <p>重新生成（改了控制器或 DTO 之后跑一次，再把文件一起提交）：{@code
 * ./mvnw -pl moonchat-biz -Dtest=OpenApiDocTest -Dmoonchat.openapi.write=true test}
 *
 * <p>不带该参数时只校验：文件与代码不一致就让构建失败，等于把「文档过期」变成一条红灯。
 */
class OpenApiDocTest extends ApiTestSupport {

    private static final String WRITE = "moonchat.openapi.write";

    @Test
    void 仓库里的openapi文件与代码一致() throws Exception {
        String body = mockMvc.perform(get("/v3/api-docs"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        ObjectMapper mapper = new ObjectMapper();
        // 行尾固定成 LF：仓库里统一 LF，Windows 上生成的也要一样，否则漂移校验跨平台就假红
        // （数组保持默认的紧凑写法，只换缩进符的换行）
        DefaultPrettyPrinter printer = new DefaultPrettyPrinter()
                .withObjectIndenter(new DefaultIndenter("  ", "\n"));
        String rendered = mapper.writer(printer).writeValueAsString(mapper.readTree(body)) + "\n";

        Path file = repoRoot().resolve("docs").resolve("openapi.json");
        if (Boolean.getBoolean(WRITE)) {
            Files.writeString(file, rendered, StandardCharsets.UTF_8);
            return;
        }

        assertThat(Files.readString(file, StandardCharsets.UTF_8))
                .as("docs/openapi.json 已过期：./mvnw -pl moonchat-biz -Dtest=OpenApiDocTest "
                        + "-Dmoonchat.openapi.write=true test，然后把文件一起提交")
                .isEqualTo(rendered);
    }

    /** 测试的工作目录是模块目录，往上找到仓库根（以 docs/truth 为准）。 */
    private static Path repoRoot() {
        for (Path dir = Path.of("").toAbsolutePath(); dir != null; dir = dir.getParent()) {
            if (Files.exists(dir.resolve("docs").resolve("truth").resolve("README.md"))) {
                return dir;
            }
        }
        throw new IllegalStateException("找不到仓库根目录");
    }
}
