# Local Development Script
# Loads environment variables from .env.local and runs the server

param(
    [string]$EnvFile = ".env.local"
)

function Load-EnvFile {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-Host "Environment file '$FilePath' not found!" -ForegroundColor Red
        Write-Host "Please copy .env.example to .env.local and fill in your values" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "Loading environment variables from: $FilePath" -ForegroundColor Green
    
    Get-Content $FilePath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            
            # Remove quotes if present
            if ($value.StartsWith('"') -and $value.EndsWith('"')) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            if ($value.StartsWith("'") -and $value.EndsWith("'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
            Write-Host "  $key = $value" -ForegroundColor Cyan
        }
    }
}

Write-Host "🚀 Starting MCP Azure PDF Server (Local Development)" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green

# Load environment variables
Load-EnvFile -FilePath $EnvFile

# Build and start the server
Write-Host "`nBuilding TypeScript..." -ForegroundColor Yellow
npm run build

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nStarting server..." -ForegroundColor Yellow
    npm start
} else {
    Write-Host "Build failed!" -ForegroundColor Red
    exit 1
}