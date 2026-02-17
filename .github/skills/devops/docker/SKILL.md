---
name: docker
description: Docker containerization best practices for Java 21 applications. Use when creating Dockerfiles, optimizing images, or setting up container security.
---

# Docker Containerization for Java

## Multi-Stage Build (Recommended)

```dockerfile
# Build stage
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

# Runtime stage
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -g 1001 appgroup && adduser -D -u 1001 -G appgroup appuser
COPY --from=build /app/target/*.jar app.jar
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD java -version || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
```

## JVM Container Options

```
-XX:+UseContainerSupport
-XX:MaxRAMPercentage=75.0
-XX:+UseG1GC
```

## .dockerignore

```
target/
.git/
.github/
*.md
src/test/
.env
*.key
*.pem
```

## Security Checklist

- [ ] Use multi-stage build (no build tools in production)
- [ ] Run as non-root user
- [ ] Use Alpine-based JRE image
- [ ] Scan with Trivy: `trivy image --severity HIGH,CRITICAL myapp:latest`
- [ ] Never store secrets in images
- [ ] Use specific version tags (not `latest` in production)
