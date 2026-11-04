$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$serverRoot = Split-Path -Parent $projectRoot
$oldPythonPath = $env:PYTHONPATH
$oldPath = $env:PATH
Push-Location $projectRoot
try {
    $testRun = Join-Path (Split-Path -Parent $projectRoot) ('runtime\pytest-' + [guid]::NewGuid().ToString('N'))
    $env:PYTHONPATH = (Join-Path $serverRoot 'safety') + ';' + (Join-Path $projectRoot 'ai-service')
    $env:PATH = (Join-Path $serverRoot 'tools\ffmpeg') + ';' + $oldPath
    & (Join-Path $serverRoot '.venv\Scripts\python.exe') -m pytest -q --tb=short --basetemp $testRun
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
} finally { $env:PYTHONPATH = $oldPythonPath; $env:PATH = $oldPath; Pop-Location }
