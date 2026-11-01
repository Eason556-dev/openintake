# 成分映射与确认

扫描只生成草稿。所有成分以名称、可空含量、原始单位、来源及层级保存在本地；一次确认后才成为产品。实际摄入另生成事件。

| 类别 | 默认行为 | 示例 |
|---|---|---|
| 准确对应 | 自动预填，整体确认后可写入 | Vitamin D 25 mcg → 维生素 D |
| 较宽泛对应 | 说明依据与限制，默认关闭，用户主动同意后写入 | Omega-3 → 多不饱和脂肪 |
| 无准确类型 | 完整保留本地，不请求该成分写入 | 鱼油、EPA、DHA、姜黄、草本等效量、CFU |

Apple 没有专用 Omega-3、EPA、DHA 或姜黄类型。Omega-3 属于多不饱和脂肪，但已知 Omega-3 含量不能视为产品全部多不饱和脂肪的测定值，因此必须显示限制并单独同意。鱼油质量也不能自动等同总脂肪。

## Jamieson 每粒案例

| 成分 | 1 粒 | 3 粒 | 关系 / HealthKit |
|---|---:|---:|---|
| 鱼油 | 834 mg | 2,502 mg | 本地父成分 |
| Omega-3 | 500 mg | 1,500 mg | 包含于鱼油；可选写入 PUFA |
| EPA | 300 mg | 900 mg | 包含于 Omega-3；本地 |
| DHA | 200 mg | 600 mg | 包含于 Omega-3；本地 |
| 姜黄提取物 | 20 mg | 60 mg | 本地；50:1 |
| 干燥草本等效量 | 1,000 mg | 3,000 mg | 等效于提取物，非额外摄入 |

开启宽泛映射时，Apple 健康仅接收 0.5 g / 1.5 g 多不饱和脂肪。关闭时，这一案例全部仅本地。不能把父成分、子成分和等效量相加为摄入总质量。

质量转换为 g：mg ÷ 1,000，mcg ÷ 1,000,000。实际份数 = 服用粒数 ÷ 每份粒数。只使用明确标签值；不从比例推算缺失数量，只对维生素 D 使用 40 IU = 1 mcg 专属规则，其他 IU、CFU、RAE、DFE 保留本地。草本等效量以标签明确声明存储。

## Apple API 核实（2026-10-10）

[HKQuantityTypeIdentifier.dietaryFatPolyunsaturated](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietaryfatpolyunsaturated) 是累计质量类型，支持质量单位；应用统一使用 HKUnit.gram()。Xcode 27 beta SDK 的 HKTypeIdentifiers.h 与官方文档一致。没有专用 Omega-3、EPA、DHA 或姜黄字段，不创建自定义类型冒充官方营养项。

[requestAuthorization(toShare:read:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:)) 只请求实际投影类型的写权限，read 为空；完成请求后仍逐类型检查 sharingAuthorized。纯本地事件无需授权。药物不进入此写入流程。

事件先原子保存，再调用 HealthKit；失败保持 pending。每个新事件冻结写入清单，使用稳定 syncIdentifier 重试。系统 [HKMetadataKeySyncIdentifier](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier) 支持同步去重；mock 可验证调用契约，实际系统数据库行为需真机验收。

## 识别边界

当前扫描流程优先端侧 AI 结构化语义解析，并经过独立原文验证；不可用时明确使用保守规则。规则包含多语言别名，但不是完整语义模型。未知单位保留原文。OCR 跨行、多列、反光和复杂成分仍可能误识别；关系及每份粒数均需核对。手工更改名称/含量/单位标为 manual，AI 输出标为 aiEstimate。成分详情允许修正关系，保存时验证环路、重复 ID、数量及父子质量约束。

## 避免“未确认”被误解为“不支持”

首页提示待确认的 Omega-3 宽泛映射，并提供直接编辑入口。确认页把映射选择放在成分列表之前，显示每份实际写入预览。localOnly 事件如果当时有未确认宽泛映射，会明确显示“当时未启用宽泛映射”。修改产品不补写旧事件；纠错须撤销后重新记录。

总脂肪及多不饱和脂肪是 Apple 官方允许分别记录的层级类别，不合并相加。同一类型的父子总量只投递一次。鱼油不能仅凭名称自动视为总脂肪；测试中总脂肪样本要求标签明确写出总脂肪。
