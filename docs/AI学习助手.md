# 讲一讲

此功能由 iOS 提供；共享协议与提示词位于 [AICore](../Sources/AICore)，macOS 暂不提供交互入口。

## 配置与使用

打开“设置 → AI 服务与提示词”，添加服务，填写接口类型、HTTPS 基础地址、API Key 和模型 ID。自定义服务须兼容所选协议；地址可包含网关前缀和 API 版本。最终请求地址在编辑页显示。支持的协议及默认地址以 [AIProtocol](../Sources/AICore/AIConfiguration.swift) 为准。

选择默认文字服务；图片服务可以独立选择，也可共用支持图片的文字服务。填写的“支持图片”是服务配置，不是能力检测结论。分别执行文字和图片测试，检查返回内容；测试会产生真实 API 请求，按服务商规则计费。

在课程笔记、练习、本地 HTML 或普通网页中选中文字，打开系统选区菜单并点击“讲一讲”。系统菜单空间不足时可能需展开更多选项。禁用选字的页面、跨域嵌入、canvas 和图片文字不保证能取到文本，可改用图片提问。

课程阅读更多菜单提供“拍照提问”和“选择图片”；可在预览中拖动框选并裁剪题目，再点击“讲一讲”。拍照需要系统相机授权。识别和解题均由图片服务处理，客户端不运行 OCR 或语言模型。

回答面板支持停止、重新讲解、复制当前回答和继续追问。关闭后不保存永久聊天历史。回答与追问只使用当前会话的模型配置，改变默认服务影响新问题。

## 教学与公式

默认模板和固定教学、公式要求只有一个定义源：[AIPrompts](../Sources/AICore/AIPrompts.swift)。设置支持修改文字与图片讲解偏好，或恢复默认。数学教学依据 [MathLearning 项目要求](https://github.com/XYXBlAcG/MathLearning/blob/main/AGENTS.md) 与 [输出规范](https://github.com/XYXBlAcG/MathLearning/blob/main/输出规范.md) 选取与答疑相关的规则，不触发课程归档或每日出题流程。

App 回答采用 Markdown 文件公式格式。课程与 AI 回答共用 [Markdown 渲染入口](../Sources/LearningCore/Resources/Reader/markdown.js)、[MathJax 配置](../Sources/LearningCore/Resources/Reader/math-config.js) 与同一份本地依赖。公式源选取与复制见 [selection-copy.js](../Sources/LearningCore/Resources/Reader/selection-copy.js)；流式排版见 [ai-answer.js](../Sources/LearningCore/Resources/Reader/ai-answer.js)。

## 数据与验收入口

密钥保存在系统钥匙串；原生层直接访问用户配置的服务。课程选区附带限长邻近上下文，HTML 与网页选区只附带标题；不会自动上传整页、整个课程或 GitHub 凭证。图片在用户确认后发送。

- [配置、会话与界面](../Apps/iOS/AI)
- [请求与接口适配](../Sources/AICore/AIRequest.swift)
- [流事件与取消](../Sources/AICore/AIClient.swift)
- [协议与传输测试](../Tests/AICoreTests)
- [离线公式渲染测试](../Tests/ReaderTests/ai-markdown.test.cjs)
- [人工验收](开发与验收.md#人工验收)
