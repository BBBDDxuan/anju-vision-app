[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')][string]$Configuration = 'release',
    [string]$EnvironmentFile = 'D:\AndroidDev\env.ps1',
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $EnvironmentFile) { . $EnvironmentFile }
Push-Location -LiteralPath $ProjectRoot
try {
    & flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    & node tool/source_check.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Source verification failed.' }
    & flutter analyze --no-fatal-infos
    if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
    & flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    if ($Configuration -eq 'release') {
        & flutter build apk --release --split-per-abi --dart-define=USE_FIREBASE=false
    } else {
        & flutter build apk --debug --split-per-abi --target-platform android-arm64,android-x64 --dart-define=USE_FIREBASE=false
    }
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
} finally { Pop-Location }
