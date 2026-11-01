# 架构

## 决策

原生 Swift/SwiftUI，iPhone iOS 17+，纯 Swift 核心库，零第三方运行时依赖。VisionKit 文档相机提供稳定照片输入，Vision OCR 在后台任务处理图像；UI 在 MainActor 上编辑草稿。选择拍摄确认而非持续流式 DataScanner，避免实时结果增删导致草稿抖动。相机不可用时可手动粘贴文字。

本地资料库是产品模板及写入审计账本，不聚合 Apple 健康其他数据。JSON atomic write 足以支持第一阶段的小规模个人产品和摄入事件；产品及历史增长后评估 SQLite/SwiftData。带 schemaVersion，未知版本和损坏文件阻止后续写入，绝不自动清空。

App 和 Intent 都在同一个前台主应用进程的 MainActor 单例执行；busy 锁覆盖跨 await 的完整操作。没有 App Group、扩展进程或并行写入者。新增 widget、watch 或后台扩展前，必须替换为具有事务和跨进程互斥的存储。

## 数据模型

| 模型 | 字段与不变量 |
|---|---|
| Product | UUID、revision UUID、名称、supplement/medication 分类、每份文字定义、结构化成分图、可选宽泛映射同意、每份粒数、旧版稀疏营养数组、原始 OCR 文本、可选 AI 原始草稿、confirmedAt |
| NutrientAmount | Nutrient 枚举、有限非负数、g/mg/mcg/mL/L/kcal/kJ、labelOCR/manual/database/aiEstimate 来源；同一产品不得重复营养项 |
| IntakeEvent | 独立 UUID、完整产品版本及 HealthKit 写入清单快照、有限正份数、实际记录时间、同步状态、最近错误 |
| Library | schemaVersion=1、产品列表、事件账本 |

确认状态和提取来源分别存储：AI 来源经用户核对后仍保持 aiEstimate，不伪装成数据库。手动修改营养数值或单位时来源改为 manual；原始 OCR 及 AI 草稿仍在产品快照内。数据库来源是未来适配器的扩展点，尚未接入外部数据源。

质量计算完全确定：`标签每份质量 × 单位克系数 × 实际份数`。明确的 Serving Size / Each capsule / 每粒声明会提取 unitsPerServing，仍需核对。实际粒数除以每份粒数得到实际份数；未知时不猜测，保留按份入口。

## 流程及恢复

1. 扫描/粘贴 → OCRDocument → 可选 SemanticParsingProvider → SemanticValidator → 验证草稿。扫描不写资料库，也不调用 HealthKit。
2. 编辑/人工确认 → validate → 原子保存 Product。
3. 实际摄入 → 计算及去重 → 原子保存 pending 事件 → 按写入清单请求 HealthKit 授权 → 写样本 → 原子标记 synced。没有可写类型时直接标记 localOnly，无需健康授权。
4. 写入失败保留 pending；用户重试。每个样本的稳定 syncIdentifier 为 `intake.<event UUID>.<nutrient>`，syncVersion 初始为 1，重复投递使用同一标识。依赖 HealthKit 官方同步标识语义，真实重试行为须真机验证。
5. 撤销先原子保存 deletionPending，再按事件/营养 syncIdentifier 删除本 App 样本，成功后标记 deleted。中断后继续删除，不再写入。逐营养删除可部分成功，重复删除已不存在的样本是安全的。

不申请其他来源营养数据的读取权限。当前重复检测覆盖本应用同一产品/份数 60 秒内的事件，无法知道其他 App 已记录的摄入，也不声称做全局去重。已撤销和待撤销事件不拦截新摄入。

产品编辑生成新 revision，不篡改历史事件。摄入纠错使用撤销后重新记录；当前界面不支持自选历史时间。发布前若需要补记/历史纠错，应加入独立时间选择与关联 replacement ID，避免无意改写时间语义。

## HealthKit 边界

写每个已确认 nutrient 的 HKQuantitySample，质量用 g、体积用 mL、能量用 kcal，start/end 均为摄入时间。只请求当前事件包含类型的写权限；授权流程完成不等于获准，逐类型检查 sharingAuthorized。

自定义元数据包含 product UUID、产品名称、revision、origin、confirmedAt，另加系统 syncIdentifier、syncVersion、WasUserEntered。没有伪造未知营养项或宽泛食物 correlation。删除仅按独立 syncID，HealthKit 本身将删除限制为当前 App 写入的数据。

MVP 有意不写药品、总食物质量、健康评分、设备指标。没有自定义 Medications 写入替代方案。

## 扩展边界

- `NutritionHealthStore`：授权/写入/删除协议，生产适配 HealthWriter，测试适配故障模拟。
- `LabelParser`：纯函数提取，不能直接产生 confirmedAt。
- `SemanticParsingProvider`：语言无关的可选语义提供者；生产使用 Apple SystemLanguageModel，失败转 OfflineSemanticProvider 并说明原因；均不能直接写 HealthKit。
- 未来 ProductDataSource：条形码/公共数据库返回带 URL、版本、抓取时间的草稿。
- 未来 MealEstimator：输出明确的估算及份量提示，不自动合并为确认标签值。
- 未来 BYOK/self-hosted：单独用户选择和网络隐私说明，默认不启用。

当前 UI 只有产品、实际摄入记录及同步状态；成功状态内联显示，默认摄入不需要额外确认弹窗。

## 结构化成分与兼容

Ingredient 保存可空数量、原始单位、来源、parentID、component/equivalent 关系及备注。未知不等于零。HealthPlan 只投影准确类型和用户同意的宽泛类型；已选父成分抑制映射到同一类型的子成分，等效量不写入。重复独立类型拒绝自动求和，循环、重复 ID、子成分总质量超过父成分均阻止保存。

新字段均为可选，schemaVersion 保持 1，旧资料库可读取。旧产品进入编辑器才转换为成分列表，旧事件的营养快照保持兼容。新事件冻结 healthWriteSnapshot；后续修改产品、映射同意或解析规则不改变旧事件的重试与撤销。来源及全部未映射成分仍在事件产品快照内。

OCRDocument、SemanticProposal、OfflineSemanticProvider、SemanticValidator、SemanticReconciliation、IngredientMapper、HealthPlan 和数量不变量均属于 IntakeCore；SupplementParser/LabelParser 保留为旧版兼容解析器，当前扫描界面不再把 AI 自由文本交给它们；ProductEditor 只负责呈现与人工确认，HealthWriter 只负责 Apple API 适配。详见 [映射规则](INGREDIENT_MAPPING.md)。

## 启动与可选系统服务

首页启动只需要本地资料库。HealthWriter 延迟到首次同步时创建；App Shortcuts 参数刷新在首页出现后调度到 utility 任务，不在 App.init 或产品保存主线程同步调用。多次刷新合并并保留刷新期间发生的后续变更；系统索引服务故障不能阻止绘制或保存。`--startup-audit` 仅输出首页 onAppear 就绪标记，不包含个人数据。

## 语义升级

详见 [四段语义管道](SEMANTIC_PIPELINE.md)。产品增加可选 OCRDocument、SemanticProposal、ruleProposal、LabelBasis、recommendations、parsingProvider；Ingredient 增加标准 ID、原文名称/证据 ID、化学形式、原始标值、比例、浓度及待确认原因。所有新增持久化字段可选，旧 JSON 兼容。推荐剂量不参与 IntakeEvent 运算；事件仍冻结产品和最终 HealthKit 写入清单。

## 0.3.3 统一证据与扫描状态

LabelNameEvidence 统一目录、规则与 AI 验证的名称证据；LabelEvidenceLink 统一数量跨行/表格/位置规则。ChemicalSource 保存无独立摄入量的化学来源及其证据。OCREvidenceMerge 合并同一物理文本的段落/表格表示。LabelRecognitionSession 统一每轮规则与模型结果、代际取消和去重采用，空识别不会保留旧成分。SemanticProposal.rawModelResponses 为可选本机原始 JSON，旧数据兼容。详见 [修复报告](LABEL_PIPELINE_REPAIR.md)。

## 可恢复撤销（0.3.4）

最近摄入仅左滑显示撤销，禁用 full swipe；已撤销/待撤销行与同步中心提供恢复。Library.restore 保留事件 ID、原时间、数量和冻结映射，清除旧核验并递增可选 healthSyncVersion（旧数据默认为1），原子保存 pending 后执行同步。为处理部分删除，恢复及其重试先按本事件精确来源/同步ID清理残留，再写入和核验；失败保留 pending。没有增加摄入事件。已有相同产品/份数/时间附近的替代记录时拒绝恢复以防重复。较高版本使用 Apple [同步标识与版本语义](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier)。

## 0.4.0 手动食品领域

ManualNutritionTemplate 保留原始每份基准、饮料/食品类型、包装/常用份量及用户已知营养；生成food产品并标准化为每100mL/g，Product.validate 检查与原始标值一致。可选字段支持旧资料读取。未知模板用未知成分保留本机，不能产生虚构样本。OrdinarySalt使用稳定产品ID和原有数量去重，按个人比例换算钠，来源manualEstimate，事件保留输入假设。DailyNutritionSummary仅从本App活跃事件快照计算糖/钠，不读取全局健康数据。App/ManualNutritionViews.swift负责呈现，计算在IntakeCore。详情见MANUAL_FOOD.md。

## WidgetKit与系统动作（0.5.0）

Widgets包含独立扩展入口，Shared包含主App与扩展共同编译的前台App Intents和产品选项查询。App/WidgetPublisher只将ID、名称和单位发布到App Group，不迁移私有账本。扩展只读、无HealthKit访问；openAppWhenRun将动作交给主App，QuickIntake在IntakeCore重新验证当前产品、实际数量和单位，随后调用IntakeStore.logUnits，沿用单写入者与已有健康同步队列。过期ID或变化单位拒绝，不用小组件缓存直接计算营养。前台/保存/删除刷新选项；系统调度小组件时间线。详见WIDGETS_SHORTCUTS.md。

0.5.1：CaptureIntakeIntent将系统参数解析变为条件分支工作流；App内CaptureWorkflowView提供原生可操作表单，OpenCaptureWorkflowIntent仅导航到该表单。主界面统一处理菜单与餐食草稿请求，关闭旧弹层后呈现，避免静默遮挡。TextMealRecognition使用可选本机文字模型；IntakeCore/TextMeal独立核查原文引用、数量、单位、重复和营养合理性。AI营养始终为估算，确认后复用MealValidation与同一健康队列。

0.5.1最终产品组件：移除实际XPC失败的WidgetConfigurationIntent与专用查询层；采用StaticConfiguration稳定时间线，App内配置产品数量，由IntakeCore的QuickIntake.widgetSelection验证选择、删除及单位变化，WidgetPublisher只发布所选产品。新kind OpenIntakeFavorite需重加旧组件。

0.5.2：MealReviewState 是 SwiftUI 与核心测试共用的确认状态机；内容值相等时不重置，不以非规范化JSON比较状态。异步结果必须匹配 analysisID，提交在启动Task前占用状态，并对已入账的草稿请求去重。餐食明细兼容新增毫升与每100mL基准，不猜密度。已有文字/人工份量时照片仅作参考。未知条目保留在事件快照，Apple健康只接收有值的小计并保留估算来源。
