# Test the MCP Server API endpoints
# Usage: Set environment variables before running:
#   $env:SERVER_API_KEY = "your-api-key"
#   $env:MCP_SERVER_URL = "https://your-app.azurecontainerapps.io"
# Or provide them as parameters:
#   ./test-api.ps1 -ApiKey "your-api-key" -BaseUrl "https://your-app.azurecontainerapps.io"

param(
    [string]$ApiKey = $env:SERVER_API_KEY,
    [string]$BaseUrl = $env:MCP_SERVER_URL
)

# Check if required parameters are provided
if ([string]::IsNullOrEmpty($ApiKey)) {
    Write-Host "Error: SERVER_API_KEY is required. Set it as an environment variable or pass it as -ApiKey parameter." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrEmpty($BaseUrl)) {
    Write-Host "Error: MCP_SERVER_URL is required. Set it as an environment variable or pass it as -BaseUrl parameter." -ForegroundColor Red
    exit 1
}

# Remove /api/tools suffix if present (we'll add endpoints as needed)
$baseUrl = $BaseUrl -replace "/api/tools$", ""
$apiKey = $ApiKey

Write-Host "Testing health endpoint..." -ForegroundColor Green
$health = Invoke-RestMethod -Uri "$baseUrl/health" -Method Get
Write-Host "Health response: $($health | ConvertTo-Json)" -ForegroundColor Yellow

Write-Host "`nTesting search endpoint..." -ForegroundColor Green
$searchBody = @{
    query = "test search"
} | ConvertTo-Json

$searchResponse = Invoke-RestMethod -Uri "$baseUrl/api/search" -Method Post -ContentType "application/json" -Headers @{"x-api-key" = $apiKey} -Body $searchBody
Write-Host "Search response: $($searchResponse | ConvertTo-Json)" -ForegroundColor Yellow

Write-Host "`nTesting tools endpoint..." -ForegroundColor Green
$toolsBody = @{
    tool = "search"
    arguments = @{
        query = "test"
    }
} | ConvertTo-Json

try {
    $toolsResponse = Invoke-RestMethod -Uri "$baseUrl/api/tools" -Method Post -ContentType "application/json" -Headers @{"x-api-key" = $apiKey} -Body $toolsBody
    Write-Host "Tools response: $($toolsResponse | ConvertTo-Json)" -ForegroundColor Yellow
} catch {
    Write-Host "Tools endpoint error: $($_.Exception.Message)" -ForegroundColor Red
}