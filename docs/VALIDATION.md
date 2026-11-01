# 本次验证记录

日期：2026-10-10。环境：Apple Silicon macOS，Xcode 27.0 beta（27A5252f），iPhoneOS 27 SDK，Swift 6 language mode。

- 最终 `xcodebuild`，generic/platform=iOS，CODE_SIGNING_ALLOWED=NO：**BUILD SUCCEEDED**。
- Swift Package XCTest：**10 tests，0 failures**。包括 8 项领域/存储测试和 2 项同步故障测试。
- Info.plist、HealthKit entitlements、PrivacyInfo.xcprivacy 及 project.pbxproj：plutil 校验通过。
- Python 工程生成脚本语法及确定性重建通过。
- 本机未安装 iOS Simulator runtime，未运行模拟器。
- 未选择个人签名 Team，未连接或安装 iPhone，未完成摄像头、真实 HealthKit、Siri、Action Button 或端侧模型运行验收。
- GitHub Actions 已提供但未在远程运行；本地无 GitHub remote，项目未上传。

构建和测试最初受受限执行环境的宏沙箱/系统缓存路径影响；使用同一 Xcode 工具链在获准的本地构建环境完成验证。没有改动全局 xcode-select，没有安装依赖或模拟器。

下一项验收请按 TESTING.md 在签名 iPhone 上进行。测试通过不能替代真实 HealthKit 幂等、权限和删除行为检查。

## 后续模拟器启动验证（2026-10-10）

已通过 Xcode 官方命令下载并安装 iOS 27.0（24A5423a）arm64 Simulator runtime。模拟器目标编译 BUILD SUCCEEDED，使用 iPhone Air 模拟器成功安装并启动 org.openintake.app，已在 Device Hub 确认首页正常显示。本次未录入摄入或授予健康权限。Xcode 27 beta 的模拟器画面由 Device Hub 展示。真机仍需签名 Team 与 Developer Mode；未安装到实体 iPhone。

## 真机安装准备与修复（2026-10-10）

实体 iPhone Air 已连接且 Developer Mode 已由用户开启。本次修复：

- 相机扫描前明确请求/检查授权；拒绝权限时显示手动录入及设置指引。
- 本地资料库直接读取并区分不存在和不可读，避免将权限/文件保护错误误判为空资料库；提供解锁后的重新读取入口。
- 数字键盘增加完成按钮，手动重复营养项和无效数值有明确提示。

更新后 generic iPhone 无签名构建及 Simulator 构建均 BUILD SUCCEEDED；11 项 XCTest 全部通过。更新的 Simulator App 已安装、启动并检查产品表单；未保存测试摄入，未验证真实 HealthKit 或真实相机权限效果。

已尝试对连接的实体 iPhone 签名构建，失败原因为未选择 DEVELOPMENT_TEAM。Xcode 当前显示 Add Account；用户需先登录开发账号并选择 Team，之后才能生成可安装的签名 App。未生成可安装 IPA，也未将 App 安装到实体 iPhone。

## 2026-10-10 成分映射重构

使用 Xcode 27 beta toolchain 执行 swift test：27 项通过，0 失败。iPhone generic/platform=iOS 与 generic/platform=iOS Simulator 无签名编译均 BUILD SUCCEEDED。覆盖 Jamieson 层级、宽泛映射同意、1/2/3 粒及每份两粒、单位转换、歧义与循环拒绝、旧版解码、冻结写入快照、同步失败持久化。未以 mock 结果冒充真实 Apple Health 授权或数据库验证。

独立 OpenIntake Mapping QA 模拟器安装并启动成功，合成产品首页显示按粒记录；确认页显示一次性保存、每份粒数、鱼油数量和本地状态，技术映射收在详情中。完整滚动交互及真实摄像头 OCR 尚需人工验收。

最终代码已签名构建成功并经 devicectl 确认更新安装至用户 iPhone Air。安装不等于真机功能验收；未替用户授权或生成真实摄入样本。
远程启动命令 20 秒超时，未确认真机自动启动；请用户从手机桌面打开进行验收。

## 完整营养清单与提示修正

SDK 集合检查通过：39 种 Dietary 类型 = 37 种质量类型 + 能量 / 饮水，原 10 个质量漏项补齐；已纳入 CI。31 项 XCTest 全通过，无签名 iOS、模拟器及签名真机构建均 BUILD SUCCEEDED。新版已安装到 iPhone Air。

隔离 iOS 27.0 模拟器运行时清单检查正常；UI 实测开关关闭显示待确认原因，打开后预览多不饱和脂肪 500 mg。未保存这个开关测试或生成新摄入。真机远程诊断被系统以 Locked 拒绝：iOS 27.2 实际运行时验证与真实 HealthKit 写入仍待用户解锁后执行，不能用模拟器结果替代。

## 真机白屏排查与 iOS 27.2 类型核对

Xcode Debug Navigator 显示真机进程暂停于 HomeView.body，OpenIntakeApp.swift 第 17 行文件断点启用，工具栏为 Paused。已关闭当前唯一断点的激活状态；不通过修改业务代码掩盖调试器暂停。原调试会话继续后报告 signal 9 结束，不能把它作为已恢复 UI 的证据，因此另行冷启动。

随后 devicectl 在用户 iPhone Air 上冷启动成功，控制台输出 os=27.2 / count=39；全部 39 项 available=true、unitCompatible=true、aggregation=0。构造 PUFA 样本读回 0.5 g，saved=false。没有申请健康权限、读取个人健康样本或写入摄入。这次结果是 iOS 27.2 实机类型验证，替代此前被锁屏阻止的检查。

Xcode 关闭断点并重新 Run 后显示 Running OpenIntake on Eason’s iPhone。控制台另有 App Shortcuts helper 连接失败；将索引刷新从 App.init / 保存路径主线程移至合并的 utility 任务，HealthWriter 改为延迟初始化，以防可选系统服务拖住本地首页。

最终启动保护版本：无签名 iOS 与签名真机编译通过，更新安装成功。在 iOS 27.2 真机以 `--startup-audit` 冷启动，收到 `OPENINTAKE_UI_READY`（首页 onAppear 回调），确认首页生命周期已进入。结束诊断控制台后以无诊断参数普通模式再次启动成功，留给用户操作。断点暂停是本次白屏的直接证据；索引后台化和 HealthKit 延迟初始化是额外的启动隔离保护。未因此宣称所有功能已完成真机验收。

## 0.2.0 多语言语义管道与图标（2026-10-10）

本次为现有 App 增量修改；未更换资料库或创建另一套 App。新增结构化 Vision 文档适配、@Generable 本地模型提供者、语言无关身份词典、原文验证及已验证规则补全。现有摄入 outbox、稳定 syncIdentifier 与撤销 tombstone 保留。叶子图使用用户提供 PNG，标准化为 1024×1024 不透明 AppIcon，构建产物 Info.plist 的 CFBundleIconName=AppIcon，版本 0.2.0。

- 最终 53 项 XCTest 通过，包含英文/中文/英法/混合、共享双语数值、跨行位置/表格、错字/低置信度/不等号、化合物净量、特殊单位、每100g/mL、父子去重、模型遗漏/冲突及持久化失败重试/撤销。
- SDK 审计脚本通过：39 个 Dietary 标识与领域枚举完全一致；37 质量 + mL 体积 + kcal 能量。工程重生成确定性检查通过。
- 最终 iOS 无签名与真机签名构建均 BUILD SUCCEEDED，覆盖安装成功，保留本地资料。模拟器构建/安装/首页与编辑确认页已检查；该 UI 检查中模型拒绝正确显示降级原因，六项规则草稿及包含/等效关系可见，测试草稿未保存。
- 真实 Vision（macOS、生产 DocumentOCR）12 个绘制文字标签角度案例通过：10 个准确获得鱼油834mg及Omega-3 500mg，2 个因“欭米伽”或“母粒”OCR 错字明确隔离、无 PUFA 写入计划。不是 100% OCR 准确率，也不是实际瓶身照片的相机测试。
- 真实本机 Apple 模型测试发现原提示会拒绝，随后使用纯文档转录/实体组织提示、明确 evidenceID JSON 输入和结构化数值字段。macOS 真实模型成功返回并验证六项成分，perUnit、单一 PUFA 500mg、warnings=0、saved=false；没有使用云模型或修改默认 guardrails。模型仍可能拒绝或生成错误字段，App 会明确降级或依靠独立原文规则补全，数值冲突不得自动选取。

Xcode 27 beta 的部分签名构建日志含 AppIntents SSU 训练工具“Could not archive SSU artifacts”，但构建最终成功、动作元数据生成。Siri 自然语言训练效果仍需设备验收，不将这项非致命工具错误当作已修复。真实用户健康授权、样本保存及撤销仍必须按 TESTING.md 验收；所有自动诊断只处理合成标签，未写入用户健康数据。

最终真实本机模型脚本再次通过：六项规范化成分、perUnit、仅 PUFA 500mg、passed=true、saved=false；此次 provider=appleFoundationModels+validatedRules，说明有模型遗漏/无效字段由独立原文补全，不能描述为模型自身全部准确。真机此前一次 smoke test 曾出现八项条目（正确PUFA但重复本地条目），已新增名称中混入含量、虚构/重复化学形式及错误等效关系的回归与隔离；其后一次真机生成未在50秒诊断窗口内完成。最终实拍和真机模型输出稳定性仍需验收，不掩盖这些限制。CFBundleDevelopmentRegion 已补为字符串 en，修复运行时元数据警告。

最终覆盖安装成功后，普通启动验证被 iPhone 锁屏阻止（CoreDevice: Locked），因此未声称最终版本已通过真机 UI 启动验收。解锁后点击叶子图标进行 TESTING.md 中的实拍、授权、写入和撤销验收。

## 0.3.0 增量验证（2026-10-11）

- 69项核心XCTest通过；新增分列/串行OCR、分隔符、多列表格拒绝、饮水单位/日期/撤销/重复、提醒时段、餐食实际份量/明确确认/量纲/质量边界/来源及快照回归。
- 真实macOS本机标签AI smoke通过：6项成分、perUnit、单一PUFA500mg、passed=true、saved=false。仍使用独立规则补全，不能表述为模型全部独立正确。
- 真实Vision合成图回归通过：12个案例中10个准确、2个安全阻止；非实拍准确率评估。
- SDK39饮食类型审计通过。公开文件检查69个候选文件、零发现；本机签名仍由忽略文件提供。
- 最终iOS无签名、真机签名构建均BUILD SUCCEEDED；模拟器构建、覆盖安装、启动通过。检查首页饮水圆环、同步中心（本地记录原因及写入清单）、饮水设置的目标/时段/保存取消、餐食空草稿禁止确认。饮水设置从列表子视图提升至首页呈现，避免弹窗生命周期不稳定。
- Device Hub显示iPhone当前不可连接，未声称0.3.0已安装至真机。真实图片模型、系统Shortcuts照片传参、通知送达和Apple健康实际写入/撤销需连接设备后按TESTING.md验收。
- 餐食图片提示API由本机SDK27核实并编译，运行时检查本机模型vision/guidedGeneration能力；不能将iOS版本满足当作模型必然支持。无外部网络提供者。

### 营养权限入口增量修复

原实现只在实际摄入写入清单非空时请求授权：饮水必有类型，而待确认或未同意宽泛映射的产品没有可写清单。新增独立营养权限页，逐项显示39类型写入状态、用户选择申请及产品映射诊断。只申请所选营养类型的写权限；不请求读取、不保存样本、不改变历史快照。

73项核心测试通过，包括维生素C/钙的真实领域授权调用（mock后端）、宽泛映射同意边界、待同步历史类型及未知/未确认项目。无签名iOS构建BUILD SUCCEEDED，公开候选文件检查零发现。系统弹窗及真实授权状态仍需真机验收。

依据：[Apple authorizationStatus(for:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:))、[requestAuthorization(toShare:read:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:))。授权请求完成不代表所选类型全部允许，必须逐项检查写入状态。

### 0.3.1 官方授权与样本核验修复

77项XCTest通过；无签名及真机签名BUILD SUCCEEDED。已检查App签名与安装描述文件实际HealthKit entitlement，均为true；健康使用说明齐全。已覆盖安装0.3.1/build4至连接的iPhone，普通启动成功，Device Hub实见Apple官方Health Access窗口包含多种营养写入项目。未代替用户点击Allow，未声称真实营养保存/撤销已验收。

新增首次前台39营养授权请求、保存后仅对本App事件样本查询核验、撤销后空结果核验及旧记录未核验标识。新字段向后兼容，不修改历史摄入快照。详见HEALTHKIT_WRITE_VERIFICATION.md。

### 0.3.2 双语AI与本机提醒修复

83项核心XCTest通过；iOS真机无签名、签名及模拟器构建均BUILD SUCCEEDED。新增输入压缩/分段/重叠/跨语言去重/连接词和提醒计划测试。Mac实际调用端侧Foundation Models完成英法双语合成Jamieson标签约10.5秒，模型草稿6行，其中5行通过独立验证，规则补足最终6项；鱼油834mg和Omega-3 500mg均由AI直接正确提取并验证。最终写入计划为单个500mg多不饱和脂肪（需明确宽泛映射同意），不是重复EPA/DHA。该耗时不是iPhone性能承诺，也不代表实际弯曲瓶身照片已验收。

已实现通知权限状态、前台展示委托、5秒测试请求、每日自定补充剂提醒及关闭/删除清理；本机提醒不需推送服务器。实际通知授权由用户选择，送达需真机确认。覆盖安装首次尝试因Apple CoreDevice错误4016（设备不可连接）未完成，不将签名构建成功误报为安装成功。

后续连接恢复为wired/connected，0.3.2 build5真机覆盖安装exit0，普通启动exit0，Device Hub实见新版首页“通知与服用提醒”。在同一iPhone Air实际执行纯合成英法标签AI回归：本机模型available=true，耗时约18.83秒，aiRows=6、aiValidated=5；独立规则补足最终6项，单个PUFA500mg写入计划，passed=true、saved=false。没有为此测试创建产品或HealthKit摄入事件。真实瓶身拍照仍由用户验收，不能从合成文本测试推断照片准确率。

QA模拟器实际打开通知设置页并观察到授权/横幅/声音均开启，测试请求进入pending队列；未将pending视为送达证据。真机通知许可选择、后台/锁屏横幅及定时补充剂提醒仍需用户验收。

### 0.3.3 共享双语名称与证据链修复（2026-10-12）

99项核心测试0失败，包含原始失败文字、T01–T15、同一物理OCR证据合并。iOS无签名、签名及模拟器构建全部BUILD SUCCEEDED，版本0.3.3/build6。真实Mac Apple模型：Jamieson约10.1秒，6行AI成分均验证；Vitamin C约3.8秒，经独立验证得到一个500mg主成分与两个化学来源。15个真实Vision合成角度案例13准确、2个OCR错字安全隔离。本次提供的截图文字区域也经实际Vision→真实模型→验证→写入计划通过；截图未入仓库。

QA模拟器确认UI自动填写维生素C、每片500mg、准确映射和两个来源；保存、普通重启、重开后仍正确，无新增摄入事件。无签名模拟器缺HealthKit entitlement，未冒充实际健康保存验收。真实模型曾拒绝旧提示词，改为中性文字提取后复验通过，默认防护未关闭。按用户选择先验证、稍后安装，0.3.3未覆盖安装手机；真实瓶身照片与实际健康写入仍待验收。详细根因和测试边界见 [修复报告](LABEL_PIPELINE_REPAIR.md)。

### 0.3.4 最近摄入防误触及恢复（2026-10-12）

104项核心测试0失败；iOS无签名与模拟器最终构建均BUILD SUCCEEDED。新增测试覆盖完成/部分删除后的恢复、清理失败和部分写入重试、权限拒绝后重试、重复替代记录防护、仅本机成分、持久化和旧版本兼容。恢复原事件ID、时间、份数及冻结健康写入清单，增加同步版本；先原子保存恢复意图，再精确清理原事件残留并重写核验。

既有QA模拟器覆盖更新并启动成功。实际UI检查：正常记录没有内联撤销；完整左滑只显示撤销按钮，未执行；点击撤销后出现“取消撤销并恢复”，点击后回到原时间/数量的待同步记录。既有已撤销行显示“恢复记录”。QA无签名版本缺HealthKit entitlement，因此失败仍保留本机待同步，没有创建真实健康样本。本次未更新iPhone；真实Apple健康删除/恢复仍需真机验收。公开候选文件86个、隐私检查0发现。

### 0.3.5 权限关闭后重新开启（2026-10-12）

根因：通知按钮在denied时仍重复调用请求并仅显示错误，设置跳转没有处理失败；健康类型选择使用Toggle，容易被误认为系统授权开关，重复requestAuthorization不保证出现窗口。通知现根据最新系统状态分流：首次请求、其他状态打开官方通知设置，失败回退App设置/手动指引；回到前台刷新。健康在请求前调用官方statusForAuthorizationRequest，已处理且有拒绝类型时显示Apple健康重新开启步骤，增加手动刷新并改用申请勾选。

104项核心测试0失败。QA模拟器新版通知页显示真实已授权/横幅/声音状态与“检查／调整通知权限”；点击唤起系统设置，但当前iOS27模拟器保留Developer页面，未定位通知子页，故不能将API返回成功等同于设置落点验收。App已补常驻手动路径；关闭后重启权限的真机全流程、首次弹窗、通知送达和健康权限恢复仍待验收。本版未覆盖安装iPhone。

依据：[Apple 通知授权的重复请求行为](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:))、[官方通知设置URL](https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring)、[HealthKit 授权请求状态](https://developer.apple.com/documentation/healthkit/hkauthorizationrequeststatus)。本机SDK27核对并编译HealthKit状态查询接口，不使用私有健康设置URL。

最终代码的iOS无签名及模拟器构建均BUILD SUCCEEDED（0.3.5/build8）；公开候选文件86个、隐私扫描0发现。

### 0.4.0 离线饮料食品与盐（2026-10-12）

113项核心测试0失败，新增ManualNutritionTests的9项回归。最终iOS无签名及模拟器构建均BUILD SUCCEEDED；已重生成工程，版本0.4.0/build9。公开候选文件90个、隐私检查0发现。新增代码没有网络或AI调用。

QA模拟器实际手动建立公开虚构饮料模板：每100mL糖10g、钠20mg、包装330mL，能量留空。保存后糖/钠仍显示未记录，没有新增摄入；重新打开保留100mL、330mL、10g及20mg，未知能量没有变为0。首页一瓶/半瓶及自定义数量入口可见。点击一瓶后统计糖33g、钠66mg，喝水保持0mL；同步中心显示相同数值。无签名环境缺HealthKit entitlement，记录如实保留待同步，没有真实健康写入。为避免有效虚构记录留在QA统计中，已撤销该测试摄入；因模拟器权限限制保留deletionPending，统计回到未记录，未误报为实际删除完成。该QA模板仍留在模拟器供界面检查，不在公开仓库保存其本机账本。

核心自动化另外覆盖普通食盐5g×25%个人比例→钠500mg、人工估算来源、半瓶和酱料换算、标签基准一致性、完整保存读取、冻结历史、模拟健康同步/删除/恢复与重复防护。本版尚未安装到iPhone，真实Apple健康样本和盐表单真机操作仍待验收；不以mock或无签名模拟器代替真机证明。详见MANUAL_FOOD.md。

### 0.4.1 糖／钠授权与写入证据（2026-10-12）

116项核心测试0失败；新增3项覆盖两种质量单位、缺失/错误样本拒绝、实际核验与本地统计分离、冻结写入计划、旧版未核验状态、日期和撤销状态、拒绝权限不写入与恢复后重试两项类型。iOS无签名和模拟器构建均BUILD SUCCEEDED，工程已重生成，版本0.4.1/build10。

QA模拟器首页实际显示糖／钠“尚未申请”、已核验0、待同步0、待撤销1（沿用上一版已撤销的QA饮料事件）。点击专用授权入口后可见“申请所选2项写入权限”；由于本次是无签名环境，显示Missing com.apple.developer.healthkit entitlement，未误报授权成功或已写入。没有新建摄入，没有改动真机数据。

真实iPhone验收仍待安装后进行：检查糖与钠的逐项权限；用真实摄入记录确认同步页“已写入并核验”，并在Apple健康对应营养类别核对OpenIntake来源、数值与时间；关闭任一类型后记录应保留待同步，恢复后重试不重复；撤销后样本删除，恢复后仅一份。未把模拟器或mock结果当作真机写入证明。

### 0.5.0 WidgetKit与快捷指令（2026-10-12）

最终120项核心测试0失败，新增QuickIntakeTests的4项回归（含单位变化、药品、失效产品、重复、拒绝权限、重试、撤销恢复）。iOS与模拟器无签名构建均BUILD SUCCEEDED，无编译警告；两目标App Intents元数据生成、扩展嵌入验证通过。生成工程可包含OpenIntakeWidgets扩展，版本0.5.0/build11。公开候选99文件、隐私检查0发现。

QA模拟器实际安装并打开配置指南，ShortcutsLink可触发系统动作发现，观察到记录饮水、记录饮料食品和记录摄入三入口；编译元数据另包含按份及餐食照片自定义动作。主屏幕系统小组件库可找到OpenIntake，三个页面分别提供饮水小号、常用产品小号／中号，实际查看了饮水150/250mL按钮、说明和布局渲染。尚未把这一发现/渲染结果当作完整小组件动作闭环成功。

本版尚未安装至物理iPhone。App Group签名、可配置产品实际列表、冷启动／锁屏点击、快捷指令参数询问、Siri和操作按钮、照片传入及真实Apple健康样本都需要设备验收，详见WIDGETS_SHORTCUTS.md。无签名环境缺HealthKit entitlement，不能据此证明真机写入成功；没有向用户真机注入测试摄入。

### 0.5.1 可执行工作流、文字餐食与产品组件修复（2026-10-12）

最终128项核心测试0失败。新增TextMealTests的7项回归，QuickIntakeTests增加组件默认／删除／单位变化保护。iPhone及模拟器无签名构建均BUILD SUCCEEDED，最终签名构建也成功。仅以布尔结果检查签名产物：主App和扩展的App Group entitlement匹配Info配置，双方profile均允许同一group；主App含HealthKit，扩展不含HealthKit。个人签名内容未输出或写入公开文件。

QA实际验证App内六类原生菜单、饮料模板330mL默认量与空产品禁用；文字输入经真实键盘进入多项草稿，本机模型返回rice/chicken/apple与150/100/80g及原文引用。第一次模型返回中存在非法／未知估算，旧全组拒绝策略清空营养；已修正为先排除未知零值、重复及非法单项，再联合检查宏量总量，新增测试验证保留合法项目及拒绝矛盾总量。该UI测试证明名称和质量整理，不证明估算营养事实准确；草稿取消，没有点击确认写入。

从系统Shortcuts页面实际运行“选择并记录”，观察到六项类别菜单；选择饮料食品后出现产品选择及“实际摄入多少mL”输入页，取消未提交。不是将所有记录动作顺序串联。

旧AppIntentConfiguration产品组件在实际日志中出现XPC linkAction无法解析、CHSErrorDomain1101空视图。只移动配置类型到扩展仍未解决，最终移除该配置路径及专用查询，改为StaticConfiguration稳定时间线，App内选择产品和数量；新kind为OpenIntakeFavorite。QA实际检查小号与中号完整预览，中号含其他摄入入口；添加到主屏幕后正常显示共享不可用提示和可执行入口，点击能打开完整App菜单。无签名QA无法获取App Group容器，因此没有把预览或签名匹配当作真机产品共享成功证明。旧产品组件需移除重加，小中号共用App设置。

最终公开候选104文件，隐私扫描0发现。此版本未覆盖安装物理iPhone。真机仍需验收实际产品名及数量、小组件冷启动、Siri／操作按钮、文字估算核对后真实摄入的HealthKit样本与撤销恢复；所有输入到草稿阶段不应新增摄入。详见WIDGETS_SHORTCUTS.md。

## 0.5.2 餐食确认修复（2026-10-13）

详见 [根因、修改范围、饮料遗漏与验收](MEAL_CONFIRMATION_FIX.md)。141 项核心回归通过，iPhone/Simulator 无签名构建通过。实际模拟器 SwiftUI 开关开启、刷新保持、关闭禁用提交、无效份量重置及明确提示均验证；测试草稿已取消，无新增摄入。未在真机安装，未将测试数据写入用户 Apple 健康。原补充剂识别与健康写入适配器没有修改。
