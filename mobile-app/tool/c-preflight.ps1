[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'find_flutter.ps1')
$flutter = $null
try { $flutter = Resolve-FlutterCommand } catch {}
$result = [ordered]@{
    checked_at = [DateTimeOffset]::Now.ToString('o')
    flutter_found = [bool]$flutter
    flutter_path = $flutter
    android_sdk_configured = [bool]($env:ANDROID_HOME -and (Test-Path -LiteralPath $env:ANDROID_HOME))
    java_found = [bool](Get-Command java -ErrorAction SilentlyContinue)
    firebase_client_config_present = Test-Path -LiteralPath (Join-Path $root 'android/app/google-services.json')
    release_signing_config_present = Test-Path -LiteralPath (Join-Path $root 'android/key.properties')
    server_fcm_enabled = ($env:APP_FCM_ENABLED -eq 'true')
    server_credential_path_configured = [bool]$env:APP_FCM_CREDENTIALS
    backend_lock_screen_delivery_verified = $false
    real_phone_tested = $false
}
$result | ConvertTo-Json
