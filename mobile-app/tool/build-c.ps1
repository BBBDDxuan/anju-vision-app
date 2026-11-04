[CmdletBinding()]
param([switch]$WithFirebase, [switch]$Release, [switch]$SkipChecks, [string]$FlutterPath, [string]$ExpectedSigningSha256)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_flutter.ps1')
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$reports = Join-Path $PSScriptRoot 'logs'
[void][IO.Directory]::CreateDirectory($reports)
$statusFile = Join-Path $reports 'c-build-status.json'
function Status([string]$state, [string]$stage, [string]$apk = '') {
    @{state=$state; stage=$stage; updated_at=[DateTimeOffset]::Now.ToString('o'); apk=$apk; firebase_enabled=[bool]$WithFirebase; real_phone_tested=$false} | ConvertTo-Json | Set-Content -LiteralPath $statusFile -Encoding utf8
}
$oldFirebase = $env:ORG_GRADLE_PROJECT_enableFirebase
$configuration = if ($Release) { 'release' } else { 'debug' }
Push-Location -LiteralPath $project
try {
    Status 'running' 'preflight'
    $flutter = Resolve-FlutterCommand -FlutterPath $FlutterPath
    if ($Release -and -not (Test-Path -LiteralPath 'android/key.properties')) { throw 'Original release signing configuration is unavailable. Never substitute a different key for an upgrade.' }
    if ($Release -and $ExpectedSigningSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Release requires -ExpectedSigningSha256 from the original APK certificate.' }
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (-not $sdk -or -not (Test-Path -LiteralPath (Join-Path $sdk 'build-tools'))) { throw 'Android SDK build-tools is unavailable.' }
    $signer = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Filter apksigner.bat -Recurse -File | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $signer) { throw 'apksigner is required to verify produced APK signatures.' }
    if ($WithFirebase) {
        $file = Join-Path $project 'android/app/google-services.json'
        if (-not (Test-Path -LiteralPath $file)) { throw 'Firebase client config missing. Background push is not enabled.' }
        $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        $application = 'com.eldersafety.elder_safety_mobile'
        if (-not $Release) { $application += '.test' }
        $packages = @($config.client | ForEach-Object { $_.client_info.android_client_info.package_name })
        if ($application -notin $packages) { throw 'Firebase package does not match this build, including the debug .test suffix.' }
        $env:ORG_GRADLE_PROJECT_enableFirebase = 'true'
    } else { $env:ORG_GRADLE_PROJECT_enableFirebase = 'false' }
    & $flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Locked dependency restore failed.' }
    if (-not $SkipChecks) {
        Status 'running' 'verification'
        & node tool/source_check.mjs
        if ($LASTEXITCODE -ne 0) { throw 'Source consistency failed.' }
        & node tool/check-c-config.mjs
        if ($LASTEXITCODE -ne 0) { throw 'C notification configuration failed.' }
        & node tool/check-c-scope.mjs
        if ($LASTEXITCODE -ne 0) { throw 'ABC file boundary violation.' }
        & $flutter analyze --no-fatal-infos
        if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
        & $flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    }
    Status 'running' 'apk_build'
    $firebase = ([bool]$WithFirebase).ToString().ToLowerInvariant()
    & $flutter build apk "--$configuration" --no-pub --split-per-abi "--dart-define=USE_FIREBASE=$firebase"
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
    $outputs = @(Get-ChildItem -LiteralPath 'build/app/outputs/flutter-apk' -Filter "*-$configuration.apk" -File)
    if ($outputs.Count -eq 0) { throw 'No new APK was produced.' }
    $destination = Join-Path $project '../docs/c-notifications/builds'
    [void][IO.Directory]::CreateDirectory($destination)
    $versionLine = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:').Line
    $version = ($versionLine -replace '^version:\s*','').Trim()
    $artifacts = @()
    foreach ($output in $outputs) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($output.FullName)
        try { if (-not $zip.GetEntry('AndroidManifest.xml') -or -not $zip.GetEntry('classes.dex')) { throw 'Invalid Android package.' } } finally { $zip.Dispose() }
        $signature = & $signer.FullName verify --verbose --print-certs $output.FullName 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'APK cryptographic signature verification failed.' }
        $certificateMatch = [regex]::Match(($signature -join [Environment]::NewLine), 'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})')
        if (-not $certificateMatch.Success) { throw 'APK signing certificate fingerprint was not returned.' }
        $certificate = $certificateMatch.Groups[1].Value.ToLowerInvariant()
        if ($Release -and $certificate -ne $ExpectedSigningSha256.ToLowerInvariant()) { throw 'Signing certificate differs from original APK; upgrade rejected.' }
        $target = Join-Path $destination ("AnjuVision-$version-c-$firebase-" + $output.Name)
        Copy-Item -LiteralPath $output.FullName -Destination $target
        $artifacts += @{file=[IO.Path]::GetFileName($target); sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant(); bytes=(Get-Item -LiteralPath $target).Length; certificate_sha256=$certificate; original_signer_verified=[bool]$Release}
    }
    $sourceCommit = (& git -C $project rev-parse HEAD | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record source Git revision.' }
    $dirty = [bool](& git -C $project status --porcelain)
    @{source_commit=$sourceCommit; contains_uncommitted_changes=$dirty; version=$version; configuration=$configuration; firebase_enabled=[bool]$WithFirebase; real_phone_tested=$false; artifacts=$artifacts} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'BUILD-METADATA.json') -Encoding utf8
    Status 'succeeded' 'apk_produced_not_phone_verified' $destination
    Write-Host "APKs: $destination"
} catch {
    Status 'failed' 'see-build-log'
    throw
} finally {
    $env:ORG_GRADLE_PROJECT_enableFirebase = $oldFirebase
    Pop-Location
}
