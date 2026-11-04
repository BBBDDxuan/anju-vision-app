[CmdletBinding()]
param(
    [string]$FlutterPath,
    [ValidateSet('android', 'ios', 'web')]
    [string[]]$Platforms = @('android', 'ios', 'web'),
    [string]$Organization = 'com.eldersafety'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'find_flutter.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$missing = @($Platforms | Select-Object -Unique | Where-Object {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $_)) {
        Write-Host "Preserving existing platform directory: $_"
        $false
    } else { $true }
})
if ($missing.Count -eq 0) {
    Write-Host 'All requested platform directories exist. Nothing was changed.'
    return
}
$flutter = Resolve-FlutterCommand -FlutterPath $FlutterPath
$stageParent = Join-Path $projectRoot '.platform_scaffold'
if ((Test-Path -LiteralPath $stageParent) -and
    ((Get-Item -LiteralPath $stageParent).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'Refusing a staging directory that is a symbolic link or junction.'
}
$stageRoot = Join-Path $stageParent ([Guid]::NewGuid().ToString('N'))
$stageProject = Join-Path $stageRoot 'elder_safety_mobile'
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
& $flutter create --project-name elder_safety_mobile --org $Organization --platforms ($missing -join ',') --no-pub $stageProject
if ($LASTEXITCODE -ne 0) { throw "flutter create failed ($LASTEXITCODE). Existing sources were not changed. Staging retained at $stageRoot" }

function Set-AndroidAttribute($document, $node, [string]$name, [string]$value) {
    $attribute = $document.CreateAttribute('android', $name, 'http://schemas.android.com/apk/res/android')
    $attribute.Value = $value
    [void]$node.Attributes.SetNamedItem($attribute)
}
function Set-PlistValue($document, [string]$key, $valueNode) {
    $dict = $document.SelectSingleNode('/plist/dict')
    $existing = $dict.SelectSingleNode("key[.='$key']")
    if ($existing) { [void]$dict.ReplaceChild($valueNode, $existing.NextSibling) }
    else {
        $keyNode = $document.CreateElement('key')
        $keyNode.InnerText = $key
        [void]$dict.AppendChild($keyNode)
        [void]$dict.AppendChild($valueNode)
    }
}
if ($missing -contains 'android') {
    $mainFile = Join-Path $stageProject 'android/app/src/main/AndroidManifest.xml'
    [xml]$manifest = Get-Content -LiteralPath $mainFile -Raw
    $application = $manifest.SelectSingleNode('/manifest/application')
    Set-AndroidAttribute $manifest $application 'label' '安心相伴'
    $permission = $manifest.CreateElement('uses-permission')
    Set-AndroidAttribute $manifest $permission 'name' 'android.permission.INTERNET'
    [void]$manifest.DocumentElement.AppendChild($permission)
    $metadata = $manifest.CreateElement('meta-data')
    Set-AndroidAttribute $manifest $metadata 'name' 'firebase_messaging_auto_init_enabled'
    Set-AndroidAttribute $manifest $metadata 'value' 'false'
    [void]$application.AppendChild($metadata)
    $notificationPermission = $manifest.CreateElement('uses-permission')
    Set-AndroidAttribute $manifest $notificationPermission 'name' 'android.permission.POST_NOTIFICATIONS'
    [void]$manifest.DocumentElement.AppendChild($notificationPermission)
    $channelMetadata = $manifest.CreateElement('meta-data')
    Set-AndroidAttribute $manifest $channelMetadata 'name' 'com.google.firebase.messaging.default_notification_channel_id'
    Set-AndroidAttribute $manifest $channelMetadata 'value' 'elder_safety_alerts_v1'
    [void]$application.AppendChild($channelMetadata)
    $manifest.Save($mainFile)
    $activityFiles = @(Get-ChildItem -LiteralPath (Join-Path $stageProject 'android/app/src/main/kotlin') -Recurse -Filter MainActivity.kt -File)
    if ($activityFiles.Count -ne 1) { throw 'Unrecognized Android Kotlin template; staging retained.' }
    $activity = Get-Content -LiteralPath $activityFiles[0].FullName -Raw
    $packageMatch = [regex]::Match($activity, '(?m)^package\s+([a-zA-Z0-9_.]+)')
    if (-not $packageMatch.Success) { throw 'Android package missing; staging retained.' }
    $nativeTemplate = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'android/MainActivity.kt.template') -Raw
    Set-Content -LiteralPath $activityFiles[0].FullName -Value $nativeTemplate.Replace('__PACKAGE__', $packageMatch.Groups[1].Value) -Encoding UTF8
    $debugFile = Join-Path $stageProject 'android/app/src/debug/AndroidManifest.xml'
    [xml]$debugManifest = Get-Content -LiteralPath $debugFile -Raw
    $debugApp = $debugManifest.SelectSingleNode('/manifest/application')
    if (-not $debugApp) {
        $debugApp = $debugManifest.CreateElement('application')
        [void]$debugManifest.DocumentElement.AppendChild($debugApp)
    }
    Set-AndroidAttribute $debugManifest $debugApp 'usesCleartextTraffic' 'true'
    $debugManifest.Save($debugFile)
}
if ($missing -contains 'ios') {
    $infoFile = Join-Path $stageProject 'ios/Runner/Info.plist'
    [xml]$info = Get-Content -LiteralPath $infoFile -Raw
    Set-PlistValue $info 'FirebaseMessagingAutoInitEnabled' ($info.CreateElement('false'))
    $info.Save($infoFile)
    [xml]$debugInfo = $info.OuterXml
    $transport = $debugInfo.CreateElement('dict')
    $allowKey = $debugInfo.CreateElement('key')
    $allowKey.InnerText = 'NSAllowsArbitraryLoads'
    [void]$transport.AppendChild($allowKey)
    [void]$transport.AppendChild($debugInfo.CreateElement('true'))
    Set-PlistValue $debugInfo 'NSAppTransportSecurity' $transport
    $debugInfo.Save((Join-Path $stageProject 'ios/Runner/Info-Debug.plist'))
    $entitlements = @'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>keychain-access-groups</key><array><string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string></array></dict></plist>
'@
    foreach ($file in @('DebugProfile.entitlements', 'Release.entitlements')) {
        Set-Content -LiteralPath (Join-Path $stageProject "ios/Runner/$file") -Value $entitlements -Encoding UTF8
    }
    $projectFile = Join-Path $stageProject 'ios/Runner.xcodeproj/project.pbxproj'
    $project = Get-Content -LiteralPath $projectFile -Raw
    $script:runnerConfigurations = 0
    $project = [regex]::Replace($project, '(?ms)^\s*[A-F0-9]+ /\* (Debug|Release|Profile) \*/ = \{\s*isa = XCBuildConfiguration;.*?^\t\t\};', {
        param($match)
        $block = $match.Value
        if ($block.Contains('INFOPLIST_FILE = Runner/Info.plist;')) {
            $script:runnerConfigurations++
            $entitlementFile = 'Release.entitlements'
            if ($match.Groups[1].Value -ne 'Release') { $entitlementFile = 'DebugProfile.entitlements' }
            $replacement = "CODE_SIGN_ENTITLEMENTS = Runner/$entitlementFile;" + [Environment]::NewLine + ([string][char]9 * 4) + 'INFOPLIST_FILE = Runner/Info.plist;'
            $block = $block.Replace('INFOPLIST_FILE = Runner/Info.plist;', $replacement)
            if ($match.Groups[1].Value -eq 'Debug') {
                $block = $block.Replace('INFOPLIST_FILE = Runner/Info.plist;', 'INFOPLIST_FILE = "Runner/Info-Debug.plist";')
            }
        }
        return $block
    })
    if ($script:runnerConfigurations -ne 3) { throw 'Unrecognized iOS template. Nothing copied; inspect the retained staging directory.' }
    Set-Content -LiteralPath $projectFile -Value $project -Encoding UTF8
}
# Copy only absent platform directories and absent .metadata. Never copy the
# generated lib/, test/, pubspec.yaml, README, analysis settings or .gitignore.
foreach ($platform in $missing) {
    $source = Join-Path $stageProject $platform
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "flutter create did not produce $platform. Nothing copied."
    }
}
foreach ($platform in $missing) {
    $destination = Join-Path $projectRoot $platform
    [IO.Directory]::Move((Join-Path $stageProject $platform), $destination)
    Write-Host "Created $destination"
}
$metadataTarget = Join-Path $projectRoot '.metadata'
$metadataSource = Join-Path $stageProject '.metadata'
if ((Test-Path -LiteralPath $metadataSource) -and -not (Test-Path -LiteralPath $metadataTarget)) {
    [IO.File]::Move($metadataSource, $metadataTarget)
}
# Verify the resolved cleanup path stays inside this project's staging directory.
$resolvedStage = (Resolve-Path -LiteralPath $stageRoot).Path
$resolvedParent = (Resolve-Path -LiteralPath $stageParent).Path.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedStage.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing cleanup outside the staging directory.'
}
Remove-Item -LiteralPath $resolvedStage -Recurse -Force
Write-Host 'Scaffolding complete. Run tool/verify.ps1 for dependency resolution, analysis and Flutter tests.'
