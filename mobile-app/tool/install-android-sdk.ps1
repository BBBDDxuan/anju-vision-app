[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-env.ps1')
$sdkManager = Join-Path $env:ANDROID_HOME 'cmdline-tools/19.0/bin/sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkManager)) { throw 'Android command-line tools are not installed yet.' }
$proxyArgs = @()
$buildProxyValue = $env:HTTPS_PROXY
if (-not $buildProxyValue) { $buildProxyValue = $env:HTTP_PROXY }
if ($buildProxyValue) {
    $buildProxyUri = [uri]$buildProxyValue
    if ($buildProxyUri.UserInfo) { throw 'Authenticated build proxy needs manual local configuration.' }
    $proxyArgs = @('--proxy=http', "--proxy_host=$($buildProxyUri.Host)", "--proxy_port=$($buildProxyUri.Port)")
}
if (-not $buildProxyValue -and (Test-Path -LiteralPath (Join-Path $androidToolsRoot 'build-proxy.json'))) {
    $localProxy = Get-Content -LiteralPath (Join-Path $androidToolsRoot 'build-proxy.json') -Raw | ConvertFrom-Json
    $proxyArgs = @('--proxy=http', "--proxy_host=$($localProxy.host)", "--proxy_port=$($localProxy.port)")
}
$licenseLog = Join-Path $androidToolsRoot 'logs/android-licenses.log'
$sdkLog = Join-Path $androidToolsRoot 'logs/android-sdk-install.log'
1..100 | ForEach-Object { 'y' } | & $sdkManager "--sdk_root=$env:ANDROID_HOME" @proxyArgs --licenses *> $licenseLog
if ($LASTEXITCODE -ne 0) { throw "Android SDK license setup failed; see $licenseLog" }
& $sdkManager "--sdk_root=$env:ANDROID_HOME" @proxyArgs 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' *> $sdkLog
if ($LASTEXITCODE -ne 0) { throw "Android SDK component installation failed; see $sdkLog" }
Write-Host "Android SDK components installed. Log: $sdkLog"
