# 自研限流插件打进 turms-service 镜像：基础层仍是上游 pinned digest，只多一层插件 jar。
# 用独立 workflow（.github/workflows/turms-plugin.yml）构建，因为要编 vendor/turms（约 20 分钟），
# 不能塞进每次 push 都跑的 CD。
#
# 关键：容器里编 vendor 必须 -Dmaven.test.skip=true。-DskipTests 挡不住
# ElasticsearchManagerTests（它要起 docker compose，构建容器里没有 docker socket）。
#
# 构建：docker build -f infra/turms/Dockerfile -t <tag> .
# 前提：vendor/turms 子模块已初始化（CI 里 checkout 用 submodules: recursive）。
ARG TURMS_SERVICE_IMAGE=ghcr.io/turms-im/turms-service@sha256:2be538a0607c8a7b5538b4429466341944d7f3c585c61f137056b31681e2399c

# 两个 Maven 命令共用的参数：仓库抖动时重试，别让一次 TLS 失败整轮报废。
FROM maven:3.9-eclipse-temurin-25 AS plugin-build
ENV MVN_FLAGS="-B -Dmaven.wagon.http.retryHandler.count=5 -Dmaven.javadoc.skip=true -Dmaven.source.skip=true"
WORKDIR /workspace
COPY vendor/turms /workspace/vendor/turms
COPY backend/mondchat-turms-plugin /workspace/backend/mondchat-turms-plugin
RUN --mount=type=cache,target=/root/.m2 \
    cd /workspace/vendor/turms \
    && mvn $MVN_FLAGS install -Dmaven.test.skip=true \
        -Dcheckstyle.skip=true -Dmaven.gitcommitid.skip=true -pl turms-service -am \
    && cd /workspace/backend/mondchat-turms-plugin \
    && mvn $MVN_FLAGS package

FROM ${TURMS_SERVICE_IMAGE}
# 插件目录是容器里的 $TURMS_SERVICE_HOME/plugins，不是镜像根的 /opt/turms/plugins。
COPY --from=plugin-build /workspace/backend/mondchat-turms-plugin/target/mondchat-turms-plugin.jar \
     /opt/turms/turms-service/plugins/
