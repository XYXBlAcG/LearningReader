# 讲一讲

此功能由 iOS 提供；共享协议与提示词位于 [AICore](../Sources/AICore)，macOS 暂不提供交互入口。

## 配置与使用

打开“设置 → AI 服务与提示词”，添加服务，填写接口类型、HTTPS 基础地址、API Key 和模型 ID。自定义服务须兼容所选协议；地址可包含网关前缀和 API 版本。最终请求地址在编辑页显示。支持的协议及默认地址以 [AIProtocol](../Sources/AICore/AIConfiguration.swift) 为准。

DeepSeek 基础地址可直接填写 `https://api.deepseek.com`，请求地址会显示为 `/chat/completions`。测试编辑中的配置后，点击“保存并用于文字讲解”即可保存并选为默认。

选择默认文字服务；图片服务可以独立选择，也可共用支持图片的文字服务。填写的“支持图片”是服务配置，不是能力检测结论。分别执行文字和图片测试，检查返回内容；测试会产生真实 API 请求，按服务商规则计费。

在课程笔记、练习、本地 HTML 或普通网页中选中文字，打开系统选区菜单并点击“讲一讲”。点击后先显示准备面板；默认询问是否使用整篇文章，上下文开关的初始值由设置决定。关闭“每次询问是否使用全文”后直接按默认值发起请求。仅选区模式不发送全文；全文模式发送当前 Markdown 文件完整原文，或 HTML／网页的整页可读正文。Markdown 折叠的参考答案也属于全文；图片、脚本和其他页面不会递归上传。系统菜单空间不足时可能需展开更多选项。禁用选字的页面、跨域嵌入、canvas 和图片文字不保证能取到文本，可改用图片提问。

课程阅读更多菜单提供“拍照提问”和“选择图片”；可在预览中拖动框选并裁剪题目，再点击“讲一讲”。拍照需要系统相机授权。识别和解题均由图片服务处理，客户端不运行 OCR 或语言模型。

回答面板支持停止、重新讲解、复制当前回答和继续追问。所选材料附在首条消息中，追问复用这份上下文。客户端超限时明确提示，不截断全文；模型服务可能有更小的上下文限制。输入预算见 [AIInputBudget](../Sources/AICore/AIPrompts.swift)。讲解默认自动保存到本机，可在 AI 设置关闭自动保存，也可在回答页手动保存；保存过的会话会继续保存追问。回答与追问使用会话开始时的配置，改变默认服务或提示词影响新问题。

## 对照阅读与本地讲解

回答页上方默认约三分之一显示完整题干、所选内容或已确认题图，下方显示讲解；两个区域独立滚动，支持拖动分隔条调整比例、收起题干及展开查看。对照区不会改变请求中的全文上下文选择，也不修改课程 Markdown。

课程参考答案提供同样的对照阅读；多题文件通过章节和题号选题，可切换上下题，原文仍可展开阅读。对应关系不明确时显示未匹配，不自动猜题。

课程目录中的“本地讲解”支持搜索、课程筛选、改标题、右滑删除、批量删除和撤销。停止或中断的回答保留有效内容并显示状态；重新生成和追问保留回答版本。保存失败会提示，不能把屏幕上显示的内容视为已落盘。

本地记录包含题目快照、已使用的上下文、回答和必要题图；阅读不依赖当前 Key 或原课程仍存在。继续追问时选择本次服务，沿用保存的上下文。返回原题沿用课程定位，原文变更时保存的题干不会被替换。

支持单篇 Markdown 导出、含题图的完整 ZIP 条目，以及全部讲解的 JSON 备份和导入。ZIP 中的 Markdown 与附件可独立阅读，record.json 用于恢复。导入相同记录 UUID 时保留本机记录。导出包含本地学习内容，API Key 不进入记录或备份。

- [学习记录与版本](../Sources/AICore/StudyRecord.swift)
- [持久化、备份与附件](../Sources/StudyLibrary)
- [原生对照与讲解库](../Apps/iOS/Study)
- [题目与答案对应](../Sources/LearningCore/Resources/Reader/study-questions.js)

## 菜单与推理

在“长按菜单操作”中新增、编辑、排序、启用或删除操作，例如“出一道变式”。每项只有按钮名称与任务提示词；全部复用当前文字服务、上下文选择、教学和公式规范。默认“讲一讲”的任务提示词在此编辑。

服务编辑页可启用自定义推理参数，按接口选择推理强度、DeepSeek 思考模式、Claude 自适应思考或思考 Token 预算；关闭时沿用服务默认。最大输出 Token 可留空；Claude 显式思考预算须小于输出上限。支持范围由所填模型与网关决定，使用连接测试验证。实际参数与约束见 [AIReasoning](../Sources/AICore/AIReasoning.swift) 和 [AIRequest](../Sources/AICore/AIRequest.swift)。官方协议：[OpenAI](https://developers.openai.com/api/docs/guides/reasoning)、[DeepSeek](https://api-docs.deepseek.com/guides/thinking_mode/)、[Claude](https://platform.claude.com/docs/en/build-with-claude/effort)、[Gemini](https://ai.google.dev/gemini-api/docs/generate-content/thinking)。

## 教学与公式

文字讲解、图片讲题、教学规范和公式规范均可在设置中编辑、保存及恢复默认；实际请求采用保存的内容，不附加隐藏的固定教学或公式要求。默认值只有一个定义源：[AIPrompts](../Sources/AICore/AIPrompts.swift)。默认数学教学依据 [MathLearning 项目要求](https://github.com/XYXBlAcG/MathLearning/blob/main/AGENTS.md) 与 [输出规范](https://github.com/XYXBlAcG/MathLearning/blob/main/输出规范.md) 选取与答疑相关的规则，不触发课程归档或每日出题流程。

默认回答采用 Markdown 文件公式格式；渲染器支持的定界符以 [MathJax 配置](../Sources/LearningCore/Resources/Reader/math-config.js) 为准。课程与 AI 回答共用 [Markdown 渲染入口](../Sources/LearningCore/Resources/Reader/markdown.js) 与 [本地依赖](../Sources/LearningCore/Resources/Reader/vendor/README.md)，支持中文标点旁的粗体。公式源选取与复制见 [selection-copy.js](../Sources/LearningCore/Resources/Reader/selection-copy.js)；流式排版见 [ai-answer.js](../Sources/LearningCore/Resources/Reader/ai-answer.js)。

## 数据与验收入口

密钥保存在系统钥匙串；原生层直接访问用户配置的服务。“讲一讲”发送当前选区、标题及选择附带的全文，不上传整个课程或 GitHub 凭证。正文提取与页面身份见 [ReaderExplanation](../Sources/LearningCore/Resources/Reader/explanation.js)。图片在用户确认后发送。

- [准备、上下文选择与错误状态](../Sources/AICore/AIInvocation.swift)
- [操作配置](../Sources/AICore/AISelectionAction.swift)
- [配置、会话与界面](../Apps/iOS/AI)
- [请求与接口适配](../Sources/AICore/AIRequest.swift)
- [流事件与取消](../Sources/AICore/AIClient.swift)
- [协议与传输测试](../Tests/AICoreTests)
- [离线公式渲染测试](../Tests/ReaderTests/ai-markdown.test.cjs)
- [全文与页面身份测试](../Tests/ReaderTests/reader-explanation.test.cjs)
- [人工验收](开发与验收.md#人工验收)
