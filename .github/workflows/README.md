# GitHub Workflows

This repository includes automated GitHub Actions workflows for security analysis and code remediation.

## Workflows Overview

### 1. Security Review for Java Code (Agentic Workflow)
**File:** `.github/workflows/security-review-java.md`

An AI-powered agentic workflow that automatically performs security scanning and creates PRs with fixes when Java code is added.

**Trigger:** Push to main branch with commit message containing "adding java" (case-insensitive)

**What It Does:**
1. Checks commit messages for "adding java" keyword
2. Invokes the SecurityAgent (`my-security`) to scan Java code for vulnerabilities
3. Reviews the security report
4. If vulnerabilities are found, invokes the DeveloperAgent (`my-developer`) to fix them
5. Creates a Pull Request with the security fixes

**Key Features:**
- Sequential agent coordination (security scan → developer fix → PR creation)
- Smart filtering - only runs when Java code is mentioned in commits
- Transparent operation - uses `noop` safe output when no work is needed
- Automated remediation - fixes are applied automatically and submitted as PR

**Safe Outputs:**
- `create-pull-request` - Creates PR with security fixes
- `noop` - Signals completion when no action is needed

**Permissions:**
- `contents: read` - To read repository code
- `issues: read` - For GitHub API access
- `pull-requests: read` - For GitHub API access

**How to Use:**
1. Push Java code changes to main branch
2. Include "adding java" anywhere in your commit message
3. The workflow will automatically run security analysis
4. Review the created PR for security fixes

**Example Commit Message:**
```
feat: adding java implementation of customer service
```

### 2. Security Scan Workflow (Traditional)

## Overview

The `security-scan.yml` workflow is a traditional GitHub Actions workflow that triggers on every push to main branch. It invokes the SecurityAgent custom agent to perform a comprehensive security analysis of the codebase.

## What It Does

When code is committed to the main branch, the workflow:

1. **Checks out the repository** - Fetches the latest code from the main branch
2. **Creates a timestamped branch** - Generates a new branch named `security-scan-YYYYMMDD-HHMMSS`
3. **Invokes SecurityAgent** - Uses the GitHub Copilot CLI (`@github/copilot`) to run the SecurityAgent prompt
4. **Analyzes the code** - SecurityAgent scans for:
   - SQL Injection vulnerabilities
   - Cross-Site Scripting (XSS) issues
   - Cross-Site Request Forgery (CSRF) vulnerabilities
   - Authentication and authorization flaws
   - Hardcoded secrets or credentials
   - Insecure cryptography implementations
   - Path traversal vulnerabilities
   - Input validation issues
   - And other security risks
5. **Generates security reports** - Creates detailed reports in the `security-reports/` directory
6. **Commits and pushes results** - Pushes the security scan results to the new branch

## Workflow File

Location: `.github/workflows/security-scan.yml`

### Trigger

```yaml
on:
  push:
    branches:
      - main
```

The workflow runs automatically on every push to the main branch.

### Permissions

The workflow requires:
- `contents: write` - To create branches and commit results
- `pull-requests: write` - For future PR creation capabilities

## Security Reports

Security analysis reports are generated in the `/security-reports/` directory on the newly created branch. Each report includes:

- **Executive Summary** - Overall security posture and risk level
- **Vulnerability Findings** - Detailed list of issues by severity (Critical, High, Medium, Low)
- **Recommendations** - Specific remediation steps for each finding
- **Best Practices Review** - Compliance with security standards

## Reviewing Results

After the workflow completes:

1. Check the Actions tab for the workflow run summary
2. Look for the newly created `security-scan-YYYYMMDD-HHMMSS` branch
3. Review the security reports in the `security-reports/` directory
4. Address any Critical or High severity findings
5. Follow the remediation recommendations provided

## Custom Agent

The workflow uses the **SecurityAgent** custom agent defined in `.github/agents/my-security.agent.md`. This agent specializes in:

- Java security code analysis
- OWASP Top 10 vulnerability detection
- Secure coding practices validation
- Dependency vulnerability scanning

## Manual Execution

While the workflow runs automatically, you can also manually trigger security scans:

```bash
gh workflow run security-scan.yml
```

## Troubleshooting

If the workflow fails:

1. Check the Actions tab for error logs
2. Ensure the repository secret `GITHUBCOPILTOKEN` is set (a token for a user with Copilot access)
3. Verify GitHub CLI (`gh`) is available (used to open the PR)
4. Ensure the SecurityAgent definition exists in `.github/agents/my-security.agent.md`
5. Check repository permissions for branch creation and pushing

## Notes

- The workflow creates a new branch for each scan to preserve history
- No changes are made to the main branch automatically
- Security findings should be reviewed and addressed before merging code
- The workflow summary provides quick status in the Actions tab

---

## Comparison: Agentic vs Traditional Workflows

| Feature | Security Review (Agentic) | Security Scan (Traditional) |
|---------|---------------------------|----------------------------|
| **Trigger** | Push with "adding java" | Every push to main |
| **Security Scan** | ✓ SecurityAgent | ✓ SecurityAgent |
| **Automatic Fixes** | ✓ DeveloperAgent | ✗ Manual |
| **PR Creation** | ✓ Automated | ✗ Manual |
| **Selective Execution** | ✓ Commit message filter | ✗ Runs always |
| **AI Coordination** | ✓ Multi-agent | ✓ Single agent |

## GitHub Agentic Workflows

The `security-review-java` workflow uses GitHub Agentic Workflows (gh-aw), which enables:
- Natural language workflow definitions in markdown
- AI agent coordination and task delegation
- Safe outputs for GitHub API interactions
- Sequential agent execution with state management

To modify agentic workflows:
1. Edit the `.md` file (e.g., `.github/workflows/security-review-java.md`)
2. Run `gh aw compile <workflow-name>` to regenerate the lock file
3. Commit both the `.md` and `.lock.yml` files

For more information: https://github.github.com/gh-aw/
