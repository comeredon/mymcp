---
name: terraform-modernization
description: Step-by-step Terraform upgrade and modernization guide. Use when migrating a Terraform project across major versions (0.12 → 0.13 → 0.14 → 0.15 → 1.0 → 1.7.x), fixing breaking changes, or adopting modern HCL patterns. Never skip a major version step.
---

# Terraform Modernization Skill

## Upgrade Path

Only ever migrate one major version at a time:

```
0.12.x → 0.13.x → 0.14.x → 0.15.x → 1.0.x → 1.7.x
```

## Before Every Version Step

1. **Back up state** (PowerShell):
   ```powershell
   Copy-Item terraform.tfstate "terraform.tfstate.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -ErrorAction SilentlyContinue
   ```
2. Tell the user exactly what version you are switching to and what will change.
3. **Ask for explicit confirmation** before proceeding.

## Per-Version Actions

### 0.12 → 0.13

```bash
terraform 0.13upgrade          # rewrites required_providers with source addresses
terraform init -upgrade
terraform validate
terraform plan -out=tfplan-013
```

**Breaking changes to fix:**
- All providers need an explicit `source` in `required_providers`:
  ```hcl
  terraform {
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 4.0"
      }
    }
    required_version = ">= 0.13"
  }
  ```
- Non-HashiCorp providers must have a full registry address (e.g., `registry.terraform.io/org/provider`).

---

### 0.13 → 0.14

```bash
terraform init -upgrade   # generates .terraform.lock.hcl
terraform validate
terraform plan -out=tfplan-014
```

**Actions:**
- Update `required_version = ">= 0.14"`.
- Commit `.terraform.lock.hcl` to version control — this pins provider checksums.
- Mark sensitive variables:
  ```hcl
  variable "db_password" {
    type      = string
    sensitive = true   # redacts from plan/apply output
  }
  ```
- Check that `terraform.tfvars` is not being loaded twice (it is now auto-loaded).

---

### 0.14 → 0.15

```bash
terraform init -upgrade
terraform validate   # deprecation warnings become ERRORS in 0.15
terraform plan -out=tfplan-015
```

**Breaking changes to fix:**

| Deprecated pattern | Replacement |
|--------------------|-------------|
| `list(string)` type constraint shorthand `list` | `list(string)` (explicit) |
| `map` shorthand | `map(string)` (explicit) |
| `null_resource` without `triggers` | Add `triggers = {}` explicitly |

- Outputs that expose sensitive values must declare `sensitive = true`:
  ```hcl
  output "connection_string" {
    value     = local.db_url
    sensitive = true
  }
  ```
- Several legacy functions were removed — run `terraform validate` and address each error individually.

---

### 0.15 → 1.0

```bash
terraform init -upgrade
terraform validate
terraform plan -out=tfplan-100
```

**Actions:**
- Update `required_version = ">= 1.0"`.
- This version is intentionally backward-compatible with 0.15 — the step is mostly a version constraint bump.
- Review plan output carefully; no resource should be destroyed unless expected.

---

### 1.0 → 1.7.x

```bash
terraform init -upgrade
terraform validate
terraform plan -out=tfplan-173
```

**Actions:**
- Update `required_version = ">= 1.7"` (or pin: `"= 1.7.3"`).
- Optional new features to adopt (non-breaking):

  **`import` block (GA)** — declarative resource import:
  ```hcl
  import {
    to = aws_s3_bucket.my_bucket
    id = "my-existing-bucket"
  }
  ```

  **`removed` block** — remove from state without destroying:
  ```hcl
  removed {
    from = aws_instance.old_server
    lifecycle { destroy = false }
  }
  ```

  **`terraform test` framework** — write `.tftest.hcl` files:
  ```hcl
  run "s3_bucket_exists" {
    command = plan
    assert {
      condition     = aws_s3_bucket.main.bucket == "my-app-bucket"
      error_message = "Unexpected bucket name."
    }
  }
  ```

  **Provider-defined functions** — call functions shipped by providers:
  ```hcl
  output "arn_region" {
    value = provider::aws::arn_parse(aws_s3_bucket.main.arn).region
  }
  ```

---

## Modern HCL Patterns (apply at any version ≥ 1.0)

### Explicit `required_providers` with version constraints

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
```

### Variable validation

```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be dev, staging, or prod."
  }
}
```

### `for_each` over `count` for named resources

```hcl
# Prefer this
resource "azurerm_resource_group" "envs" {
  for_each = toset(["dev", "staging", "prod"])
  name     = "rg-${each.key}"
  location = var.location
}

# Avoid this (index-based, brittle on deletion)
resource "azurerm_resource_group" "envs" {
  count    = 3
  name     = "rg-${count.index}"
  location = var.location
}
```

### Locals for computed values

```hcl
locals {
  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}
```

### Moved blocks (1.1+) — rename resources without destroy

```hcl
moved {
  from = azurerm_resource_group.old_name
  to   = azurerm_resource_group.new_name
}
```

---

## State Safety Rules

- **NEVER edit `.tfstate` files manually** — only the Terraform CLI may modify state.
- **NEVER run `terraform apply` without a confirmed `terraform plan` first.**
- Always store state remotely in production (Azure Blob, S3, Terraform Cloud):
  ```hcl
  terraform {
    backend "azurerm" {
      resource_group_name  = "rg-terraform-state"
      storage_account_name = "tfstate12345"
      container_name       = "tfstate"
      key                  = "prod.terraform.tfstate"
    }
  }
  ```
- Use state locking (enabled by default for Azure/S3 backends).

---

## Upgrade Checklist

Before marking a version step complete, verify all of the following:

- [ ] State backed up with timestamp
- [ ] `required_version` updated in `versions.tf` / `main.tf`
- [ ] `terraform init -upgrade` ran without errors
- [ ] `terraform validate` exits with `Success!`
- [ ] `terraform plan` shows no unexpected destroy operations
- [ ] `.terraform.lock.hcl` committed (0.14+)
- [ ] Breaking-change patterns fixed for this version step
- [ ] User confirmed plan output before proceeding

---

## Tooling Recommendations

| Tool | Purpose |
|------|---------|
| `tfenv` / `tfswitch` | Manage multiple Terraform binary versions side-by-side |
| `terraform fmt` | Auto-format HCL to canonical style |
| `terraform validate` | Catch syntax and type errors without a backend |
| `tflint` | Provider-aware linting (e.g., deprecated arguments) |
| `checkov` | Static security/compliance scanning of `.tf` files |
| `infracost` | Cost estimation from plan output |

---

## Anti-Patterns to Avoid

- Skipping a major version in the upgrade path
- Running `terraform apply` before reviewing `terraform plan`
- Hard-coding credentials in `.tf` files — use environment variables or a secrets backend
- Using `count` for named resources (prefer `for_each`)
- Ignoring `.terraform.lock.hcl` in version control
- Storing state locally in production
- Using `terraform taint` (deprecated in 1.0 — use `terraform apply -replace` instead)
