import SwiftUI

/// Static guidance only: no account, model SDK, network request or automatic data sharing.
struct ExternalInformationGuide: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    private var prompt: String {
        L10n.tr("请帮我整理我提供的包装标签，不猜测缺失营养值。列出产品名称、每份定义、各成分原名、含量、单位及原文依据；区分总量、子成分和提取物当量。未知请写未知。不要把推荐服用量当作实际摄入量，也不要把药物剂量当作营养。普通餐食若没有可靠营养资料，请不要编造数值，并注明来源与不确定性。我会核对后手动填入 OpenIntake。")
    }
    var body: some View {
        List {
            Section(L10n.tr("可选的外部工具")) {
                Text(L10n.tr("你可以自行使用 ChatGPT、Claude 或其他工具核对标签。OpenIntake 不连接这些服务，不需要账号或 API 密钥，也不会自动发送照片或健康记录。"))
                ShareLink(item: prompt) { Label(L10n.tr("分享核对提示词"), systemImage: "square.and.arrow.up") }
                Text(L10n.tr("这里只分享通用提示词；照片和文字由你自行选择是否提供给外部服务，并遵循其隐私政策。外部回答不保证准确。"))
            }
            Section(L10n.tr("核对后手动填写")) {
                Text(L10n.tr("1. 对照包装或可靠资料，核对每份／每100g／每100mL、含量与单位。\n2. 在产品或餐食页填入已核实的数值；未知留空。\n3. 保存产品供以后复用。实际摄入时输入数量，确认后才同步 Apple 健康。"))
                Text(L10n.tr("保存产品不会记录摄入。只有同步中心显示已写入并核验，才代表对应样本完成同步。"))
            }
        }.navigationTitle(L10n.tr("借助外部工具核对"))
    }
}
