---
name: github-actions
description: GitHub Actions workflow patterns for Java CI/CD pipelines. Use when creating or modifying build, test, and deployment workflows.
---

# GitHub Actions for Java

## Java CI Pipeline

```yaml
name: Java CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
          cache: 'maven'
      - run: mvn clean verify
      - uses: actions/upload-artifact@v3
        with:
          name: app-jar
          path: target/*.jar
```

## Docker Build and Push

```yaml
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
- uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
```

## Optimization Tips

- Cache Maven: `actions/setup-java` with `cache: 'maven'`
- Run lint, test, security in parallel jobs
- Use `needs:` to chain dependent jobs
- Use matrix builds for multi-version testing

## Secrets Management

- Store in Settings → Secrets and variables → Actions
- Reference as `${{ secrets.SECRET_NAME }}`
- Never commit secrets to git
