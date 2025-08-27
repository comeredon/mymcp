# Environment Validation Script
# Checks your .env.local file for completeness and validity

param(
    [string]$EnvFile = ".env.local"
)

function Test-EnvFile {
    param([string]$FilePath)
    
    Write-Host "🔍 Validating Environment Configuration" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "❌ Environment file '$FilePath' not found!" -ForegroundColor Red
        Write-Host "💡 Run: copy .env.example .env.local" -ForegroundColor Yellow
        return $false
    }
    
    Write-Host "✅ Environment file found: $FilePath" -ForegroundColor Green
    
    $envVars = @{}
    $lineCount = 0
    
    Get-Content $FilePath | ForEach-Object {
        $lineCount++
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            
            # Remove quotes
            if ($value.StartsWith('"') -and $value.EndsWith('"')) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            if ($value.StartsWith("'") -and $value.EndsWith("'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            
            $envVars[$key] = $value
        }
    }
    
    Write-Host "📄 Found $($envVars.Count) environment variables" -ForegroundColor Green
    
    # Check required variables
    $required = @{
        "SEARCH_ENDPOINT" = @{
            "description" = "Azure AI Search service endpoint"
            "example" = "https://mysearch.search.windows.net/"
            "validation" = { param($v) $v -match "^https://.*\.search\.windows\.net/?$" }
        }
        "SEARCH_KEY" = @{
            "description" = "Azure AI Search admin key"
            "example" = "1234567890ABCDEF..."
            "validation" = { param($v) $v.Length -ge 20 }
        }
        "SEARCH_INDEX" = @{
            "description" = "Name of your PDF search index"
            "example" = "pdf-documents"
            "validation" = { param($v) $v -match "^[a-zA-Z0-9\-_]+$" }
        }
        "SERVER_API_KEY" = @{
            "description" = "API key for client authentication"
            "example" = "my-secure-api-key-123"
            "validation" = { param($v) $v.Length -ge 8 }
        }
    }
    
    $optional = @{
        "PORT" = @{
            "description" = "Server port"
            "default" = "8080"
            "validation" = { param($v) $v -match "^\d+$" -and [int]$v -gt 0 -and [int]$v -lt 65536 }
        }
        "AZURE_RESOURCE_GROUP" = @{
            "description" = "Target Azure resource group"
            "default" = "mcpserver"
            "validation" = { param($v) $v -match "^[a-zA-Z0-9\-_\.]+$" }
        }
        "AZURE_LOCATION" = @{
            "description" = "Azure region"
            "default" = "swedencentral"
            "validation" = { param($v) $v -match "^[a-z0-9]+$" }
        }
    }
    
    $isValid = $true
    
    Write-Host "`n🔧 Required Variables:" -ForegroundColor Yellow
    foreach ($var in $required.Keys) {
        $config = $required[$var]
        if ($envVars.ContainsKey($var) -and -not [string]::IsNullOrWhiteSpace($envVars[$var])) {
            $value = $envVars[$var]
            $isValidValue = & $config.validation $value
            
            if ($isValidValue) {
                $displayValue = if ($var.Contains("KEY")) { "***hidden***" } else { $value }
                Write-Host "  ✅ $var = $displayValue" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  $var = invalid format" -ForegroundColor Red
                Write-Host "     Expected: $($config.example)" -ForegroundColor Gray
                $isValid = $false
            }
        } else {
            Write-Host "  ❌ $var = missing" -ForegroundColor Red
            Write-Host "     Description: $($config.description)" -ForegroundColor Gray
            Write-Host "     Example: $($config.example)" -ForegroundColor Gray
            $isValid = $false
        }
    }
    
    Write-Host "`n⚙️ Optional Variables:" -ForegroundColor Yellow
    foreach ($var in $optional.Keys) {
        $config = $optional[$var]
        if ($envVars.ContainsKey($var) -and -not [string]::IsNullOrWhiteSpace($envVars[$var])) {
            $value = $envVars[$var]
            $isValidValue = & $config.validation $value
            
            if ($isValidValue) {
                Write-Host "  ✅ $var = $value" -ForegroundColor Green
            } else {
                Write-Host "  ⚠️  $var = invalid format" -ForegroundColor Yellow
                $isValid = $false
            }
        } else {
            Write-Host "  ➖ $var = not set (will use default: $($config.default))" -ForegroundColor Gray
        }
    }
    
    # Security checks
    Write-Host "`n🔒 Security Checks:" -ForegroundColor Yellow
    
    if ($envVars.ContainsKey("SERVER_API_KEY")) {
        $apiKey = $envVars["SERVER_API_KEY"]
        if ($apiKey.Length -lt 16) {
            Write-Host "  ⚠️  SERVER_API_KEY is short (recommend 16+ characters)" -ForegroundColor Yellow
        } elseif ($apiKey -match "^[a-zA-Z0-9]+$" -and $apiKey.Length -ge 16) {
            Write-Host "  ✅ SERVER_API_KEY looks secure" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  SERVER_API_KEY should contain alphanumeric characters" -ForegroundColor Yellow
        }
    }
    
    # Check for example values
    $exampleValues = @("your-search-service", "your-actual-search", "your-custom-api-key")
    foreach ($key in $envVars.Keys) {
        $value = $envVars[$key]
        foreach ($example in $exampleValues) {
            if ($value -like "*$example*") {
                Write-Host "  ⚠️  $key contains example text - please update with real values" -ForegroundColor Yellow
                $isValid = $false
            }
        }
    }
    
    Write-Host "`n" -NoNewline
    if ($isValid) {
        Write-Host "🎉 Environment configuration is valid!" -ForegroundColor Green
        Write-Host "✅ Ready for deployment with: ./deploy-with-env.ps1" -ForegroundColor Green
    } else {
        Write-Host "❌ Environment configuration has issues" -ForegroundColor Red
        Write-Host "💡 Please fix the issues above before deploying" -ForegroundColor Yellow
    }
    
    return $isValid
}

# Run validation
$result = Test-EnvFile -FilePath $EnvFile

if ($result) {
    Write-Host "`n🚀 Next Steps:" -ForegroundColor Cyan
    Write-Host "  • Test locally: npm run dev-local" -ForegroundColor White
    Write-Host "  • Deploy to Azure: ./deploy-with-env.ps1" -ForegroundColor White
    Write-Host "  • Dry run first: ./deploy-with-env.ps1 -DryRun" -ForegroundColor White
} else {
    Write-Host "`n🔧 Fix Issues:" -ForegroundColor Cyan
    Write-Host "  • Edit: .env.local" -ForegroundColor White
    Write-Host "  • Validate: ./validate-env.ps1" -ForegroundColor White
    Write-Host "  • Reference: ENV-SETUP.md" -ForegroundColor White
}