[CmdletBinding()]
param([string]$ToolsRoot = (Join-Path $PSScriptRoot '../../../C模块/tools'))
$ErrorActionPreference = 'Stop'
$ToolsRoot = [IO.Path]::GetFullPath($ToolsRoot)
[void][IO.Directory]::CreateDirectory($ToolsRoot)
$archive = Join-Path $ToolsRoot 'flutter_windows_3.47.8-stable.zip'
$url = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.8-stable.zip'
$expected = '11e19ea3409808fe3b3765ea8149640c299e58cce6eda7c9f38fc1b4a193eb6e'
if (-not (Test-Path -LiteralPath (Join-Path $ToolsRoot 'flutter/bin/flutter.bat'))) {
    & curl.exe --fail --location --retry 3 --retry-delay 2 --continue-at - --output $archive $url
    if ($LASTEXITCODE -ne 0) { throw 'Flutter download failed; partial archive retained for a normal resume.' }
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Flutter archive SHA-256 mismatch. Do not extract.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $ToolsRoot)
}
Write-Host (Join-Path $ToolsRoot 'flutter/bin/flutter.bat')
