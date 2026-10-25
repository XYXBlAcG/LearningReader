# 讲一讲

此功能由 iOS 提供；共享协议与提示词位于 [AICore](../Sources/AICore)，macOS 暂不提供交互入口。

## 配置与使用

打开“设置 → AI 服务与提示词”，添加服务，填写接口类型、HTTPS 基础地址、API Key 和模型 ID。自定义服务须兼容所选协议；地址可包含网关前缀和 API 版本。最终请求地址在编辑页显示。支持的协议及默认地址以 [AIProtocol](../Sources/AICore/AIConfiguration.swift) 为准。

选择默认文字服务；图片服务可以独立选择，也可共用支持图片的文字服务。填写的“支持图片”是服务配置，不是能力检测结论。分别执行文字和图片测试，检查返回内容；测试会产生真实 API 请求，按服务商规则计费。

在课程笔记、练习、本地 HTML 或普通网页中选中文字，打开系统选区菜单并点击“讲一讲”。选区标记讲解重点，同时发送当前 Markdown 文件完整原文，或 HTML／网页的整页可读正文。Markdown 折叠的参考答案也属于全文；图片、脚本和其他页面不会递归上传。系统菜单空间不足时可能需展开更多选项。禁用选字的页面、跨域嵌入、canvas 和图片文字不保证能取到文本，可改用图片提问。

课程阅读更多菜单提供“拍照提问”和“选择图片”；可在预览中拖动框选并裁剪题目，再点击“讲一讲”。拍照需要系统相机授权。识别和解题均由图片服务处理，客户端不运行 OCR 或语言模型。

回答面板支持停止、重新讲解、复制当前回答和继续追问。全文附在首条消息中，追问复用这份上下文。客户端超限时明确提示，不截断全文；模型服务可能有更小的上下文限制。输入预算见 [AIInputBudget](../Sources/AICore/AIPrompts.swift)。关闭后不保存永久聊天历史。回答与追问使用会话开始时的配置，改变默认服务或提示词影响新问题。

## 教学与公式

文字讲解、图片讲题、教学规范和公式规范均可在设置中编辑、保存及恢复默认；实际请求采用保存的内容，不附加隐藏的固定教学或公式要求。默认值只有一个定义源：[AIPrompts](../Sources/AICore/AIPrompts.swift)。默认数学教学依据 [MathLearning 项目要求](https://github.com/XYXBlAcG/MathLearning/blob/main/AGENTS.md) 与 [输出规范](https://github.com/XYXBlAcG/MathLearning/blob/main/输出规范.md) 选取与答疑相关的规则，不触发课程归档或每日出题流程。

默认回答采用 Markdown 文件公式格式；渲染器支持的定界符以 [MathJax 配置](../Sources/LearningCore/Resources/Reader/math-config.js) 为准。课程与 AI 回答共用 [Markdown 渲染入口](../Sources/LearningCore/Resources/Reader/markdown.js) 与 [本地依赖](../Sources/LearningCore/Resources/Reader/vendor/README.md)，支持中文标点旁的粗体。公式源选取与复制见 [selection-copy.js](../Sources/LearningCore/Resources/Reader/selection-copy.js)；流式排版见 [ai-answer.js](../Sources/LearningCore/Resources/Reader/ai-answer.js)。

## 数据与验收入口

密钥保存在系统钥匙串；原生层直接访问用户配置的服务。“讲一讲”发送当前选区、文件全文与标题，不上传整个课程或 GitHub 凭证。正文提取与页面身份见 [ReaderExplanation](../Sources/LearningCore/Resources/Reader/explanation.js)。图片在用户确认后发送。

- [配置、会话与界面](../Apps/iOS/AI)
- [请求与接口适配](../Sources/AICore/AIRequest.swift)
- [流事件与取消](../Sources/AICore/AIClient.swift)
- [协议与传输测试](../Tests/AICoreTests)
- [离线公式渲染测试](../Tests/ReaderTests/ai-markdown.test.cjs)
- [全文与页面身份测试](../Tests/ReaderTests/reader-explanation.test.cjs)
- [人工验收](开发与验收.md#人工验收)
