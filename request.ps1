$body = @{
    visitor = "Windows11"
} | ConvertTo-Json

Invoke-RestMethod `
    -Method Post `
    -Uri "http://localhost:8080/api/visits" `
    -ContentType "application/json" `
    -Body $body