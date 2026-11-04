# C 通知模块与构建交付

App 已导入完整 mobile-app 源码和 B 发布版本的 25 个业务文件；C 拥有的通知、Android 配置、测试和构建脚本位于 mobile-app/。候选版本 1.2.2+7，未构建新 APK。

统一后端只在 anju-vision-website 维护；C 的独立异步插件位于该仓库 backend/push_notifications/，测试位于 tests/push_notifications/。没有重新引入被 A 撤回的 App server/ 副本。

- [源码来源与上传范围](PUBLICATION.md)：准确提交基线和未完成的装配项。
- [A 的插件配置](A_INTEGRATION.md)：使用现有异步接点，不修改公共入口、鉴权或数据库模型。
- [B 的通知装配](B_INTEGRATION.md)：唯一 snapshot 数据流、scope、点击和 token 生命周期。
- [构建方法](BUILD_AND_TEST.md)、[真机验收](DEVICE_ACCEPTANCE.md)。
- [本次上传前验证](validation/PUBLICATION_RESULTS.md)；validation/RESULTS.md 是导入 B 前的历史结果。

本次通过 Git 提交可审查的源码，不上传源码 ZIP。旧附件未覆盖；package/ 和 builds/ 在本目录忽略。

当前 B 公共入口仍待装配 C 模块；独立测试通过不等于通知集成完成。Firebase 配置、Android SDK/JDK、原签名、前后台和锁屏两机验收均独立验证。provider accepted 表示提供商接受，不能等同手机送达或严格 exactly-once。当前只支持单后端 origin|default，不宣称多租户隔离。
