---
name: code-scanning
description: Security scanning patterns and vulnerability assessment for Java applications. Use when performing security reviews or setting up automated security scanning.
---

# Code Security Scanning

## OWASP Top 10 Checklist for Java

1. **Injection** — Use parameterized queries, validate all input
2. **Broken Authentication** — Use strong password hashing, session management
3. **Sensitive Data Exposure** — Encrypt data at rest/transit, no hardcoded secrets
4. **XXE** — Disable external entity processing in XML parsers
5. **Broken Access Control** — Enforce authorization on every endpoint
6. **Security Misconfiguration** — Remove defaults, disable unused features
7. **XSS** — Encode output, validate input, use Content Security Policy
8. **Insecure Deserialization** — Validate input types, avoid native serialization
9. **Known Vulnerabilities** — Run `mvn dependency-check:check`
10. **Insufficient Logging** — Log security events, protect log integrity

## Dependency Scanning

```bash
# OWASP Dependency Check
mvn dependency-check:check

# Fail on HIGH/CRITICAL
mvn dependency-check:check -DfailBuildOnCVSS=7
```

## Container Scanning

```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 myapp:latest
```

## Secret Detection

- Never commit passwords, API keys, or tokens
- Use environment variables or secret managers
- Scan with: `trufflehog git file://. --since-commit HEAD~10`

## Report Structure

1. Executive Summary (overall posture, critical count, risk level)
2. Findings by severity (Critical → Low) with file/line, description, fix
3. Best Practices Review
4. Dependency Analysis
5. Prioritized Action Items
