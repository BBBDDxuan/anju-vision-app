param([int]$Port = 8010, [string]$BindAddress = '127.0.0.1')
$ErrorActionPreference = 'Stop'
$serverRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$python = Join-Path $serverRoot '.venv\Scripts\python.exe'
$oldPythonPath = $env:PYTHONPATH
Push-Location -LiteralPath $serverRoot
try {
    if (-not (Test-Path -LiteralPath 'safety/.env')) {
        & $python scripts/configure_phone.py
        if ($LASTEXITCODE -ne 0) { throw 'Private configuration failed.' }
    }
    $env:PYTHONPATH = Join-Path $serverRoot 'safety'
    & $python -m uvicorn safety_backend.main:create_app --factory --host $BindAddress --port $Port --no-proxy-headers --no-access-log
    if ($LASTEXITCODE -ne 0) { throw 'Safety backend stopped with an error.' }
} finally { $env:PYTHONPATH = $oldPythonPath; Pop-Location }
