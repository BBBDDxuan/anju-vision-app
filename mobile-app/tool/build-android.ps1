[CmdletBinding()]
param([switch]$WithFirebase, [switch]$SkipChecks, [switch]$VerboseBuild)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-env.ps1')
& (Join-Path $PSScriptRoot 'build-c.ps1') -WithFirebase:$WithFirebase -SkipChecks:$SkipChecks -FlutterPath (Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat')
