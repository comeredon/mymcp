---
name: cicd-practices
description: General CI/CD best practices for pipeline design, quality gates, and deployment verification. Use when designing or improving CI/CD workflows.
---

# CI/CD Best Practices

## Pipeline Stages (Recommended Order)

1. Lint/formatting (seconds)
2. Unit tests (1-3 min)
3. Static analysis + security scan (parallel)
4. Integration tests (3-10 min)
5. Build artifacts
6. Deploy to staging
7. Smoke tests
8. Deploy to production (manual approval)

## Quality Gates

### Pre-Merge (Pull Requests)
- All tests pass
- Code review approved
- Coverage threshold met (≥80%)
- No HIGH/CRITICAL vulnerabilities
- Build succeeds

### Pre-Deployment
- Staging tests pass
- Smoke tests pass
- Manual approval obtained
- Rollback plan verified

## Build Optimization

- Cache dependencies (`~/.m2/repository`)
- Run independent jobs in parallel
- Use incremental builds when possible
- Keep build time under 10 minutes

## Deployment Verification

```bash
# Health check loop
for i in {1..10}; do
  curl -f https://myapp.com/health && exit 0
  sleep 10
done
exit 1
```

## Anti-Patterns to Avoid

- Manual deployment steps
- Long builds (>15 min)
- No rollback plan
- Deploying without testing
- Secrets in code
- No monitoring after deployment

## DORA Metrics

- Deployment Frequency → multiple times/day
- Lead Time → < 1 day
- MTTR → < 1 hour
- Change Failure Rate → < 15%
