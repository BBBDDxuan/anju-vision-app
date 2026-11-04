[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$logRoot = Join-Path $PSScriptRoot 'logs'
[void][IO.Directory]::CreateDirectory($logRoot)
$log = Join-Path $logRoot 'android-apk-build.log'
try {
    & (Join-Path $PSScriptRoot 'build-android.ps1') *> $log
    exit 0
} catch {
    ($_ | Out-String) | Add-Content -LiteralPath $log
    exit 1
}
