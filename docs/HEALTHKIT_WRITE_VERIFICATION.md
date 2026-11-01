# HealthKit 接入与真实写入验证（0.3.1）

## 已核实的官方流程

HealthKit capability和安装签名权限只允许App申请访问，不自动显示授权页。App必须调用requestAuthorization(toShare:read:)指定具体类型，系统才处理相应权限。授权按类型区分；请求回调成功不代表用户全部允许，保存前需检查每个类型的authorizationStatus(for:)。

本App只申请营养写入：read为空，不要求读取其他来源健康数据。首次前台UI准备好后请求全部39种已适配营养类型，由用户在官方页选择；不在App.init阻塞启动。完成一次请求后不反复自动弹窗；仍可在营养写入权限页检查及重试。系统已记住的选择可能不会再弹，不能把弹窗次数作为是否接入的判断标准。不同意授权仍可保存本地产品及摄入。

官方依据：

- [Setting up HealthKit](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)
- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [HKAuthorizationStatus](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus)

## 原问题

旧版只在实际记录且写入清单非空时申请类型。饮水有明确water类型，所以出现Water单项授权；未确认、无支持类型或未启用Omega-3宽泛映射的补充剂没有写入清单。仅看到本地记录不能证明营养样本保存。截图中Water开关关闭也不能证明已授权。

## 当前写入闭环

1. 用户记录实际摄入，先持久化pending事件与不可变写入清单。
2. 检查所有涉及类型的写入许可；拒绝则保留pending，不写、不标成功。
3. 创建HKQuantitySample，使用对应g/mL/kcal单位、实际摄入时间和稳定syncIdentifier/version，调用HKHealthStore.save。
4. 保存成功后，按“当前App来源 + 本次稳定同步ID”查询每个对应类型；校验项目数量、数值、时间及来源。
5. 核验通过才记录healthVerifiedAt并标记同步完成；核验失败保留待同步，重试使用同一同步ID。
6. 撤销先持久化deletionPending，再删除本App对应样本，查询确认已无该样本后标记完成。

Apple说明未获读取权限时查询仍可返回App自己保存的样本；本查询同时限定本App来源与本事件同步ID，不请求其他来源读权限。查询核验是当前时刻的证据；用户之后从Apple健康手动删除样本不会自动回推本地状态。

旧版synced记录没有healthVerifiedAt，界面明确显示“旧版未做样本核验”，不追认为已验证。授权、保存产品和核验现有事件都不能凭空创建实际摄入。

## 本次实证范围

2026-10-11：检查已签名App和embedded.mobileprovision，HealthKit entitlement均为true，健康使用说明存在。0.3.1/build4无签名及签名构建成功；77项核心测试通过。已覆盖安装至连接的iPhone并成功启动，实际观察到Apple官方Health Access页面包含多种维生素、脂肪及矿物质，区别于之前的Water单项页面。授权选择及Allow由用户操作，未代替授权。

这证明正式系统授权路径与真机签名接入成立；不等于已验证用户实际营养写入。下一步是用户允许对应项目、记录真实摄入，并在同步页观察“已写入并核验”，同时在Apple健康核对来源、数量和时间，再验收撤销。没有向用户手机注入虚构健康样本。

## 0.4.1 糖／钠专项检查

代码确认饮料与食盐事件沿同一持久化待同步队列进入 HealthWriter，分别使用 dietarySugar 和 dietarySodium 的质量类型，以 g 写入；例如每100mL糖10g、钠20mg，实际330mL为糖33g和钠0.066g（66mg）。写入前检查两项授权，保存后逐项查询本App样本并校验；缺样本、错单位或授权拒绝均不能标为成功。

补足首页可见性：逐项实际授权状态、当天相关事件核验状态、糖／钠专用授权入口，以及同步中心重试入口。关闭权限后App不能自行重新开启；已处理过的类型也不能保证再次显示系统窗口。当前SDK HKHealthStore.h的requestAuthorization注释明确说明，全部请求类型已有用户选择时会直接调用完成回调而不再提示。参见 [Apple 授权状态](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus)、[糖类型](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietarysugar)、[钠类型](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietarysodium)。

116项核心测试与无签名构建通过，只证明计算、队列行为和可编译性。本版未部署到真机；尚不能断言用户当前糖／钠权限已允许或实际健康样本已保存。
