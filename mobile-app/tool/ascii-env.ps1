# Dot-source this optional Windows workaround before Flutter on Unicode paths.
[CmdletBinding()]
param([string]$ToolsDrive='X:', [string]$RepositoryDrive='Y:')
$ErrorActionPreference='Stop'
if ($ToolsDrive -notmatch '^[D-Zd-z]:$' -or $RepositoryDrive -notmatch '^[D-Zd-z]:$' -or $ToolsDrive -eq $RepositoryDrive) { throw 'Choose two different non-system drive letters.' }
if (-not ('AnjuCDeviceQuery' -as [type])) {
    Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class AnjuCDeviceQuery { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern uint QueryDosDevice(string name, StringBuilder target, int length); }'
}
$repositoryRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\')
$toolsRoot=if($env:ANJU_ANDROID_TOOLS_ROOT){[IO.Path]::GetFullPath($env:ANJU_ANDROID_TOOLS_ROOT).TrimEnd('\')}else{[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../C模块/tools')).TrimEnd('\')}
# Resolve an existing subst alias to its physical target, without moving files.
function Physical([string]$candidate) {
    $drive=[IO.Path]::GetPathRoot($candidate).TrimEnd('\')
    $buffer=New-Object Text.StringBuilder 2048
    if ([AnjuCDeviceQuery]::QueryDosDevice($drive,$buffer,2048) -gt 0 -and $buffer.ToString().StartsWith('\??\')) {
        return [IO.Path]::GetFullPath((Join-Path $buffer.ToString().Substring(4) $candidate.Substring($drive.Length).TrimStart('\'))).TrimEnd('\')
    }
    return $candidate
}
$repositoryRoot=Physical $repositoryRoot
$toolsRoot=Physical $toolsRoot
$bindings=@(@{Drive=$ToolsDrive;Target=$toolsRoot},@{Drive=$RepositoryDrive;Target=$repositoryRoot})
foreach($binding in $bindings) {
    if(-not(Test-Path -LiteralPath $binding.Target)){throw 'Alias target does not exist.'}
    $buffer=New-Object Text.StringBuilder 2048
    $exists=[AnjuCDeviceQuery]::QueryDosDevice($binding.Drive,$buffer,2048) -gt 0
    if($exists) {
        if($buffer.ToString() -ne ('\??\'+$binding.Target)){throw ('Drive is occupied; refusing to replace '+$binding.Drive)}
    } else {
        & subst.exe $binding.Drive $binding.Target
        if($LASTEXITCODE -ne 0){throw 'Could not create temporary ASCII drive alias.'}
    }
}
if(-not(Test-Path -LiteralPath ($RepositoryDrive+'\mobile-app\pubspec.yaml'))){throw 'Repository alias verification failed.'}
$env:ANJU_ANDROID_TOOLS_ROOT=$ToolsDrive+'\'
. (Join-Path $PSScriptRoot 'android-env.ps1')
Set-Location -LiteralPath ($RepositoryDrive+'\mobile-app')
Write-Host ('ASCII environment: '+$RepositoryDrive+'\mobile-app; tools '+$ToolsDrive+'\')
Write-Host 'Mappings are session-local, not permanent. Remove only these aliases with subst DRIVE: /D after all Flutter commands finish.'
