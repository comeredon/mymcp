# Security Guidelines

## 🔒 Protecting Your Secrets

This repository is designed to be safely published publicly. All sensitive information should be stored in environment variables, **never** committed to the repository.

## ✅ What's Safe to Commit

- `.env.example` - Template file with placeholder values
- Configuration files that use environment variable references (e.g., `${MCP_SERVER_URL}`)
- Infrastructure as Code (Bicep) files that generate secrets dynamically
- Scripts that read from environment variables

## ❌ What Should NEVER Be Committed

- `.env.local` - Your actual environment values (already in `.gitignore`)
- `.env` - Any file with real secrets
- Hardcoded API keys, passwords, or connection strings
- Real Azure resource URLs or service names specific to your deployment
- Access tokens or credentials

## 🛡️ Security Checklist Before Publishing

Before making your repository public or sharing it, verify:

- [ ] All `.env*` files (except `.env.example`) are listed in `.gitignore`
- [ ] No hardcoded API keys or secrets in any files
- [ ] No real Azure service URLs (except in dynamically generated outputs)
- [ ] Test scripts use environment variables or command-line parameters
- [ ] Configuration files use placeholders like `your-service-name`
- [ ] README and documentation use example values only

## 🔑 Managing Secrets

### Local Development

1. Copy `.env.example` to `.env.local`:
   ```bash
   copy .env.example .env.local
   ```

2. Fill in your actual values in `.env.local`

3. **Never commit `.env.local`** - it's already in `.gitignore`

### Azure Deployment

Secrets are managed securely:
- **Container App Secrets**: Sensitive values are stored as Container App secrets
- **Managed Identity**: Used for Azure service authentication
- **Key Vault** (optional): For additional secret management
- **Environment Variables**: Non-sensitive configuration

### Testing

When testing, provide secrets via:
1. Environment variables:
   ```powershell
   $env:SERVER_API_KEY = "your-key"
   $env:MCP_SERVER_URL = "https://your-app.azurecontainerapps.io"
   ./test-api.ps1
   ```

2. Command-line parameters:
   ```powershell
   ./test-api.ps1 -ApiKey "your-key" -BaseUrl "https://your-app.azurecontainerapps.io"
   ```

## 🚨 What to Do If Secrets Are Exposed

If you accidentally commit secrets:

1. **Immediately rotate all exposed credentials**:
   - Generate new API keys
   - Update Azure Search keys
   - Change any exposed passwords

2. **Remove from Git history**:
   ```bash
   # This requires force push - be careful!
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch path/to/file" \
     --prune-empty --tag-name-filter cat -- --all
   ```

3. **Update `.gitignore`** if needed to prevent future accidents

4. **Verify no secrets remain**:
   ```bash
   git log --all --full-history -- path/to/file
   ```

## 📝 Best Practices

1. **Use Strong Keys**: Generate secure API keys with sufficient entropy
   ```powershell
   # PowerShell
   [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([System.Guid]::NewGuid().ToString() + [System.Guid]::NewGuid().ToString()))
   ```

2. **Rotate Regularly**: Change API keys and secrets periodically

3. **Principle of Least Privilege**: Grant only necessary permissions

4. **Monitor Access**: Review access logs and audit trails

5. **Secure Transmission**: Always use HTTPS for API calls

6. **Environment Isolation**: Use different secrets for dev/staging/production

## 🔍 Scanning for Secrets

Regularly scan your repository for accidentally committed secrets:

```bash
# Check current files
git grep -i "api.key\|password\|secret" | grep -v ".env.example"

# Check git history
git log -p | grep -i "api.key\|password\|secret"
```

## 📚 Additional Resources

- [GitHub's Guide to Removing Sensitive Data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
- [Azure Key Vault Best Practices](https://docs.microsoft.com/en-us/azure/key-vault/general/best-practices)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
