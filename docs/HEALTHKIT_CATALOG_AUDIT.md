# Apple 营养类型完整核对

2026-10-10，以 Apple 官方 Nutrition Type Identifiers 文档及本机 Xcode 27 beta / iOS 27.0 SDK 的 HKTypeIdentifiers.h 逐项核对。SDK 清单包含 39 种 Dietary quantity 类型。当前可编译 SDK 版本与用户 iPhone 的 iOS 27.2 运行时不同，不能仅凭 SDK 把后者宣称为已实测。本次随后已在用户 iPhone Air 的 iOS 27.2 运行时验证全部 39 项类型存在、单位兼容，并构造 0.5 g PUFA 样本但不保存；见 VALIDATION.md。

完整可审查清单：[39 项 CSV](HEALTHKIT_NUTRITION_CATALOG.csv)。没有 Omega-3、EPA、DHA、鱼油、姜黄或自定义任意成分字段。App 当前覆盖全部 39 个 Dietary 类型：37 个质量类型，加上独立量纲的膳食能量（kcal）与饮水（mL）。不存在把毫克输入能量或体积类型的兜底映射。

| 分组 | Apple 公开类型 |
|---|---|
| 宏量及脂肪（10） | 能量、碳水化合物、纤维、糖、蛋白质、总脂肪、饱和脂肪、单不饱和脂肪、多不饱和脂肪、胆固醇 |
| 维生素（13） | A、C、D、E、K、B1/硫胺素、B2/核黄素、B3/烟酸、B5/泛酸、B6、B12、叶酸、生物素 |
| 矿物质（14） | 钙、氯化物、铬、铜、碘、铁、镁、锰、钼、磷、钾、硒、钠、锌 |
| 其他（2） | 咖啡因、饮水 |

[Apple 官方清单](https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers)也说明总脂肪与脂肪子类别可以分别记录；这是分组表达，不能将父项与子项再次相加。Omega-3 已知质量可以经用户同意作为已知多不饱和脂肪贡献量记录，但不能声称得到了全部 PUFA 测定值。

## 重现 SDK 检查

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  python3 scripts/audit_healthkit_catalog.py --output docs/HEALTHKIT_NUTRITION_CATALOG.csv
```

脚本从 SDK 提取完整 Dietary 清单，与 IntakeCore 的所有质量类型比较集合相等、无遗漏/多余项，并验证 g / Cumulative 单位契约。CI 同样执行此检查；SDK 增加营养字段会使检查失败，而不会静默遗漏。

## 系统运行时检查

App 首页 → Apple 健康营养类型完整清单：显示实际系统版本，逐项用 HKObjectType.quantityType 构造类型，并用 is(compatibleWith:) 核对 g、kcal、mL 兼容性。这个页面不会读取任何个人健康数据、请求权限或写入摄入。可以直接在 iOS 27.2 手机上截图查看。

开发者启动参数 `--healthkit-catalog-audit` 输出相同 39 项检查及 0.5 g PUFA 样本构造结果（不保存样本）。这能验证类型及单位，但不能替代真实用户授权、写入后的健康 App 核对或撤销验收。完整营养清单比截图其他无关健康类别更直接回答营养字段是否遗漏；不把心率、运动、症状等类别用来存储补充剂剂量。

## 本次修正与测试

原 App 只列出 27 种质量类型，遗漏 10 个质量类型：咖啡因、碳水化合物、氯化物、胆固醇、单不饱和脂肪、饱和脂肪、膳食纤维、磷、蛋白质、糖。已补齐。这个漏项不是 Jamieson 案例零写入的原因；原因是该产品没有准确专用类型，且 Omega-3 的宽泛映射尚未确认。旧提示错误地把“尚未确认”写成“没有可写入成分”，现已区分。

31 项 XCTest 通过：新增全部 37 质量类型的人名映射、遗漏字段扫描、总脂肪/PUFA 独立类别、未确认提示及历史快照不回写测试；原 Jamieson 1/2/3 粒、单位转换、重试、撤销及持久化测试保持通过。
