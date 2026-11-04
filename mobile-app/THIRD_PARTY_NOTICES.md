# 第三方组件

本版移除单张照片 ONNX 权重。开源许可可从“我的 → 关于与开源许可”查看。

实时摄像头采用 VideoLAN `org.videolan.android:libvlc-all:3.7.7` 原生库（Maven Central 官方发布，POM 声明 LGPL 2.1），通过本项目 Android 原生视图接入，原生库未修改。LibVLC 与 VLC 各依赖的源码、构建脚本和许可：

- https://code.videolan.org/videolan/libvlcjni
- https://code.videolan.org/videolan/vlc
- https://repo.maven.apache.org/maven2/org/videolan/android/libvlc-all/3.7.7/
- https://www.videolan.org/legal.html

LGPLv2.1、LGPLv3 与 GPLv3 附录文本保存在 `assets/licenses/native-video.txt` 并注册到 App 许可页。原生动态库与 App 源码分开，可依照上述对应源码重新构建替换库。

Flutter/Dart、video_player、file_picker、webview_flutter、flutter_secure_storage、Firebase 等依赖的版本见 pubspec.lock；各包的许可由 Flutter 汇总到 App 许可页。
