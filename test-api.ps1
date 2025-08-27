# Test the MCP Server API endpoints
$apiKey = "REDACTED_API_KEY"
$baseUrl = "https://REDACTED_CONTAINER_APP_URL"

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