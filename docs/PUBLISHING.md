# 发布源码到 GitHub / Publish source on GitHub

本项目专用仓库：[Eason556-dev/openintake](https://github.com/Eason556-dev/openintake)。以下步骤只针对该仓库或你自己的 Fork，不操作其他已有仓库。

## 初次公开发布

1. 先修复并测试代码，补齐 README.md / README.zh-CN.md、LICENSE、构建指南与示例截图。
2. 运行：
   ```sh
   swift test
   python3 scripts/check_public_files.py
   python3 scripts/check_localization.py
   python3 scripts/generate_project.py
   xcodebuild -project OpenIntake.xcodeproj -scheme OpenIntake \
     -destination 'generic/platform=iOS' -derivedDataPath /tmp/OpenIntake-build \
     CODE_SIGNING_ALLOWED=NO build
   ```
3. 在 GitHub 新建专用 **Public** 仓库，不把项目上传到无关旧仓库。项目已包含 MIT LICENSE，不再由 GitHub 添加另一份许可或冲突 README。
4. 在本项目的 Git 目录核对 `git remote -v`。仅指向目标专用仓库；没有 remote 时才添加。不要重设其他项目的 remote。
5. 只提交公开源文件。检查 `git status --short`、`git diff --cached --name-only`，确认没有 Local.xcconfig、个人资料库、证书、描述文件、构建目录或 API 凭据。运行公开文件检查后再 commit/push 到 main。
6. 浏览 GitHub main，确认双语 README、图片及源码目录正确显示，再准备 Release。

本地公开文件检查为启发式检查，不是秘密扫描的数学证明；新增格式需要人工审查。不要通过网页拖拽整个工作目录绕过 Git ignore。

## v0.8.0 Release

先在干净/已核对的源码目录打包：

```sh
python3 scripts/check_public_files.py
python3 scripts/package_source.py --version 0.8.0
```

产物在忽略的 dist/：

- `OpenIntake-0.8.0-source.zip`：Xcode 工程、源码、双语文档、示例配置、截图、许可与 SOURCE_MANIFEST.json。
- `OpenIntake-0.8.0-source.zip.sha256`：整个 ZIP 的 SHA-256。

不包含个人 Local.xcconfig、.git、签名资料、健康记录或 IPA。ZIP 创建后会校验逐文件摘要及 ZIP 完整性。

### 自动方式：标签触发

在已确认只有该项目的专用仓库中，对通过测试的提交创建并推送标签：

```sh
git tag v0.8.0
git push origin v0.8.0
```

`.github/workflows/release.yml` 先在 macOS 运行检查、核心测试和无签名构建，再打包并发布源码预览 Release。需要仓库允许 GitHub Actions 运行，并允许该发布 job 使用 contents:write；不需要维护者个人访问令牌或 Apple 凭据。

若 GitHub 托管运行器的 Xcode SDK 不满足源码所用 API，构建会失败并阻止自动发布。选择符合要求的运行器/工具链后重试；不要跳过失败的构建假装通过。发布环境/权限由仓库所有者决定。

### 网页方式：已验证的本地产物

1. 专用仓库 → **Releases → Draft a new release**。
2. Tag 填 **v0.8.0**，Target 选择已核验的 main 提交。已有标签时选择同一标签，不随意移动已发布标签。
3. 标题填 **OpenIntake v0.8.0**；复制 `docs/releases/v0.8.0.md` 的说明。
4. 向 Assets 上传上面的两个 dist 文件，等待上传完成。
5. 标记 **pre-release**，因为目前是开发预览。检查下载名称、构建证据和说明后发布。
6. 下载公开 ZIP，验证 checksum、解压并确认无 Local.xcconfig，能找到 OpenIntake.xcodeproj 及两份 README。

若对应标签已有已发布 Release，工作流会保留它，不替换公开资产；若只是未发布草稿，则上传已验证源码并完成草稿发布。建议选择单一发布方式，重复执行不覆盖已公开下载。

[GitHub 官方 Release 步骤](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。

## English maintainer summary

Use a dedicated repository, audit all publication candidates, run core tests and an unsigned iOS/watchOS build, then commit/push only source and documentation. Keep private signing overrides ignored.

`python3 scripts/package_source.py --version 0.8.0` creates an audited deterministic ZIP and SHA-256 file in dist/. Publish both as prerelease assets, with release notes from docs/releases/v0.8.0.md. Users open the included Xcode project and sign with their own eligible Apple team.

Either push a `v*` tag to run the verified-source release workflow, or publish the locally verified assets through GitHub's release UI. Do not run both for the same tag. Check the publicly downloaded archive and source manifest afterward. Neither a source ZIP nor an unsigned build is an installable IPA or proof of real-device HealthKit acceptance.
