# 0.3.3 标签识别故障诊断与修复

> 版本说明（2026-10-31）：0.7.0 已移除内置模型与自动餐食营养估算。本文涉及 AI 的内容为历史实现或计划；当前行为见 [轻量记录版本](LIGHTWEIGHT_RECORDING.md)。

验证日期：2026-10-12。版本 0.3.3 / build 6。基于现有 App 增量修复，没有另建识别 App。按用户选择先完成验证，暂缓本版本真机安装。

## 复现与根因

失败输入（公开标签文字，不含个人摄入信息）：

```text
Each tablet contains/Chaque comprimé
contient :
Vitamin/Vitamine C ..
500 mg
(Ascorbic acid, Sodium ascorbate/
acide ascorbique, ascorbate de sodium)
```

修复前对现有核心代码执行只读诊断：目录无法解析共享前缀 `Vitamin/Vitamine C`；规则草稿与验证结果均为空；即使提供正确的 AI `Vitamin C / 500 mg` 草稿，验证器也以“缺少原文名称证据”拒绝。截图中的括号化学来源则可能留下未知成分及无效父引用。问题不只是模型超时，也不是 HealthKit 缺少维生素 C 类型。

| 层 | 修复前原因 | 修复后责任 |
|---|---|---|
| IngredientCatalog / OfflineSemanticProvider | 别名依赖完整词组，共享双语前缀和跨行数值无法稳定关联 | LabelNameEvidence 统一别名和共享前缀语法；保留实际原文引用 |
| SemanticValidator | 要求模型的标准名称在单一原文中连续出现，误拒绝正确标准化结果 | 仅在被引用的证据块内，依据经过审查的唯一标准身份回接原文；不做模糊猜词 |
| 名称与数量关联 | 解析器和验证器使用不同的跨行条件 | LabelEvidenceLink 为两者提供相同的确定性关联规则 |
| 化学来源 | 括号来源被当独立成分；根成分被拒后留下孤立来源 | ChemicalSources 作为无独立剂量的来源元数据，合并英语/法语来源名；忽略脱离主成分的来源行 |
| ProductEditor | 流式回调与最终结果重复采用；空结果可能保留上一轮成分 | LabelRecognitionSession 统一状态；重复最终响应不再采用，旧任务不能覆盖新扫描，空结果清除旧识别成分 |
| DocumentOCR | 文档段落和表格可能重复输出同一物理文字 | OCREvidenceMerge 只合并同页同位置同文字，保留证据 ID 和表格信息 |

代码入口：`Sources/IntakeCore/LabelNameEvidence.swift`、`LabelEvidenceLink.swift`、`ChemicalSources.swift`、`LabelRecognitionSession.swift`、`OCREvidenceMerge.swift`；App 适配为 `App/DocumentOCR.swift`、`OptionalAI.swift`、`ProductEditor.swift`。旧 LabelParser / SupplementParser 为兼容仍保留，扫描界面不会同时再运行旧解析器。

## 完整调用链与边界

Vision → OCRDocument（文字、位置、置信度、表格、原始结构）→ 规则草稿 + 可选 Apple Foundation Models 结构化草稿 → SemanticValidator → SemanticReconciliation → LabelRecognitionSession → 用户确认保存 Product → 用户记录实际数量 → HealthPlan → 现有 HealthWriter。

AI 原始 JSON、模型输入批次、OCR 引用和验证结果可在本机详情检查。结构化输出仍必须通过名称、数值、单位、基准、关系和映射检查，不能直接写 HealthKit。规则路径复用同一证据规则，不因为模型失败就伪造结果。

- 手动文字：只有明确的单一名称紧邻单一纯数量行才允许跨行连接；中间出现另一成分时阻止。
- 相机文字：跨行必须有布局证据，或有唯一表格关联；缺位置、跨列、歧义或多个数量候选时不猜测。
- 双语共享前缀是通用语法，覆盖其他维生素；不是针对 Vitamin C 硬编码数值。
- 化学来源无独立剂量字段。标示的 Vitamin C 净含量可以映射；单独 Sodium ascorbate 化合物总量不能冒充维生素 C 或钠含量。
- 未知量保持未知；扫描和保存产品不生成摄入事件。包含/等效关系、推荐服用量和实际摄入的既有边界保持不变。

本机实际模型曾拒绝旧提示词。已将内置提示改为中性的标签文字结构化提取，保持 Apple 默认防护，并重新实际运行通过。没有关闭防护、改用宽松字符串绕过结构化生成，也没有仅靠修改提示词完成本次修复。模型仍可能拒绝或遗漏，确定性降级与人工核对继续必要。[Apple 安全说明](https://developer.apple.com/documentation/FoundationModels/improving-the-safety-of-generative-model-output)

## Before / After

| 项目 | 修复前 | 修复后验证结果 |
|---|---|---|
| 主成分 | Vitamin C 被拒绝，括号来源成为未知行 | 一个维生素 C，500 mg，基准每片 |
| 化学来源 | 孤立父引用 / 含量未知错误 | Ascorbic acid 与 Sodium ascorbate 两个来源形式，英法去重，无额外摄入量 |
| HealthKit 计划 | 无可写成分 | 一个 dietaryVitaminC；1 片 500 mg = 0.5 g，2 片 = 1 g |
| 保存和重开 | 缺少本例端到端覆盖 | 模拟器保存、普通重启、重开后 500 mg 和两个来源保留；没有创建摄入 |

维生素 C 使用质量单位，准确类型为 [dietaryVitaminC](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietaryvitaminc)。本次验证生成写入计划，未向个人 HealthKit 写入虚构测试摄入。

## 验证结果

核心 `swift test`：99 项、0 失败。新文件 `Tests/IntakeCoreTests/LabelRecognitionRegressionTests.swift` 包含 T01–T15 与 OCR 物理证据合并测试：

| 编号 | 覆盖 |
|---|---|
| T01–T03 | 单语、共享双语前缀及其他维生素、跨行数值与歧义隔离 |
| T04–T05 | 完整原始失败文字、双语化学来源及引用 |
| T06–T08 | D3 专属 IU 换算、多成分、括号来源及不能映射的化合物总量 |
| T09–T10 | 已知名称未知数量、未知成分有数量但仅本机保存 |
| T11–T12 | 正确标准化 AI 输出通过、虚构名称拒绝、孤立来源不生成成分 |
| T13–T14 | 重复响应、重新解析、取消和旧任务结果隔离、空结果清除旧成分 |
| T15 | 原子保存/读取完整结构化资料，摄入事件仍为空 |

其他实际验证：

- iOS 无签名、iOS 签名、模拟器构建全部 `BUILD SUCCEEDED`，使用本机 Xcode beta / SDK 27.0。
- macOS 真实 Apple 模型：Jamieson 六项 AI 成分均通过验证，约 10.1 秒；本例约 3.8 秒，AI 原始两行经验证成为一个 Vitamin C 500 mg 和两个来源。均不保存摄入。
- 真实 Vision API 的 15 个合成图角度案例：13 个准确，2 个已知 OCR 错字被安全阻止；不是 100% 识别准确率。本例三个角度均正确。
- 用户提供的 App 截图：仅取标签文字区域，实际经过生产 Vision → 真实 Apple 模型 → 验证 → 产品与写入计划，得到一个 500 mg Vitamin C 与两个来源。截图没有加入仓库。
- QA 模拟器实际确认页面自动填好名称、每片、500 mg、准确映射和两个来源；保存后普通重启、重新打开仍保留，没有新增摄入事件。无签名模拟器提示缺 HealthKit entitlement，未将此环境冒充真实健康写入成功。

## 尚需真机验收 / 技术限制

以上 Mac 耗时不代表 iPhone 性能；绘制图和 App 截图不代表反光、曲面、模糊的真实瓶身照片。0.3.3 尚未安装到 iPhone，按用户要求稍后安装；现有真机版本不能用于判断本次修复结果。

未来验收：扫描这瓶维生素 C，确认每片 500 mg、两个来源、无多余钠/来源剂量；保存重开；仅在真实服用后记录实际片数，核对 Apple 健康维生素 C 数值、时间与本 App 来源，再验收撤销。另复扫英法 Jamieson，确保父子量和提取物当量仍正确。

模型非确定性、未覆盖的语言/化学形式、复杂版面仍可导致待确认项；不能承诺任意包装完全自动正确。原文缺失或证据不足仍需人工修正。本次没有增加强制网络、账号、API 服务或大型模型。
