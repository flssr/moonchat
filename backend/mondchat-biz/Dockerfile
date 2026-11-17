FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

COPY backend/pom.xml pom.xml
COPY backend/mondchat-biz/pom.xml mondchat-biz/pom.xml
RUN mvn -B -pl mondchat-biz -am dependency:go-offline

COPY backend/mondchat-biz/src mondchat-biz/src
RUN mvn -B -pl mondchat-biz -am package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /opt/mondchat

# logback 往相对路径 logs/ 写滚动文件（WORKDIR 就是 /opt/mondchat），这个目录不存在时
# 非 root 用户建不出来，Spring Boot 判定日志初始化失败直接退出。用数字 uid:gid 建，
# 不依赖镜像里有没有同名组（`useradd --system` 不保证建组，写 `mondchat:mondchat` 可能直接构建失败）。
RUN useradd --system --uid 10001 mondchat \
    && mkdir -p /opt/mondchat/logs \
    && chown -R 10001:10001 /opt/mondchat

COPY --from=build /workspace/mondchat-biz/target/mondchat-biz-0.1.0-SNAPSHOT.jar app.jar

USER mondchat
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/opt/mondchat/app.jar"]
