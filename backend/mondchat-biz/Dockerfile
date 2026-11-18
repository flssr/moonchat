FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

COPY backend/pom.xml pom.xml
COPY backend/mondchat-biz/pom.xml mondchat-biz/pom.xml
RUN mvn -B -pl mondchat-biz -am dependency:go-offline

COPY backend/mondchat-biz/src mondchat-biz/src
RUN mvn -B -pl mondchat-biz -am package -DskipTests

# 按层拆开：dependencies 是第三方 jar，application 是每次提交都会变的那部分。
# Spring Boot 4 的 tools 提取结果是瘦 jar + lib/ 布局（Main-Class 直接是应用类，
# Class-Path 指向 lib/），不需要 JarLauncher 包一层，所以入口就是 java -jar。
RUN java -Djarmode=tools -jar mondchat-biz/target/mondchat-biz-*.jar extract --layers --destination /workspace/extracted \
    && mv /workspace/extracted/application/mondchat-biz-*.jar /workspace/extracted/application/app.jar

FROM eclipse-temurin:21-jre-alpine
WORKDIR /opt/mondchat

# logback 往相对路径 logs/ 写滚动文件（WORKDIR 就是 /opt/mondchat），这个目录不存在时
# 非 root 用户建不出来，Spring Boot 判定日志初始化失败直接退出。alpine 没有 useradd，
# 用 busybox 的 adduser；属主一律写数字 uid:gid，不依赖同名组是否存在。
RUN adduser -D -u 10001 mondchat \
    && mkdir -p /opt/mondchat/logs \
    && chown -R 10001:10001 /opt/mondchat

# 依赖层在前、application 最后：每次提交只有最后这层变，GHCR 里新增的存储就是它。
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./

USER mondchat
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/opt/mondchat/app.jar"]
