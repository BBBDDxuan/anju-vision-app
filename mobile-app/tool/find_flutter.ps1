# Shared by the preparation scripts. Discovery never downloads or installs an SDK.
function Resolve-FlutterCommand {
    param([string]$FlutterPath)
    if ($FlutterPath) {
        if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
            throw "Flutter executable does not exist: $FlutterPath"
        }
        return (Resolve-Path -LiteralPath $FlutterPath).Path
    }
    $command = Get-Command flutter -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) { return $command.Source }
    $projectSdk = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../tools/android-build/flutter'))
    foreach ($sdk in @($env:FLUTTER_ROOT, ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../C模块/tools/flutter'))), ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../C模块/tools/flutter-light'))), $projectSdk, 'D:/flutter', 'G:/tools/flutter', 'D:/tools/flutter', 'G:/flutter')) {
        if (-not $sdk) { continue }
        foreach ($entry in @('bin/flutter.bat', 'bin/flutter')) {
            $candidate = Join-Path $sdk $entry
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    throw 'Flutter SDK not found in PATH, the project G-drive toolchain, or the documented fallback locations. No SDK was downloaded. Supply -FlutterPath pointing to an existing executable.'
}
