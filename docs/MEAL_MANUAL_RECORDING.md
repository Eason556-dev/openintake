# 0.7.2 — Meal recording without the AI-era checkbox

## Root cause / 根因

The SwiftUI Toggle called `setAccepted`, which refused to stay on whenever `confirmationIssues` contained missing quantities or stale text. The final button depended on a second set of issues requiring that flag. After AI removal, text was not always prepared until the user explicitly selected the separate text action; all-unknown meals were also rejected as if recording always required a nutrition sample. A checkbox alone could not solve those separate blockers.

开关不是 AI API 直接控制，但其 setter 会因缺份量、文字未整理等条件立即把状态置回 false。记录按钮又依赖该状态；移除 AI 后，另一步“整理文字”及“全部营养未知不能提交”的约束，使手动流程看起来无法使用。

## Implementation / 修改

- `MealEditor`: remove the Toggle; Record is the explicit confirmation. Rules update name/quantity previews while editing text only when no nutrient values would be discarded. Existing filled nutrient rows are never silently replaced.
- `MealReviewState.recordingIssues` / `beginRecording`: validate content, stale state, quantity and submission identity without a separate checkbox. The legacy confirmation helper remains for backwards regression coverage; the current UI does not call it.
- `MealValidation.product(... allowLocalOnly: true)`: allow a valid unknown-only meal with no nutrient amounts; never generate zeros or model values.
- `Product.validate`: allow an empty nutrition plan only for a valid food meal whose saved details also contain no known nutrients. Empty arbitrary products, missing quantities and hidden known values cannot use this exception.
- `IntakeStore` / history: unknown-only meals show local-only status and quantity details. Existing shared outbox marks them local without authorization/writes; known contributions retain normal permission, verification, retry and undo behavior.

## Evidence / 验证

174 core tests passed, including four added tests: unknown-only tap-to-record with no checkbox; zero Health authorization/write calls for that event; local undo/restore and decoding; known-value permission denial and retry without duplicate samples; invalid quantity/stale text; rejection of invalid empty-product exceptions.

Full iOS/Watch unsigned builds passed with Xcode 27.2, including the final UI fixture. A ZIP-extracted public-source copy also built without Config/Local.xcconfig. The simulator screenshot shows Confirm & log available with no checkbox and no known nutrients. Mock Health tests do not establish true-device sample acceptance.

真机重点：输入明确的 g/mL 文字后直接记录；全未知应显示仅本机；填写有依据的营养后核对真实 Apple Health 样本；修改已填写营养的原文时必须按页面提示重新核对。
