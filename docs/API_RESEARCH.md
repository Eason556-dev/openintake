# Apple API 核实与选型

核实日期：2026-10-10。参考 Apple 官方在线文档、WWDC transcript，以及本机 Xcode 27.0 beta（27A5252f）iPhoneOS 27 SDK 的头文件和 Swift interfaces。SDK 可编译性不代表某台 iPhone 已完成权限或运行验证。基础功能最低部署 iOS 17；可选 Foundation Models 运行时要求 iOS 26+ 及模型可用。

## HealthKit

[HealthKit](https://developer.apple.com/documentation/healthkit) 是健康记录中心，写入要求用户授权及 HealthKit entitlement。项目包含 entitlement 和两条用途说明，并在使用前检查 `HKHealthStore.isHealthDataAvailable()`。见 [设置 HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)。

[授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)以数据类型区分读写；`requestAuthorization` 完成不代表全部类型获准。本实现逐类型检查 `authorizationStatus(for:) == .sharingAuthorized`，read 集合为空。不申请广泛健康数据读取。

实际写入 `HKQuantitySample`，每种合法投影类型一个累积型 dietary quantity；37 种质量统一 `HKUnit.gram()`，饮水用 mL，能量用 kcal。完整 SDK 逐项核对为 39 种，见 `HEALTHKIT_NUTRITION_CATALOG.csv`。以下表格列出其中维生素和矿物质子集：

| 领域枚举 | HKQuantityTypeIdentifier 后缀 |
|---|---|
| vitaminA/C/D/E/K | DietaryVitaminA/C/D/E/K |
| vitaminB6/B12 | DietaryVitaminB6/B12 |
| thiamin/riboflavin/niacin | DietaryThiamin/Riboflavin/Niacin |
| folate/biotin/pantothenicAcid | DietaryFolate/Biotin/PantothenicAcid |
| calcium/iron/magnesium/zinc/selenium | DietaryCalcium/Iron/Magnesium/Zinc/Selenium |
| copper/manganese/chromium/molybdenum | DietaryCopper/Manganese/Chromium/Molybdenum |
| iodine/potassium/sodium | DietaryIodine/Potassium/Sodium |

当前枚举与单位适配覆盖全部 39 种 Dietary 类型。识别能力不等于类型覆盖：未知成分、化学净量不明及无原文证据的值保持本地。`DietaryWater` 是 mL、`DietaryEnergyConsumed` 是 kcal，不与质量混用。

[同步标识](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier)和 syncVersion 一同使用；更高版本会替换同标识旧对象。本版本每条不可变事件/营养使用稳定标识和版本 1，重试复用同标识。修改历史采用撤销/重新记录，而非偷偷改旧快照。

[按类型及 predicate 删除](https://developer.apple.com/documentation/healthkit/hkhealthstore/deleteobjects(of:predicate:withcompletion:))用于撤销。SDK `HKHealthStore.h` 明确只能删除本 App 保存的对象；本实现再以唯一事件样本标识限定，不做日期范围批量删除。

## Medications

[Meet the HealthKit Medications API](https://developer.apple.com/videos/play/wwdc2025/321/)介绍读取用户用药与剂量日志；包括 `HKUserAnnotatedMedication`、`HKMedicationDoseEvent` 和对应 queries。该 API 从 iOS 26 引入，带专门授权及药物对象授权行为。

本机 27 SDK 的 `HKMedicationDoseEvent.h` 属性均 readonly，`init`/`new` unavailable，没有公开创建剂量事件的工厂；相关药物对象/查询接口没有公开的药物录入写入流程。因此当前可确认的是官方读取能力，不能据此设计第三方药物写入。项目不申请该读取权限、不使用药物查询，也不将药物剂量转换成 dietary 样本。用户在确认界面明确区分补充剂与药品；软件无法仅凭包装文字自动判断所有药品分类。

## Vision / VisionKit

[DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller)可实时识别文字和机器可读码，必须检查 `isSupported`、`isAvailable` 及相机权限。它不是天然结构化营养表解析器，也不是所有设备都支持。本 MVP 采用 [VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) 拍摄一页或多页；iOS 26+ 优先 [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest)，保留 DocumentObservation.Container 的段落/表格 Codable 结构、每行 boundingBox 与候选 confidence。旧系统或结构化识别失败使用 [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)；较老 iOS 同样有这些接口。

文档扫描在展示前检查 `isSupported`；`NSCameraUsageDescription` 已提供，拒绝相机时保留文字录入。OCR 使用 accurate、自动语言检测和关闭语言纠正，避免为符合语言习惯而更改标签拼写。图像只在内存；规则解析不承诺多栏阅读顺序正确。

条形码识别有 [VNDetectBarcodesRequest](https://developer.apple.com/documentation/vision/vndetectbarcodesrequest)，但代码尚未集成。条形码只能提供标识，必须另接合法数据源才能得到产品营养；不能把条形码本身当含量。

## Foundation Models

[官方生成说明](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)支持端侧语言理解、实体提取和结构化生成，并明确应检查 `SystemLanguageModel.default.availability`。本机 SDK 确认默认模型及 `LanguageModelSession` 从 iOS 26 可用，watchOS unavailable。

当前使用 `@Generable` / `@Guide` 与 `respond(to:generating:)` 输出带精确原文引用的结构化草稿；不再用模型自由文本喂关键词解析器。结构约束不能保证事实正确，所有结果再经过独立 SemanticValidator，AI 无权写入健康。只使用 SystemLanguageModel.default，没有使用 SDK 27 的 Private Cloud Compute / 远程模型能力。

运行时检查 availability、supportedLanguages、supportsLocale；语言推测来自 NaturalLanguage，每行低置信度语言不硬判。支持范围随设备及系统变化，界面展示实际能力清单。参考 [Apple 多语言支持](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) 及 [Apple Intelligence 要求](https://support.apple.com/en-us/121115)。关闭 AI、模型未准备好、语言不支持、上下文超限或生成失败均明确回退本地保守规则；未知值保持未知。

## Shortcuts 与原生 App

Apple 的 [Shortcuts share actions](https://support.apple.com/en-nz/guide/shortcuts/apdaf74d75a5/ios)明确包含 Log Health Sample。可以先在 iPhone 手工做无 App 验证：定义产品字典 → 选择产品 → 输入份数 → Calculate → Log Health Sample。扫描分支可用相机和提取文字动作。但公开说明没有保证当前每个营养子类型在快捷指令 UI 中均可写，必须在设备上确认。

此路径适合验证一次记录，不适合作为本项目长期维护主体：产品版本、稀疏营养数组、完整确认表单、原子事件账本、失败重试和精确撤销需要大量动作及状态管理。这里的结论是工程取舍，**不是声称快捷指令完全无法实现这些能力**。未生成未经验证的 `.shortcut` 二进制，也未声称已在设备执行原型。

[AppIntent](https://developer.apple.com/documentation/appintents/appintent)及 [AppEntity](https://developer.apple.com/documentation/appintents/defining-app-entities-for-your-custom-data-types)提供系统动作和可选择产品。项目使用 `EntityStringQuery` 返回已确认本地产品；`@Parameter` 声明产品和默认份数；`AppShortcutsProvider` 注册入口，见 [App Shortcuts](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents)。

Action Button 通过用户绑定 Shortcuts 调用，不需要伪造专用硬件 API。Intent 当前会打开主 App，原因是完整文件保护、授权 UI 及单进程写入；不是锁屏无交互后台入口。Siri 识别及快捷指令索引需要真机验收。

## watchOS

[watchOS 官方入口](https://developer.apple.com/documentation/watchos-apps)确认支持短交互、App Intents/Siri 和 HealthKit，也有独立生命周期和后台运行约束。iPhone Intent 的存在不代表手表可以独立执行它。当前没有 watch target，未来需要设备间产品同步、独立权限、持久化队列及跨设备幂等设计后再实现。

## 兼容性结论

| 能力 | 本版本条件 | 已验证范围 |
|---|---|---|
| 基本 App / 本地资料库 | iPhone iOS 17+ | Xcode 27 SDK 无签名编译，领域逻辑 macOS 测试 |
| 文档相机 + OCR | iOS 17+，扫描能力及相机授权可用 | API 编译；设备效果待测 |
| HealthKit 营养写入及撤销 | 健康数据可用，相关类型获准 | API 编译；模拟故障测试；真机待测 |
| Siri / Shortcuts / Action Button | 已安装，保存产品；按钮入口要求支持硬件 | Intent 元数据编译；索引及运行待测 |
| 可选端侧模型 | iOS 26+，Apple Intelligence 默认模型 available | API 编译；真实模型提取待测 |
| 药品写入 / Watch 独立操作 | 本版本不支持 | 不提供替代伪实现 |

## 结构化补充剂映射复核

2026-10-10 按官方文档及 Xcode 27 beta SDK 复核多不饱和脂肪与总脂肪：均为累计质量类型。专用 Omega-3/EPA/DHA/姜黄类型不存在；Omega-3 的宽泛映射必须主动同意，鱼油不自动当作总脂肪，草本等效量不写入。27 种核心类型包含新增 PUFA/总脂肪，仍不处理药物。具体规则及官方 API 链接见 [成分映射](INGREDIENT_MAPPING.md)。

完整 SDK 集合复核发现原实现遗漏 10 个质量类型，已扩展到全部 37 种质量类型；能量和饮水单列，不混用单位。原 27 类型是应用子集而非 Apple 完整清单。见 [完整核对](HEALTHKIT_CATALOG_AUDIT.md)。

## 单位专属规则

维生素 D 采用 [NIH ODS 官方说明](https://ods.od.nih.gov/factsheets/VitaminD-HealthProfessional/) 的 1 mcg = 40 IU；其他 IU 不沿用此公式。DFE / RAE 当前保留原单位，不折算为普通 mcg；化学形式/净营养素质量无法确定时需人工核对。
