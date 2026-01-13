FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
# Kopiuj skompilowany jar (sbt assembly) z katalogu target
COPY target/scala-*/app-assembly-*.jar app.jar
# Fallback: skopiuj dowolny jar (jeśli inna nazwa)
COPY target/scala-*/*.jar app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
