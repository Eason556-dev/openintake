# Contributing

欢迎 Fork、提出 issue 和 PR。代码采用 MIT；贡献代码须与该许可兼容。

1. 阅读 README、docs/ARCHITECTURE.md 和 docs/PRIVACY.md。
2. 使用虚构产品与摄入数据。不要提交个人健康记录、密钥或签名材料。
3. 营养计算、单位、解析、去重、存储和同步状态变更应提供有意义的回归测试；简单 UI 文案无需复制实现的测试。
4. 执行 `swift test` 和 README 的无签名 iOS 编译。增删 Swift 文件后运行 `python3 scripts/generate_project.py`。
5. PR 描述触发条件、行为变化和验证证据；标明哪些需要真机验证。

核心约束：未知不为零、扫描不等于摄入、药物不等于营养、用户确认与来源分开、网络与 AI 必须可选。不要添加服务器或账号作为默认依赖，不允许自动上传健康记录。

API 行为需要引用 Apple 官方文档或 SDK 声明。发现 OCR 错误，优先增加保守拦截和虚构标签测试，而非推测补全。
