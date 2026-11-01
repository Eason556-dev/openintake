# Publication privacy checks / 开源隐私检查

Date: 2026-11-01. Scope: this dedicated repository and its source-release assets only.

## Included checks

- All tracked files plus non-ignored publication candidates: source, Xcode project/settings, entitlements, documentation, screenshots and workflow files.
- Every file version in the public commit history, not only the current working tree.
- Both Xcode team-setting spellings, literal signing identities, email/account indicators, provisioning/certificate/private-key artifacts and common API/access-token formats.
- Source ZIP entries and per-file hashes. Personal overrides, .git, developer build products, device profiles, archives and health-library exports are excluded.
- PNG text/EXIF metadata is removed from documentation screenshots without changing their pixel data. Images depict empty/synthetic simulator data.

No private Apple account, personal team value, access token or private key was found in the checked public content. `Config/Local.xcconfig` remains ignored and untracked. The public project uses configurable generic defaults; builders provide their own identifiers and Team.

Git commits use the GitHub public no-reply identity, not an Apple ID. GitHub workflow authentication refers to the platform-provided runtime token expression; there is no literal token in source. No Apple signing material is uploaded for CI; builds are unsigned.

Checks are heuristic and cannot prove that every possible future secret format is recognizable. Run `python3 scripts/check_public_files.py` before each push and package, and review new files. If a real secret is ever published, revoke/rotate it first and clean affected history and assets; deleting it from the latest commit alone is insufficient.

## 中文

本轮核查包含公开源码、Xcode 工程、全部提交里的文件版本及 Release 源码包，而不只当前目录。未发现 Apple ID、个人签名团队值、令牌或私钥；个人 Local.xcconfig 未追踪。文档截图仅为空库/合成模拟器界面，并清除了附加元数据。

账号与签名使用者自行在设备/Xcode 配置。CI 不上传 Apple 签名资料；Git 提交使用 GitHub 公开 noreply 身份，不是 Apple ID。检查不会输出敏感匹配内容本身。
