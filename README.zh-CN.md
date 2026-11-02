<h1 align="center">
  <img src="docs/images/showcase/app-icon.png" width="44" height="44" alt="OpenIntake icon" align="middle"> OpenIntake
</h1>

[English](README.md) · [简体中文](README.zh-CN.md) · [下载 Releases](https://github.com/Eason556-dev/openintake/releases)

**轻量的 iPhone 与 Apple Watch 摄入记录工具，以 Apple Health 为健康数据中心。**

产品资料填写一次，日常只记录实际摄入数量；有明确依据、受支持的营养值通过 HealthKit 写入并核验。无需账号、开发者服务器、付费 API 或内置 AI。

**Local-first · Privacy-first · Zero Server · Zero Account · Open Source**

当前源码预览版：**0.8.0 / build 20**。[更新说明](docs/releases/v0.8.0.md) · MIT 开源许可。

## 我们的愿景

Apple Watch 和 iPhone 已能自动采集许多运动及生理数据，食品、饮料和补充剂摄入却仍需要方便的记录入口。OpenIntake 专注补齐这一步：本地产品复用、明确的实际数量、确定性计算，以及能够核验的 Apple Health 同步。

Apple Health 继续负责受支持健康数据的集中保存。OpenIntake 不自行开发健康评分、不推荐服用剂量，也不声称能预测所有食品的营养组成。用户决定记录什么，未知值始终保持未知。

## 在 iPhone 与 Apple Watch 上

<p align="center">
  <img src="docs/images/showcase/nutrition-iphone.png" width="330" alt="iPhone 实机营养首页：能量、蛋白质、碳水、脂肪与营养进度" align="middle">
  &nbsp;&nbsp;
  <img src="docs/images/showcase/watch-complications.png" width="210" alt="Apple Watch 实机表盘：补水、能量、蛋白质、糖和钠组件" align="middle">
</p>

<p align="center"><strong>一天的摄入，一眼看清。</strong><br>在 iPhone 核对营养，在 Apple Watch 抬腕查看。数值、目标与限量清晰呈现。</p>

### 从最顺手的入口开始

<p align="center">
  <img src="docs/images/showcase/water-widget.png" width="270" alt="iPhone 小组件选择页中的 OpenIntake 快速饮水组件，可记录 150 或 250 毫升" align="middle">
  &nbsp;&nbsp;
  <img src="docs/images/showcase/quick-log-shortcut.png" width="270" alt="快捷记录菜单：饮水、补充剂、食品饮料与餐食文字入口" align="middle">
</p>

<p align="center"><strong>轻点小组件，或运行快捷指令。</strong><br>饮水、补充剂、食品与餐食，通过统一入口记录实际摄入。</p>

<p align="center">
  <img src="docs/images/showcase/action-button.jpg" width="360" alt="iPhone 操作按钮的长按运行快捷指令提示，显示 OpenIntake 图标">
</p>

<p align="center">把快捷指令绑定到支持的 iPhone 操作按钮，随手开始记录。</p>

<details>
<summary>关于这些图片与 Markdown 排版</summary>

图片由维护者提供，展示实机界面在截图时的状态；设备边框来自原始素材。位置、拍摄设备及其他隐私元数据已移除，界面内容保持原样。

普通图片可写为 `![说明](docs/images/showcase/nutrition-iphone.jpg)`。标题旁图标和并排图片使用 GitHub 支持的 HTML `<img>`，通过 `width` 控制展示大小；所有图片都使用仓库内相对路径，Fork 或下载源码后也能找到。

</details>

## 已有功能

| 类别 | 当前能力 |
| --- | --- |
| 产品资料 | 保存并复用补充剂、食品及饮料标签，填写每份定义、单位和已知含量。编辑模板不重写历史事件快照。 |
| 基础 OCR | 文档相机与 Apple Vision 辅助抄录补充剂标签，本地规则辅助解析成分、数值和关系；需要用户逐项核对，不调用模型。 |
| 餐食记录 | 离线匹配食品参考资料，或粘贴明确的营养汇总；支持单独记录能量、每 100 g/mL 换算、手动调整总量及常用餐食。未知值保持未知，旧餐食可补全字段后重新同步。 |
| 补水 | 常用或自定义毫升数、当日圆环、个人目标及可选本机提醒。 |
| 营养 | 按标签记录糖、钠、能量及宏量/微量营养素，适配 39 种 HealthKit 饮食营养类型。普通食盐的近似钠换算明确标为人工估算。 |
| 成分关系 | 不支持的成分保留本地；提取物当量与已包含子成分不重复累计。Omega-3 → 多不饱和脂肪的宽泛映射需要明确同意。 |
| 健康同步 | 事件先持久化，再检查逐类型写入权限、保存并核验 HealthKit 样本；失败保留重试。本机统计和授权完成不代表同步成功。 |
| 记录管理 | 查看摄入、来源和状态；左滑撤销，误撤销可恢复。稳定事件 ID 和冻结写入清单保护重试与历史。 |
| Apple Watch | 显示当日数值及目标，记录饮水或 iPhone 已配置产品。自动传输使用稳定请求 ID，并由 iPhone 统一写入健康；新产品仍在 iPhone 设置。 |
| 系统入口 | iPhone 小组件、Watch 表盘组件、App Intents、Siri/快捷指令和操作按钮共用原有记录路径。后台传输受系统调度与连接影响。 |
| 中英文 | 可跟随系统，或在设置 → 语言中指定。标准化成分名称跟随 App 语言；用户名称及包装证据保持原文。 |
| 可选外部工具 | 分享通用核对提示词给自己选择的工具，如 ChatGPT、Claude；不自动发送资料、不接入提供方 SDK、账号或 API Key。粘贴餐食营养代码块并核对；模板中的零占位需确认或设为未知。 |

**扫描或保存产品不代表摄入。** 药品剂量不映射为营养，未知值不填零。餐食照片只在草稿页临时辅助核对，不用于营养预测。

## 从 Release 下载 Xcode 源码

1. 打开仓库的 [Releases](https://github.com/Eason556-dev/openintake/releases)，选择需要的版本。
2. 在 **Assets** 下载本版 `OpenIntake-0.8.0-source.zip` 及对应 `.sha256` 文件。GitHub 自动生成的 **Source code (zip)** 也能下载；项目命名的资产额外包含源码清单，并经过打包检查。
3. 可在下载目录打开终端验证：
   ```sh
   shasum -a 256 -c OpenIntake-0.8.0-source.zip.sha256
   ```
4. 双击 ZIP 解压，进入文件夹，打开 **OpenIntake.xcodeproj**。
5. 按[中文构建与真机安装教程](docs/BUILD.zh-CN.md)配置自己的签名并运行。

下载内容是**未签名开发源码**，不是 IPA 或 App Store 安装包。每位用户需使用自己的 Apple 账号、签名团队、唯一标识符与设备授权；不要安装其他人的签名描述文件。

## 自行构建的最短路径

需要满足所用 Xcode 要求的 Mac、含 iOS/watchOS SDK 的 Xcode，以及用于仓库脚本的 Python 3。本版使用 **Xcode 27.2（27B52）** 验证。部署目标为 iOS 17、watchOS 10，新系统功能有可用性判断；本版未认证旧 Xcode。见 [Apple 当前系统要求](https://developer.apple.com/xcode/system-requirements/)。

1. 将 `Config/Local.example.xcconfig` 复制为 **Config/Local.xcconfig**。已有本地文件时请编辑，不要覆盖。
2. 把示例 Bundle 前缀和 App Group 改成自己的唯一值。四个目标与 Watch 配套引用从同一前缀派生。
3. Xcode → Settings → Accounts 添加自己的 Apple 账号；**四个目标**选择相同 Team、自动签名并配置相同 App Group。iPhone 目标保留 HealthKit。
4. 连接并信任 iPhone，开启 Developer Mode；选择 **OpenIntake** scheme 和 Ready 的 iPhone，按 **⌘R**。
5. 在 App 中允许需要的营养写入类型。先保存产品，再记录实际摄入，核对同步状态及 Apple Health 中的样本。
6. Watch 与该 iPhone 配对；按 Xcode 要求启用开发者模式，选择 **OpenIntakeWatch** scheme 及 Ready 的 Watch，按 **⌘R**。

完整签名需要支持 **HealthKit 与 App Groups** 的 Team/描述文件。能力取决于 Apple 会员资格；不能保证免费 Personal Team 支持这套完整目标。如果 Xcode 报能力不支持，请使用符合条件的团队或先在模拟器查看 UI，不要删除 HealthKit 后宣称同步正常。见 [Apple 官方能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios)。

详细的四个标识符、模拟器、真机操作、授权、故障排查及验收步骤见 [BUILD.zh-CN.md](docs/BUILD.zh-CN.md)。

## 不使用 AI 记录餐食

输入 `米饭200克，牛肉150克`，选择实际品种和生熟状态，核对离线参考值；也可以直接粘贴明确的本餐营养汇总：

```text
Meal: Example lunch
Dietary Energy: 650 kcal
Protein: 32 g
Carbohydrates: 70 g
Total Fat: 20 g
Sodium: 900 mg
```

点击“整理文字餐食”，核对自动填写的字段，可修改总量；确认后通过同一个 HealthKit 队列写入。支持单独记录能量，无需编造食物重量。修改或补全旧餐食保留原时间与事件 ID。

- 未知营养留空；仅包含未知值的餐食保留在本机。
- 外部完整模板中的零占位需确认实际为零，或一键设为未知。
- 不明确的份量、单位冲突、重复提交及未整理的新文字会给出阻止原因，不会直接绕过校验。

[餐食与仪表盘修复说明](docs/DASHBOARD_NUTRIENT_REPAIR.md) · [离线参考资料与限制](docs/OFFLINE_NUTRITION_REDESIGN.md)

## 隐私与数据边界

资料保存在设备和用户授权的 Apple Health 中。WatchConnectivity 与 App Groups 用于 Apple 设备及扩展通信，无需开发者服务器。没有统计跟踪、广告或强制模型 SDK，提醒是本机通知。

保留原始标签及来源供检查。历史 AI 估算保留来源以兼容旧数据，当前功能不会调用模型。已知支持值统一走 outbox；本地成分和本地餐食有明确状态。

源码发布排除个人 `Config/Local.xcconfig`、Apple ID、签名证书/描述文件、API 密钥、构建产物和个人健康导出。详见[隐私设计](docs/PRIVACY.md)与[安全说明](SECURITY.md)。

## 测试与源码打包

```sh
swift test
python3 scripts/check_public_files.py
python3 scripts/check_localization.py
python3 scripts/generate_project.py
xcodebuild -project OpenIntake.xcodeproj -scheme OpenIntake \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/OpenIntake-build \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/package_source.py --version 0.8.0
```

如果终端选中了错误的开发者工具，可给命令添加 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。无签名构建无需个人签名；安装设备和真实健康写入需要另行验收。

本版 219 项核心测试通过，覆盖手动餐食、全未知本地记录、冻结快照、权限、失败/重试、撤销/恢复与 Watch 防重。见[餐食修复及验证](docs/MEAL_MANUAL_RECORDING.md)。模拟适配器与模拟器截图不能证明真机同步。

源码 ZIP 包含逐文件 SHA-256 的 `SOURCE_MANIFEST.json`。`v*` 标签触发检查、构建、源码打包及预发布流程。维护者操作见[GitHub 发布说明](docs/PUBLISHING.md)。

## 结构与贡献

```text
App/                     iPhone UI 与 Apple 系统适配
WatchApp/                Watch UI 与请求队列
Widgets/  WatchWidgets/  iPhone 小组件与表盘组件
Shared/                  本地化与跨端模型
Sources/IntakeCore/       规则、计算、校验、持久化及同步
Tests/                   合成回归样例与测试
Config/                  公开默认值与忽略的个人配置
scripts/                 工程生成、检查与源码打包
docs/                    构建教程、设计、截图和版本说明
```

欢迎按 [MIT](LICENSE) 协议 Fork 和贡献，见 [CONTRIBUTING.md](CONTRIBUTING.md)。新摄入类型必须经过共享 HealthKit outbox，保留权限、样本核验、重试、撤销和防重测试；不提交个人健康数据或签名凭据。

当前限制：离线食品资料来自历史 USDA SR Legacy，中文别名覆盖有限；没有完整品牌条码商品库、自动营养预测、用药管理或通用 IPA。OCR 与后台同步仍需真机验收。项目为开发预览版，不提供医学建议。

### 离线餐食资料与营养概览

餐食记录新增英中文规则解析、内置 USDA SR Legacy 7,793 项食品资料、食物及可靠份量选择、逐营养素完整度、可保留的手动总量调整、常用餐食复用，以及可恢复的 HealthKit 修改同步。营养页提供能量卡、三项宏量营养圆环、目标与限量进度、全部营养明细与趋势。无需 AI、服务器、API 密钥或账号；有歧义的食物需要用户选择，缺失营养保持未知。详见 [实现、来源、限制与真机验收](docs/OFFLINE_NUTRITION_REDESIGN.md)。
