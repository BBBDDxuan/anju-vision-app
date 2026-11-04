# 重建、测试与构建

从 App 仓库根目录进入 mobile-app。源码已展开在这里；不需要从 C模块/mobile-app 复制第二份源码。

## 工具与缓存

~~~powershell
Set-Location 'G:\比赛\AI黑客松\手机端\改进版安装包_v1.2.1\mobile-app'
. .\tool\android-env.ps1
. .\tool\find_flutter.ps1
$flutter = Resolve-FlutterCommand
~~~

默认工具根是 手机端/C模块/tools，可用 ANJU_ANDROID_TOOLS_ROOT 指向其他非 C 盘位置。准备 flutter、jdk、sdk 子目录；脚本不修改系统环境。完整官方压缩包可用 tool/get-flutter-c.ps1 下载并校验 SHA256；断点文件保留。不含真实 Firebase/签名。

本机另行准备 flutter-light SDK（官方 3.47.8 tag）；如使用它，环境脚本后将 FLUTTER_ROOT 设为同一 tools 下 flutter-light，或给 build-c.ps1 显式传 -FlutterPath。Android SDK/JDK 仍需准备；Flutter --version 成功不等于 APK 可构建。

## 源码与纯 Dart 核心

~~~powershell
node tool/source_check.mjs
node tool/check-c-config.mjs
node tool/check-c-scope.mjs
& 'G:\比赛\AI黑客松\手机端\C模块\tools\dart-sdk\bin\dart.exe' test/notifications/gate_scenarios.dart
~~~

核心测试覆盖 37 个合成场景。source_check 检查统一 8000 默认地址与 B 快照接口；完整集成仍须入口装配和真机验收。

## Flutter

本机 Windows 的中文路径会使 Flutter LSP 消息截断和 shader include 失败。可使用下面的可复用脚本建立英文临时盘符；检测盘符已占用且目标不一致时会拒绝覆盖。不移动或复制源码，不支持 Junction 的文件系统也可用。

~~~powershell
. .\tool\ascii-env.ps1
# 现在位于 Y:\mobile-app，工具为 X:\flutter-light
$flutter = Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'
~~~

盘符对应本机 App 仓库根目录与 C 工具目录，重启/新会话后按需重新运行；命令全部结束后可用 subst.exe X: /D 和 subst.exe Y: /D 移除这两个本任务别名。脚本不替换其他已有映射。


~~~powershell
& $flutter pub get --enforce-lockfile
& $flutter analyze --no-fatal-infos
& $flutter test
~~~

如果曾在中文路径运行失败，首次进入英文映射后执行 flutter clean，再恢复锁定依赖和测试，避免沿用缺 shader 的生成缓存。导入 B 之前这样复跑得到 66 passed、2 skipped；导入 B 后的当前结果见 validation/PUBLICATION_RESULTS.md。

保持 pubspec.lock；不要盲目升级依赖。纯 Dart 通过不能替代完整 Flutter 分析/测试。中文路径若遇分析器输出异常，可用同一 Flutter SDK 自带 Dart 分析并保留结果，不能忽略真实编译错误。

## A/C 后端离线测试

从 website 仓库根目录使用现有后端 Python 环境运行：

~~~powershell
$env:PYTHONPATH = $PWD.Path
$env:PYTHONUTF8 = '1'
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m pytest tests/push_notifications tests/test_alert_center.py -q --basetemp="$env:TEMP\anju-c-regression" --junitxml=docs/c-notifications/validation/backend-junit.xml
~~~

使用英文临时路径：本机 OpenCV imwrite 对中文路径失败，初次回归因此有 10 项夹具失败；改英文临时目录后 49 项通过；补充配置失败及离线签名回归后最终 59 项通过。不因此改 A 文件。若复用 G 盘 TEMP（含中文），需另指定可写英文临时目录。测试仅 mock HTTP、合成图片/数据，不运行摄像头、真实 FCM 或计费模型。

## APK

~~~powershell
. .\tool\android-env.ps1
.\tool\build-c.ps1
~~~

Firebase 测试包：本地 android/app/google-services.json 要匹配实际测试包 com.eldersafety.elder_safety_mobile.test，再运行 build-c.ps1 -WithFirebase。生产包名没有 .test，不能混用。USE_FIREBASE 和 Gradle enableFirebase 必须一致，脚本统一设置。

正式升级需原 key.properties 与私钥，并核对旧 APK 证书摘要：

~~~powershell
.\tool\build-c.ps1 -Release -WithFirebase -ExpectedSigningSha256 '<旧正式APK证书的64位SHA256>'
~~~

默认先检查锁文件、源码/边界、分析和测试，再构建分 ABI APK，使用 apksigner 验签；正式证书不一致失败。输出 docs/c-notifications/builds 下 APK/BUILD-METADATA.json，记录源码 HEAD、未提交状态、Firebase 开关、版本、文件及证书摘要。构建不能自动视为安装或真机通过。当前候选 1.2.2+7；旧 APK 未覆盖。

## 仅编译剩余时的交接

将实际构建日志写到 mobile-app/tool/logs/c-build.log 后后台运行；用下列命令检查。状态失败/日志异常需修复，仅进程结束不算成功。

~~~powershell
Get-Content .\tool\logs\c-build-status.json
Get-Content .\tool\logs\c-build.log -Tail 50
~~~

成功需 state=succeeded 且 stage=apk_produced_not_phone_verified，并核对 BUILD-METADATA.json 及 APK SHA256。没有启动构建时状态文件不存在是正常的；不得用旧 APK 代替。
