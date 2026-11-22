package im.mondchat.turms.plugin.ratelimit;

import java.util.Set;
import im.turms.server.common.infra.plugin.TurmsExtension;
import im.turms.server.common.infra.plugin.TurmsPlugin;

/** 插件入口：只声明一个扩展（发送限流）。描述信息在 `plugin.yaml`。 */
public class MondChatRateLimitPlugin extends TurmsPlugin {

    @Override
    public Set<Class<? extends TurmsExtension>> getExtensions() {
        return Set.of(RateLimitExtension.class);
    }
}
