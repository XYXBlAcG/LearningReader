# 平台版本

- iOS 构建与正式发布：[iOS-Version.xcconfig](iOS-Version.xcconfig)
- macOS 构建：[Version.xcconfig](Version.xcconfig)

平台版本独立维护；Release 标签由 iOS 配置校验，不在工作流中重复填写版本号。

- 发布验证开关：[Validation.json](Validation.json)。PDF 专项关闭时仍执行非 PDF 阅读器、核心及原生检查。
