FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /workspace

COPY pom.xml .
COPY moonchat-biz/pom.xml moonchat-biz/
COPY moonchat-connector/pom.xml moonchat-connector/
RUN mvn -B -pl moonchat-biz -am dependency:go-offline

COPY moonchat-biz/src moonchat-biz/src
RUN mvn -B -pl moonchat-biz -am package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /opt/moonchat

RUN useradd --system --uid 10001 moonchat
COPY --from=build /workspace/moonchat-biz/target/moonchat-biz-0.1.0-SNAPSHOT.jar app.jar

USER moonchat
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/opt/moonchat/app.jar"]
