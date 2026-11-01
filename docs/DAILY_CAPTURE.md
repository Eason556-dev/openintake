# 0.3.0 日常摄入流程

> 版本说明（2026-10-31）：0.7.0 已移除内置模型与自动餐食营养估算。本文涉及 AI 的内容为历史实现或计划；当前行为见 [轻量记录版本](LIGHTWEIGHT_RECORDING.md)。

## 补充剂：扫描后自动填表

拍摄结束立即以可验证的离线结果预填成分；启用且可用时，本机 AI 随后整理名称、含量原文和包含关系。数值、单位、计量基准、证据及 HealthKit 映射由 IntakeCore 独立核对。模型不负责选择 HealthKit 类型。

AI输入保留证据ID、页码及精简的位置/表格信息；每段约1800字符或12个文字块，两行重叠避免名称/数量在段边界断开。输出精简为成分表，包装基准与建议原文由独立证据流程保留。每段独立本机模型会话，结构化流式输出提供实时活跃信号，完整段落才进入验证和英法去重。界面显示段落进度，可停止等待；连续60秒无模型进度或总计240秒时取消本次结果接收并保留已验证草稿，不再固定45秒截断正常生成。重新扫描或离开编辑页会使旧请求失效，迟到输出不能覆盖新草稿。停止或超时只是取消本次结果接收，系统模型的实际取消响应由系统管理。正常项目自动预填；无法可靠对应的项目明确标记待确认。保存产品不记录摄入。

点线、竖线等标签分隔符不应污染名称身份。对于分开的名称列与数量列，使用原始坐标匹配同一水平行；唯一名称、唯一数量且同页才自动关联。多数量列、百分比列和不同计量基准不自动选取。AI 提示包含坐标、列号和置信度。复杂曲面与 OCR 错漏仍需实拍验收。

## 同步中心

首页显示已写入、待同步及仅本机计数，进入同步状态可查看每次摄入的营养项目、数量、时间、错误和撤销状态。同步按钮只处理待写入和待删除事件，不重复发送已完成事件。

“已写入”表示 HealthKit 保存调用成功返回；不是读取 Apple 健康核验的结果。授权拒绝或写入失败时保留本地事件。仅本机表示当时没有允许写入的营养项；修改产品映射不会补写历史事件，需要撤销并重新记录。

## 饮水圆环与提醒

- 首页提供 150、250、500 mL 和自定义实际毫升数，直接复用摄入事件、HealthKit 同步、重复拦截和撤销。
- 圆环统计本 App 在当前本地自然日的饮水记录；包含待同步量，排除已撤销和待删除事件，不读取其他来源饮水。
- 初始目标 2,000 mL 仅为可修改的界面目标，不是医学推荐。
- 用户主动开启本机通知；选择开始、结束小时及间隔，以 UNCalendarNotificationTrigger 每日重复。关闭会移除本 App 饮水提醒。重排失败清除部分计划并将设置标记为关闭。
- 当前是固定时段提醒，达到目标不会自动停止；专注模式和系统通知权限会影响送达。没有服务器或推送账号。

快捷指令可添加 OpenIntake「记录饮水」并设定实际毫升数；App Shortcut 也提供饮水入口。

## 餐食照片快捷指令

iOS 18+ 在 Shortcuts 创建：

1. 添加系统「拍摄照片」动作。
2. 添加 OpenIntake「识别餐食照片并确认摄入」。
3. 将第二步的“餐食照片”设为第一步的拍摄结果。
4. 保存，可绑定 Action Button 或由 Siri 运行。
5. App 打开草稿后自动调用本机图片模型；核对食物名称，填写每项**实际摄入克数**，按需修正每 100 g 营养值。
6. 开启份量／估算确认，点击“确认并记录”。App 持久化事件并尝试同步；在同步中心查看结果或撤销。

确认放在 App 中完成，快捷指令导入动作本身返回时仅表示已打开草稿，**不表示已写入健康**。也可以直接从首页“拍照记录本次餐食”进入相同流程。动作不会自动创建或安装到用户的快捷指令库。

### API 与能力边界

本机 Xcode 27 SDK 确认 FoundationModels `Attachment(CGImage)`、PromptBuilder 图片输入及 `capabilities.contains(.vision)` / `.guidedGeneration` 均为 iOS 27+ API。本实现只使用 `SystemLanguageModel.default`，不调用 Private Cloud Compute。先检查本机模型可用及视觉、结构化生成能力，才尝试识别；API 存在不等于当前设备模型有该能力。

- [Apple 图片提示文档](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [IntentFile](https://developer.apple.com/documentation/appintents/intentfile)
- [本机通知](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)

模型返回食物及每 100 g 营养**估算**，不估计实际吃了多少。照片无法证明油、酱汁和真实营养量。独立校验拒绝未知类型、错误量纲、重复项、非有限或非正数及明显不可能的值，但这种校验不能证明估算准确。未知营养项省略，不补零；照片不用于推断饮水体积。饮品目前也按实际质量 g 校准，不假定其密度为 1。

用户可关闭 AI，模型不可用、拒绝或超时会明确提示并允许手动填入名称、质量及已知营养值；不静默调用云模型。食物项及不确定性、每 100 g 数值和实际份量保存在事件产品快照中，不加入可复用的补充剂产品列表。照片仅在当前草稿内存中保留，取消或完成后释放，不写入 JSON，也不保留文件 URL。

真实餐食图片模型和系统快捷指令端到端行为仍需支持设备验收；编译与核心测试不能替代这一项。

## 0.3.2 通知与服用提醒

- 通知权限独立于HealthKit，不需要APNs、服务器、账号或额外推送entitlement。主动点“允许通知”或保存启用的提醒时调用官方requestAuthorization(.alert,.sound)；已拒绝时明确引导系统通知设置。
- 读取notificationSettings显示授权、横幅/声音状态；显示本App的pending请求数量。5秒测试提醒不会写入摄入数据。
- 保留共享UNUserNotificationCenterDelegate，前台willPresent返回banner/list/sound。
- 每个补充剂可设每日一次提醒，默认关闭，用户自定时间。稳定产品UUID作为通知标识，重复保存替换同一请求；关闭/删除产品移除pending计划。最多30个补充剂提醒，加最多24个饮水时段和1个测试请求，控制待处理数量。
- 用户返回系统设置时刷新权限状态。已安排不等于实际送达，测试通知与真实设备验收才能检查显示；专注模式和系统设置可能抑制横幅。
- 不从包装推荐剂量创建自动服用计划。提醒本身永远不触发健康写入。提醒内容含产品名称，系统锁屏预览设置由用户控制。

参考：[通知授权](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)、[Foundation Models上下文管理](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)。模型输入、schema及输出均占用上下文，不能只按原始OCR字数判断容量。分段和精简减少负担，不保证所有标签/设备都在固定时间完成。
