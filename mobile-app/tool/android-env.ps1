# Process-local C build environment. No dependency is installed on C:.
$ErrorActionPreference = 'Stop'
$mobileRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$androidToolsRoot = if ($env:ANJU_ANDROID_TOOLS_ROOT) { [IO.Path]::GetFullPath($env:ANJU_ANDROID_TOOLS_ROOT) } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../C模块/tools')) }
if ([IO.Path]::GetPathRoot($androidToolsRoot) -eq 'C:\') { throw 'Choose a tools/cache directory outside C:.' }
$env:FLUTTER_ROOT = Join-Path $androidToolsRoot 'flutter'
if (-not (Test-Path -LiteralPath (Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat')) -and (Test-Path -LiteralPath (Join-Path $androidToolsRoot 'flutter-light/bin/flutter.bat'))) { $env:FLUTTER_ROOT = Join-Path $androidToolsRoot 'flutter-light' }
$env:JAVA_HOME = Join-Path $androidToolsRoot 'jdk'
$env:ANDROID_HOME = Join-Path $androidToolsRoot 'sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:APPDATA = Join-Path $androidToolsRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $androidToolsRoot 'localappdata'
$env:PUB_CACHE = Join-Path $androidToolsRoot 'cache/pub'
$env:GRADLE_USER_HOME = Join-Path $androidToolsRoot 'cache/gradle'
$env:ANDROID_USER_HOME = Join-Path $androidToolsRoot 'android-home'
$env:TEMP = Join-Path $androidToolsRoot 'tmp'
$env:TMP = $env:TEMP
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
foreach ($directory in @($env:APPDATA, $env:LOCALAPPDATA, $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:ANDROID_USER_HOME, $env:TEMP, (Join-Path $PSScriptRoot 'logs'))) {
    [void][IO.Directory]::CreateDirectory($directory)
}
$env:PATH = "$env:FLUTTER_ROOT\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\cmdline-tools\latest\bin;$env:ANDROID_HOME\cmdline-tools\19.0\bin;$env:PATH"
$env:ELDER_SAFETY_BUILD_ROOT = $mobileRoot
