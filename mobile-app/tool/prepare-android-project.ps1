[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-env.ps1')
$flutter = Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) { throw 'Flutter extraction has not finished.' }
& $flutter --version
if ($LASTEXITCODE -ne 0) { throw 'Flutter version check failed.' }
& $flutter config --android-sdk $env:ANDROID_HOME --jdk-dir $env:JAVA_HOME --no-analytics
if ($LASTEXITCODE -ne 0) { throw 'Flutter Android configuration failed.' }
Push-Location -LiteralPath $env:ELDER_SAFETY_BUILD_ROOT
try {
    & (Join-Path $PSScriptRoot 'scaffold_platforms.ps1') -FlutterPath $flutter -Platforms android
} finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw 'Android scaffolding failed.' }
$mobileRoot = $env:ELDER_SAFETY_BUILD_ROOT
$gradleProperties = Join-Path $mobileRoot 'android/gradle.properties'
$properties = [IO.File]::ReadAllText($gradleProperties)
$properties = [regex]::Replace($properties, '(?m)^org[.]gradle[.]jvmargs=.*$', 'org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:+HeapDumpOnOutOfMemoryError')
if (-not $properties.Contains('org.gradle.workers.max')) { $properties += "`norg.gradle.workers.max=2`n" }
[IO.File]::WriteAllText($gradleProperties, $properties)
if (-not $properties.Contains('android.overridePathCheck')) {
    [IO.File]::AppendAllText($gradleProperties, "`n# The user workspace contains Chinese directory names.`nandroid.overridePathCheck=true`n")
}
& (Join-Path $PSScriptRoot 'verify.ps1') -FlutterPath $flutter
if ($LASTEXITCODE -ne 0) { throw 'Flutter verification failed.' }
