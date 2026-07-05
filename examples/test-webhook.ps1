# PowerShell script — right-click → Run with PowerShell
# Sends a test alert to the n8n webhook workflow

curl.exe -X POST "https://n8n-production-509b.up.railway.app/webhook-test/webhook-email" -H "Content-Type: application/json" -d '{"subject":"Server Alert","message":"CPU 94% on prod-web-01"}'
pause
