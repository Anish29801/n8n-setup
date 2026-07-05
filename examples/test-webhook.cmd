@echo off
REM Save and run this in PowerShell (not cmd)

echo {"subject":"Server Alert","message":"CPU 94%% on prod-web-01"} > %TEMP%\test.json
curl -X POST https://n8n-production-509b.up.railway.app/webhook-test/webhook-email -H "Content-Type: application/json" -d "@%TEMP%\test.json"
pause
