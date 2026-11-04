[CmdletBinding()]
param([string]$FlutterPath, [switch]$SourceOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_flutter.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($env:ELDER_SAFETY_BUILD_ROOT) { $projectRoot = $env:ELDER_SAFETY_BUILD_ROOT }
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $parseErrors = $null
    $tokens = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "PowerShell parse failed: $($file.Name): $parseErrors" }
}
Write-Host 'PowerShell source parsing passed.'
& node (Join-Path $PSScriptRoot 'source_check.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Source consistency check failed.' }
if ($SourceOnly) {
    Write-Host 'Source-only checks complete. Flutter pub get/analyze/test were NOT executed.'
    return
}
try { $flutter = Resolve-FlutterCommand -FlutterPath $FlutterPath }
catch { Write-Warning $_.Exception.Message; exit 2 }
Push-Location -LiteralPath $projectRoot
try {
    & $flutter --version
    if ($LASTEXITCODE -ne 0) { throw 'Flutter version check failed.' }
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    if ($projectRoot -match '[^\x00-\x7f]') {
        # Flutter 3.47.8's analyzer LSP writer counts characters instead of UTF-8
        # bytes. The SDK Dart analyzer works with the same package configuration.
        Write-Host 'Using SDK Dart analyzer for the Unicode workspace path.'
        $dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
        if (-not (Test-Path -LiteralPath $dart)) { throw 'SDK Dart analyzer was not found.' }
        & $dart analyze lib test
        if ($LASTEXITCODE -ne 0) { throw 'SDK Dart analysis failed.' }
    } else {
        # Keep informational diagnostics visible. The existing backend uses FCM
        # registration tokens; migrating deprecated APIs to FIDs is separate work.
        & $flutter analyze --no-fatal-infos
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
    }
    & $flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
} finally { Pop-Location }
