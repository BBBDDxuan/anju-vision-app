[CmdletBinding()]
param(
    [string]$ToolsRoot = '',
    [string]$LanTlsProfile = '',
    [ValidateSet('release', 'debug')][string]$Configuration = 'release',
    [ValidateSet('android-arm', 'android-arm64', 'android-x64')]
    [string[]]$TargetPlatform = @('android-arm64'),
    [switch]$WithFirebase,
    [string]$ExpectedSigningSha256 = '2472d43f63dbea0d2d3c34933114caf3dc532055c97ceaa40e96a968070b3e35'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mobileRoot = Join-Path $PSScriptRoot 'mobile-app'
if (-not $LanTlsProfile) {
    $userLocalData = [Environment]::GetFolderPath('LocalApplicationData')
    if ($userLocalData) { $LanTlsProfile = Join-Path $userLocalData 'AnjuVision\lan-tls' }
}
if (-not $ToolsRoot) {
    $ToolsRoot = if ($env:ANJU_ANDROID_TOOLS_ROOT) { $env:ANJU_ANDROID_TOOLS_ROOT } else { 'D:\AndroidDev' }
}
$ToolsRoot = [IO.Path]::GetFullPath($ToolsRoot)
# The bundled AOT snapshotter cannot read Unicode paths on this Windows setup.
# Use temporary ASCII aliases for the same physical checkout, never a source copy.
if ($PSScriptRoot -match '[^\x00-\x7f]' -or $ToolsRoot -match '[^\x00-\x7f]') {
    $occupied = @([IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.TrimEnd('\') })
    $available = @('Z:', 'Y:', 'X:', 'W:', 'V:', 'U:', 'T:', 'S:', 'R:', 'Q:' | Where-Object { $_ -notin $occupied })
    if ($available.Count -lt 2) { throw 'Two unused drive letters are required for the Unicode-path workaround.' }
    $toolsDrive = $available[0]
    $repositoryDrive = $available[1]
    $callerLocation = Get-Location
    $previousToolsRoot = $env:ANJU_ANDROID_TOOLS_ROOT
    $env:ANJU_ANDROID_TOOLS_ROOT = $ToolsRoot
    try {
        . (Join-Path $mobileRoot 'tool\ascii-env.ps1') -ToolsDrive $toolsDrive -RepositoryDrive $repositoryDrive
        & ($repositoryDrive + '\build.ps1') -ToolsRoot ($toolsDrive + '\') -LanTlsProfile $LanTlsProfile -Configuration $Configuration -TargetPlatform $TargetPlatform -WithFirebase:$WithFirebase -ExpectedSigningSha256 $ExpectedSigningSha256
    } finally {
        Set-Location -LiteralPath $callerLocation.Path
        # Only aliases created above, after proving both letters were unoccupied.
        & subst.exe $repositoryDrive /D
        & subst.exe $toolsDrive /D
        $env:ANJU_ANDROID_TOOLS_ROOT = $previousToolsRoot
    }
    return
}
$env:FLUTTER_ROOT = Join-Path $ToolsRoot 'flutter'
$env:JAVA_HOME = Join-Path $ToolsRoot 'jdk'
$env:ANDROID_HOME = Join-Path $ToolsRoot 'sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:PUB_CACHE = Join-Path $ToolsRoot 'cache\pub'
$env:GRADLE_USER_HOME = Join-Path $ToolsRoot 'cache\gradle'
$env:ANDROID_USER_HOME = Join-Path $ToolsRoot 'android-home'
$env:TEMP = Join-Path $ToolsRoot 'tmp'
$env:TMP = $env:TEMP
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
$env:ELDER_SAFETY_BUILD_ROOT = $mobileRoot
$env:PATH = "$env:FLUTTER_ROOT\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
$flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
foreach ($required in @($flutter, (Join-Path $env:JAVA_HOME 'bin\java.exe'), $env:ANDROID_HOME)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required tool not found: $required" }
}
foreach ($directory in @($env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:ANDROID_USER_HOME, $env:TEMP)) {
    [void][IO.Directory]::CreateDirectory($directory)
}
if ($Configuration -eq 'release' -and -not (Test-Path -LiteralPath (Join-Path $mobileRoot 'android\key.properties'))) {
    throw 'Original private signing configuration is required at mobile-app/android/key.properties.'
}
if ($Configuration -eq 'release' -and $ExpectedSigningSha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw 'Expected original signing certificate SHA-256 is invalid.'
}
$signer = Get-ChildItem -LiteralPath (Join-Path $env:ANDROID_HOME 'build-tools') -Filter apksigner.bat -Recurse -File |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signer) { throw 'Android apksigner was not found.' }
$priorFirebase = $env:ORG_GRADLE_PROJECT_enableFirebase
$priorTlsResources = $env:ANJU_ANDROID_TLS_RES
Push-Location -LiteralPath $mobileRoot
try {
    if ($WithFirebase) {
        $configPath = Join-Path $mobileRoot 'android\app\google-services.json'
        if (-not (Test-Path -LiteralPath $configPath)) { throw 'Firebase client configuration is missing.' }
        $clientConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $expectedPackage = 'com.eldersafety.elder_safety_mobile'
        if ($Configuration -eq 'debug') { $expectedPackage += '.test' }
        $configuredPackages = @($clientConfig.client | ForEach-Object { $_.client_info.android_client_info.package_name })
        if ($expectedPackage -notin $configuredPackages) { throw 'Firebase package does not match this build.' }
    }
    $env:ORG_GRADLE_PROJECT_enableFirebase = ([bool]$WithFirebase).ToString().ToLowerInvariant()
    & $flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Locked dependency restore failed.' }
    & (Join-Path $mobileRoot 'tool\verify.ps1') -FlutterPath $flutter
    & node (Join-Path $mobileRoot 'tool\check-c-config.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Notification configuration check failed.' }
    $firebase = ([bool]$WithFirebase).ToString().ToLowerInvariant()
    $platforms = $TargetPlatform -join ','
    $tlsArgs = @()
    $env:ANJU_ANDROID_TLS_RES = $null
    if ($LanTlsProfile -and (Test-Path -LiteralPath (Join-Path $LanTlsProfile 'address.txt'))) {
        $ca = [IO.File]::ReadAllBytes((Join-Path $LanTlsProfile 'ca.pem'))
        $pem = [Text.Encoding]::ASCII.GetString($ca).Trim()
        if ($ca.Length -gt 16384 -or $pem -notmatch '\A-----BEGIN CERTIFICATE-----\s+[A-Za-z0-9+/=\s]+-----END CERTIFICATE-----\z') {
            throw 'LAN profile must contain one public CA certificate, never a private key.'
        }
        $addresses = @((Get-Content -LiteralPath (Join-Path $LanTlsProfile 'address.txt')) |
            ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
        if ($addresses.Count -lt 1 -or $addresses.Count -gt 12) { throw 'Invalid LAN trust address count.' }
        foreach ($ip in $addresses) {
            if ($ip -notmatch '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)\d{1,3}\.\d{1,3}(?:\.\d{1,3})?$' -or
                ($ip.Split('.').Count -ne 4) -or [Net.IPAddress]::Parse($ip).ToString() -ne $ip) {
                throw 'LAN certificate trust is limited to canonical private IPv4 addresses.'
            }
        }
        $res = Join-Path $mobileRoot 'build\local-lan-tls-res'
        [void][IO.Directory]::CreateDirectory((Join-Path $res 'raw'))
        [void][IO.Directory]::CreateDirectory((Join-Path $res 'xml'))
        [IO.File]::WriteAllBytes((Join-Path $res 'raw\anju_lan_ca.pem'), $ca)
        $domains = @($addresses | ForEach-Object { '<domain includeSubdomains="false">' + $_ + '</domain>' }) -join ''
        $xml = '<network-security-config><base-config cleartextTrafficPermitted="true"><trust-anchors><certificates src="system"/></trust-anchors></base-config><domain-config cleartextTrafficPermitted="false">' + $domains + '<trust-anchors><certificates src="@raw/anju_lan_ca"/></trust-anchors></domain-config></network-security-config>'
        [IO.File]::WriteAllText((Join-Path $res 'xml\anju_network_security.xml'), $xml)
        $env:ANJU_ANDROID_TLS_RES = $res
        $origins = @($addresses | ForEach-Object { "https://$($_):8000" }) -join ','
        $tlsArgs = @("--dart-define=ANJU_LAN_ORIGINS=$origins", "--dart-define=ANJU_LAN_CA_BASE64=$([Convert]::ToBase64String($ca))")
    }
    & $flutter build apk "--$Configuration" --no-pub --split-per-abi "--target-platform=$platforms" "--dart-define=USE_FIREBASE=$firebase" @tlsArgs
    if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
    $abis = @{ 'android-arm' = 'armeabi-v7a'; 'android-arm64' = 'arm64-v8a'; 'android-x64' = 'x86_64' }
    $artifacts = @()
    foreach ($platform in $TargetPlatform) {
        $name = "app-$($abis[$platform])-$Configuration.apk"
        $apk = Join-Path $mobileRoot "build\app\outputs\flutter-apk\$name"
        if (-not (Test-Path -LiteralPath $apk)) { throw "Missing expected build output: $name" }
        $signature = & $signer.FullName verify --verbose --print-certs $apk 2>&1
        if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $name" }
        $certificateMatch = [regex]::Match(($signature -join [Environment]::NewLine), 'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})')
        if (-not $certificateMatch.Success) { throw 'Signing certificate fingerprint is missing.' }
        $certificate = $certificateMatch.Groups[1].Value.ToLowerInvariant()
        if ($Configuration -eq 'release' -and $certificate -ne $ExpectedSigningSha256.ToLowerInvariant()) {
            throw 'Signing certificate differs from the original app; upgrade must not be delivered.'
        }
        $artifacts += @{
            file = $name; abi = $abis[$platform]; bytes = (Get-Item -LiteralPath $apk).Length
            sha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
            certificate_sha256 = $certificate; original_signer_verified = ($Configuration -eq 'release')
        }
        Write-Host "Verified APK: $apk"
    }
    $sourceCommit = (& git -C $PSScriptRoot rev-parse HEAD | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record source revision.' }
    $version = ((Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:').Line -replace '^version:\s*', '').Trim()
    $report = @{
        source_commit = $sourceCommit; source_branch = (& git -C $PSScriptRoot branch --show-current | Select-Object -Last 1)
        contains_uncommitted_changes = [bool](& git -C $PSScriptRoot status --porcelain)
        version = $version; configuration = $Configuration; firebase_enabled = [bool]$WithFirebase
        real_phone_tested = $false; artifacts = $artifacts
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $mobileRoot 'build\BUILD-RESULTS.json') -Encoding utf8
} finally {
    Pop-Location
    $env:ORG_GRADLE_PROJECT_enableFirebase = $priorFirebase
    $env:ANJU_ANDROID_TLS_RES = $priorTlsResources
}
