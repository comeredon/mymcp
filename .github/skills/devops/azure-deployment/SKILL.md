---
name: azure-deployment
description: Azure deployment strategies for Java applications including blue-green and canary patterns. Use when deploying to Azure App Service or configuring deployment slots.
---

# Azure Deployment Strategies

> **Related skills:** `devops/github-actions`, `devops/docker`, `devops/cicd-practices`

## Basic Deployment

```bash
az webapp create --name $APP --resource-group $RG --plan $PLAN --runtime "JAVA:21-java21"
az webapp deploy --name $APP --resource-group $RG --src-path target/app.jar --type jar
```

## Blue-Green with Slots (Zero Downtime)

```bash
# Create staging slot
az webapp deployment slot create --name $APP --resource-group $RG --slot staging
# Deploy to staging
az webapp deploy --name $APP --resource-group $RG --slot staging --src-path target/app.jar
# Test staging, then swap
az webapp deployment slot swap --name $APP --resource-group $RG --slot staging
```

## Canary Deployment (Gradual Rollout)

```bash
az webapp traffic-routing set --name $APP --resource-group $RG --distribution staging=10
# Monitor, then increase
az webapp traffic-routing set --name $APP --resource-group $RG --distribution staging=50
# Complete rollout
az webapp deployment slot swap --name $APP --resource-group $RG --slot staging
az webapp traffic-routing clear --name $APP --resource-group $RG
```

## Rollback

```bash
az webapp deployment slot swap --name $APP --resource-group $RG --slot production --target-slot staging
```

## Monitoring

```bash
az webapp log tail --name $APP --resource-group $RG
```

## Checklist

- [ ] Deploy to staging slot first
- [ ] Run smoke tests against staging
- [ ] Swap only after verification
- [ ] Have rollback plan ready
- [ ] Enable Application Insights
