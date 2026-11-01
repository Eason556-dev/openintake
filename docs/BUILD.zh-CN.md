# 在自己的 iPhone 与 Apple Watch 构建和安装

[English](BUILD.en.md) · [简体中文](BUILD.zh-CN.md) · [README](../README.zh-CN.md)

## 1. 下载源码与准备工具

1. 打开 [Releases](https://github.com/Eason556-dev/openintake/releases)，选择版本 → Assets，下载对应 `OpenIntake-<版本>-source.zip` 和校验文件。
2. 可在下载目录运行 `shasum -a 256 -c <下载的校验文件名>`，结果应为 OK。
3. 在 Finder 双击 ZIP 解压，整个文件夹保持完整，工程会引用旁边的 App、Shared、Config 等目录。
4. 从 Apple 安装 Xcode，首次打开后自行完成组件安装与许可确认。本版通过 Xcode 27.2 验证。Mac 必须满足对应 Xcode 要求，在 Xcode Settings → Components/Platforms 按版本提示安装 iOS/watchOS 支持。见 [Apple 系统要求](https://developer.apple.com/xcode/system-requirements/)。
5. 打开 **OpenIntake.xcodeproj**，不要用 Package.swift 作为手机 App 入口；Package.swift 用于核心测试。

## 2. 配置自己的标识符

项目不提供维护者的 Apple 账号、签名证书或描述文件。

在 Finder 复制 `Config/Local.example.xcconfig`，将副本改名为 `Local.xcconfig`，放在 Config 目录内。也可在源码目录执行以下命令，只在本地文件不存在时创建：

```sh
test -f Config/Local.xcconfig || cp Config/Local.example.xcconfig Config/Local.xcconfig
```

打开 Local.xcconfig，将两项示例值改为自己的唯一值。例如使用自己的前缀 `org.example.intakepreview`：

```text
OPENINTAKE_BUNDLE_ID = org.example.intakepreview
OPENINTAKE_APP_GROUP = group.org.example.intakepreview.shared
```

`org.example` 只是示例，不要原样照抄注册。个人标识符放在 Local.xcconfig，不修改公开默认配置；该文件已从 Git 和源码包排除。

工程自动派生四个目标：

| Target | Bundle ID 示例 |
| --- | --- |
| OpenIntake | `org.example.intakepreview` |
| OpenIntakeWidgets | `org.example.intakepreview.widgets` |
| OpenIntakeWatch | `org.example.intakepreview.watchkitapp` |
| OpenIntakeComplications | `org.example.intakepreview.watchkitapp.complications` |

Watch 配套 iPhone 引用使用同一个基础前缀。不要只孤立修改手机目标的 Bundle ID。

## 3. 四个目标都配置签名

1. Xcode → Settings → Accounts 添加自己的 Apple 账号，自行完成登录及 Apple 协议确认。
2. 左侧选蓝色 **OpenIntake** 工程 → TARGETS → **OpenIntake** → Signing & Capabilities。
3. 勾选 **Automatically manage signing**，Team 选择自己的团队。
4. 对 **OpenIntakeWidgets、OpenIntakeWatch、OpenIntakeComplications** 重复操作，四个目标选择同一 Team。也可仅在 Local.xcconfig 填写自己的 Team ID。
5. iPhone 目标保留 **HealthKit**。四个目标的 **App Groups** 注册/选择同一组，必须与 `OPENINTAKE_APP_GROUP` 一致。由 Xcode 自动生成描述文件，或在自己的 Apple Developer 账号管理。
6. 所有红色签名错误解决后再运行。能力支持取决于会员资格和平台，免费 Personal Team 不保证可签完整目标；见 [Apple 能力说明](https://developer.apple.com/help/account/capabilities/capabilities-overview)及 [App Groups 配置](https://developer.apple.com/documentation/xcode/configuring-app-groups)。

如果团队不能配置 HealthKit 或 App Groups，请使用符合条件的团队，或先在模拟器预览 UI。删除这些能力会改变功能，不代表完成了完整安装。

## 4. 先运行 iPhone

1. 用数据线连接 Mac 与 iPhone，保持解锁，在手机上确认**信任此电脑**。
2. 按提示开启 **设置 → 隐私与安全性 → 开发者模式**，完成重启和设备确认。见 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
3. Xcode 打开 Device Hub / Devices and Simulators（名称随版本变化），等待设备准备完成，显示可用或 Ready。
4. 顶部 scheme 选择 **OpenIntake**，运行目标选择**自己的真实 iPhone**，按 **Product → Run（⌘R）**。Xcode 会构建、签名、安装并启动，不需要另行安装未签名 IPA。
5. 如果 iOS 要求信任开发者身份，按设备提示到 设置 → 通用 → VPN 与设备管理，确认自己团队的身份。不要信任陌生维护者的描述文件。
6. 在 App 内允许要写入的营养类型。权限按类型分开；曾拒绝的类型可能需要到 Apple 健康 → 个人资料/数据访问权限 → OpenIntake 修改，菜单随 iOS 变化。

## 5. 安装 Apple Watch 配套 App

1. Watch 先与第 4 步的 iPhone 配对。两端保持解锁、靠近并连接，打开蓝牙/Wi-Fi。
2. Xcode 要求时，在 Watch 开启开发者模式，完成重启确认。
3. 在 Device Hub 等待配对 Watch 可用。手表通常依赖已配对手机完成准备，不是任意 Watch 都能作为独立有线 Mac 目标。
4. scheme 选择 **OpenIntakeWatch**，目标选择**自己的 Watch**，按 **⌘R**。失败时检查 Watch 和 complications 目标签名。
5. 打开手机 App，让其发送产品和今日数据；新产品在手机配置。在手表记录一次已有产品或饮水，再查看手机同步中心。Watch 显示“已送达”不等于 HealthKit 样本已经核验。
6. 表盘组件：长按兼容表盘 → 编辑 → 复杂功能 → OpenIntake。可用位置随表盘变化。

## 6. 验收记录与健康同步

用实际数量或明确标注的可丢弃测试记录验证。合成测试结束后请在 OpenIntake 撤销，并确认它自己创建的健康样本被删除。

- 保存产品后，不应仅因扫描/保存就出现摄入事件或健康样本。
- 记录实际产品数量后，在同步中心核对状态；再到 Apple 健康 → 浏览 → 营养 → 对应营养素 → 显示所有数据，核对数量、时间和来源 OpenIntake。菜单名随系统版本变化。
- 输入 `米饭 150 克，茶 250 毫升`：无需确认开关即可记录；没有营养值时应为**仅本机**，不能声称已同步健康。有真实依据时填写每 100 g/mL 值，应按实际数量缩放。
- 拒绝一个写入权限：本地记录仍在，显示待同步和原因。恢复权限重试后不能重复写入。
- 撤销/恢复：保持原时间和数量；撤销必须处理对应的本 App 健康样本。
- Watch 记录一次 250 mL：送达后手机只能有一条 250 mL，不是 500 mL；断开再连接也不能翻倍。
- 切换 App 语言，收到/刷新后检查手机、Watch 和组件。系统授权弹窗使用系统语言设置。

## 模拟器及命令行验证

选择 OpenIntake + iPhone Simulator，按 ⌘R 可预览 UI。模拟器相机和健康行为不能证明真机验收。

在源码目录执行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenIntake.xcodeproj -scheme OpenIntake \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/OpenIntake-build \
  CODE_SIGNING_ALLOWED=NO build
```

Xcode 路径不同时替换为实际安装位置。添加/删除 Swift 文件或修改生成器管理的工程配置后才需要运行 `python3 scripts/generate_project.py`。个人签名放 Local.xcconfig，因为生成工程会替换工程设置。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| 签名、描述文件、能力报错 | 检查四个目标、相同 Team、唯一派生 ID、已注册 App Group 和会员资格；不要索取他人的证书。 |
| 手机/手表不可用 | 解锁两端、重接数据线、确认信任及开发者模式，等待平台支持/设备准备完成，再看 Device Hub。 |
| 调试时白屏 | 检查 Xcode 是否在断点暂停；Continue 或禁用断点。没有暂停仍白屏时，再检查崩溃与控制台。 |
| 记录按钮不可用 | 看页面明确原因：名称空、实际数量缺失/无效、有营养值时修改文字未重新核对、正在提交。无需开关或 AI。 |
| 全未知餐食未进健康 | 正常：没有已知营养可写，其名称与份量仍保存在本地历史。 |
| 授权窗口不再出现 | iOS 可能不重复显示已决定的请求，检查逐类型状态，并到 Apple 健康修改权限。 |
| 组件空白或过期 | 打开手机 App、配置产品、核对 App Group，再等待系统刷新或重新添加组件。 |
| Watch 已送达但健康待同步 | 传输确认不等于样本核验，检查手机同步中心与权限。 |

[Apple：模拟器或真实设备运行](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)。
