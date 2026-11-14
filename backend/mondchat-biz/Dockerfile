FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

COPY backend/pom.xml pom.xml
COPY backend/mondchat-biz/pom.xml mondchat-biz/pom.xml
RUN mvn -B -pl mondchat-biz -am dependency:go-offline

COPY backend/mondchat-biz/src mondchat-biz/src
RUN mvn -B -pl mondchat-biz -am package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /opt/mondchat

RUN useradd --system --uid 10001 mondchat
COPY --from=build /workspace/mondchat-biz/target/mondchat-biz-0.1.0-SNAPSHOT.jar app.jar

USER mondchat
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/opt/mondchat/app.jar"]
