$ErrorActionPreference = 'Stop'
$previousPath = $env:PATH
$previousPythonPath = $env:PYTHONPATH
Push-Location -LiteralPath $PSScriptRoot
try {
    $env:PYTHONUTF8 = '1'
    $env:PATH = (Join-Path $PSScriptRoot 'tools\ffmpeg') + ';' + $previousPath
    $python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
    & $python -m pytest tests -q
    if ($LASTEXITCODE -ne 0) { throw 'Video API tests failed.' }
    $env:PYTHONPATH = Join-Path $PSScriptRoot 'safety'
    & $python -m pytest safety/tests -q
    if ($LASTEXITCODE -ne 0) { throw 'Safety API tests failed.' }
    $env:PYTHONPATH = (Join-Path $PSScriptRoot 'safety') + ';' + (Join-Path $PSScriptRoot 'detector\ai-service')
    $tempRoot = Join-Path $PSScriptRoot ('runtime\pytest-' + [guid]::NewGuid().ToString('N'))
    & $python -m pytest detector/ai-service/tests -q --basetemp $tempRoot
    if ($LASTEXITCODE -ne 0) { throw 'Detector tests failed.' }
} finally {
    $env:PATH = $previousPath
    $env:PYTHONPATH = $previousPythonPath
    Pop-Location
}
