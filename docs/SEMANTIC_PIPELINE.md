# 多语言标签语义管道（0.2.0）

> 版本说明（2026-10-31）：0.7.0 已移除内置模型与自动餐食营养估算。本文涉及 AI 的内容为历史实现或计划；当前行为见 [轻量记录版本](LIGHTWEIGHT_RECORDING.md)。

## 数据边界

`Vision → OCRDocument → SemanticParsingProvider → SemanticProposal → SemanticValidator → SemanticReconciliation（独立原文补全）→ ValidatedLabel → 用户确认 Product → 用户实际摄入 IntakeEvent → HealthPlan → HealthWriter`。

扫描和保存产品不创建摄入事件。推荐服用说明保留在 recommendations，永不直接参与计算。AI 提供者不能调用 HealthKit，也不能自行设 confirmedAt。IntakeEvent 保持产品版本及最终写入清单快照，后续产品修改不改变历史重试/撤销。

## OCR 与语言

iOS 26+ 使用 RecognizeDocumentsRequest（[官方 API](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)、[表格识别](https://developer.apple.com/documentation/vision/recognize-tables-within-a-document)）。保存行文本、页码、归一化坐标、真实候选置信度、表格行列及完整 Container JSON（多页为换行分隔 JSON）。跨多行的表格单元不冒充唯一行关联。旧系统或失败回退 VNRecognizeTextRequest；手工粘贴不伪造坐标或置信度。照片仅在内存。

运行时读取 supportedRecognitionLanguages；AI 另行读取 SystemLanguageModel.default.supportedLanguages / supportsLocale。NaturalLanguage 只提供输入语言线索，不是语言支持证明。原文语言、AI 能力、标准 ID、HealthKit 标识和界面名称互相独立。当前主体界面为中文，成分名称可选择中文或 English；这不是完整界面七语言本地化。

别名词典含英、法、中、日、韩、西、德常见名称；Vitamin B1 / Thiamin / 硫胺素统一为 thiamin，Fish Oil / Huile de poisson 统一为 fishOil。词典覆盖不代表任意这些语言包装均正确，更不代表设备模型一定支持这些语言。化学形式保留，不与母营养素盲目等同。

## 可选 AI

AppleSemanticProvider 使用本机 SystemLanguageModel、@Generable/@Guide 与结构化生成。原文是数据，提示明确禁止遵从包装中的指令。输出包括名称、标准 ID 建议、原文证据 ID 与精确引用、计量基准、推荐量、含量/单位、化学形式、包含关系、浓度、提取比例和等效关系。

用户可以关闭 AI。模型不可用、语言不支持、输入过长或异常时，界面明确回退 OfflineSemanticProvider。该提供者是有限别名和规则解析器，不能称作 AI，也不会伪造未识别的语义。未知名称可保留本地；未可靠提取的内容仍保留原文。SemanticParsingProvider 是未来用户自选 BYOK / 自部署提供者的边界，本版本没有网络提供者。

## 确定性验证

- 验证证据 ID 唯一且存在、名称引用逐字存在。完整含量引用与原文对应；模型只给纯数字或遗漏数字字段时，仅从该名称对应的唯一印刷数值补全单位与原始量；与模型明确数值冲突时拒绝，不修复 OCR 字母错字。
- 同一行按名称边界找其后的数值；跨行只接受明确同表格行或紧邻同列且无插入成分。拒绝跨页/列、服用说明、连接词、低 OCR 置信度及不等号估值。不自动将 O 改为 0。
- 解析基准 Each softgel / 每粒、已知粒数 Per Serving、Per 100 g / mL；每份已知粒数归一为每粒。日语每日基准只有明确片数才允许归一；没有片数不猜。多个不同基准/列同时出现时暂不自动选择，进入待确认。
- 标准身份 + 化学形式 + 关系去重，换算后数量一致才合并；冲突保留证据并阻止自动映射。双语共用一个数量的别名也不产生两个剂量。
- 校验已知包含链、循环、子成分质量不超过父总量。可疑关系隔离并标记待确认，原始 AI 图仍完整保存在 SemanticProposal。其他成分图关系需要人工核对，不能仅凭 AI 建议抑制真实摄入。
- mg/g/mcg 只在质量内换算，L/mL 在体积内换算，kJ/kcal 在能量内换算。只有维生素 D 采用 40 IU = 1 mcg。其他 IU、DFE、RAE、CFU 保留原单位，不用通用公式。
- 元素名嵌在化合物名中不能证明元素净量；化学形式未确认时保持本地。缺失值为 nil，不填零。

AI 结构草稿可能遗漏项或给错引用。SemanticReconciliation 使用已独立验证的规则草稿补齐遗漏，或替换未通过验证的字段；规则来源保留为 labelOCR，原始 AI 和规则草稿分别保存。两个已验证数量不同则保持待确认，绝不悄悄选一个。已知包含链的缺失关系也可以从独立规则补全。

待确认的项目显示原因，不进入写入清单。用户对照原文修正数量/单位/关系后，可在详情中明确确认该成分。一次保存确认正常结果；不要求逐项选择 HealthKit 技术名称。

## Jamieson 回归预期

每粒：鱼油 834 mg → Omega-3 500 mg → EPA 300 mg + DHA 200 mg；姜黄提取物 20 mg，50:1，干草本等效 1,000 mg。成人每日两粒仅是推荐说明。英法重复描述合并。

关闭宽泛映射：所有成分本地保存。主动同意后：1 粒写 PUFA 0.5 g，2 粒写 1 g，3 粒写 1.5 g；EPA/DHA 不重复求和。鱼油、姜黄及干草本等效量没有专用营养类型，不强行写入。药品仍完全分离。

## 验证范围与限制

核心 XCTest 用合成文本和 OCR 坐标验证，不代表端侧模型准确率。`scripts/test_vision.sh` 在 macOS 26+ 用生产 DocumentOCR 识别绘制的中/英/英法/混合标签及 ±6° 旋转，属于真实 Vision 的合成图集成测试，不是 iPhone 相机或弯曲瓶身照片测试。`--semantic-pipeline-audit` 可在 Debug 真机运行本机模型的合成标签 smoke test；不保存产品，不调用 HealthKit。

`scripts/test_semantic.sh` 可在 macOS 26+ 使用生产 AppleSemanticProvider 和验证/补全过程进行真实本机模型合成标签测试；不可用会 SKIP，解析/验证失败返回非零。模型拒绝属于可观察的限制；不改变默认 guardrails，也不使用云模型绕过。

真实模型生成可能遗漏或拒绝有效信息；原文验证能限制错误写入，但不能证明识别完整性。多基准复杂表、模糊/反光/曲面、未收录别名和特殊营养形态仍需用户核对。健康授权、真实样本写入与撤销需在用户手机验收。
