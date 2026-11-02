import SwiftUI

struct RecordHistory: View {
    @AppStorage(L10n.preferenceKey) private var interfaceLanguage = "system"
    @ObservedObject var store: IntakeStore
    @State private var mealRequest: MealRequest?
    var body: some View {
        List {
                Section(L10n.tr("最近摄入")) {
                    ForEach(store.library.events.prefix(50)) { event in
                        VStack(alignment: .leading) {
                            Text("\(event.product.displayName) · \(event.consumedQuantity, specifier: "%.2g") \(L10n.display(event.product.intakeUnitTitle))")
                            if event.product.mealDetails != nil && (event.state == .synced || event.state == .localOnly) {
                                Button(MealNutritionRecovery.missing(in: event).isEmpty ? L10n.tr("编辑餐食") : L10n.tr("补全营养并重新同步")) { mealRequest = MealRequest(eventID: event.id) }
                            }
                            if !MealNutritionRecovery.missing(in: event).isEmpty {
                                Text(L10n.tr("原文中有营养值尚未成为健康字段；当前同步状态仅代表已经保存的字段。")).font(.caption).foregroundStyle(.orange)
                            }
                            if let meal = event.product.mealDetails {
                                DisclosureGroup(L10n.tr("本次餐食明细")) {
                                    if let text = event.product.mealInputText, !text.isEmpty { DisclosureGroup(L10n.tr("原始餐食文字")) { Text(text).font(.caption).foregroundStyle(.secondary) } }
                                    ForEach(meal.filter { !MealNutritionRecovery.isNutrientRow($0) }) { item in
                                        if let quantity = item.quantity { Text("\(item.name) · \(quantity.formatted()) \(item.portionUnit.rawValue)") }
                                        else { Text(item.name + " · " + L10n.tr("份量未知")) }
                                    }
                                    if let amounts = try? event.healthSamples, !amounts.isEmpty {
                                        ForEach(amounts) { amount in
                                            let unit = NutritionRegistry.displayUnit(amount.nutrient)
                                            let value = event.canonicalValue(for: amount) / unit.canonicalMultiplier
                                            Text("\(L10n.display(amount.nutrient.title)) \(value, specifier: "%.4g") \(unit.rawValue)")
                                        }
                                    } else { Text(L10n.tr("仅本机餐食记录，没有营养样本写入 Apple 健康。")) }
                                }
                            } else if let items = event.product.ingredients {
                                DisclosureGroup(L10n.tr("本次成分明细")) {
                                    ForEach(items) { item in
                                        if let amount = item.amount(forServings: event.servings) {
                                            Text("\(item.displayName(language: L10n.language))：\(amount, specifier: "%.4g") \(item.unit)\(item.relation == .equivalent ? L10n.tr("（等效量，不另相加）") : "")")
                                        } else { Text(L10n.tr("\(item.displayName(language: L10n.language))：含量未知")) }
                                    }
                                }
                            } else if let amounts = try? event.healthSamples, !amounts.isEmpty {
                                DisclosureGroup(L10n.tr("本次营养明细")) {
                                    ForEach(amounts) { amount in
                                        Text("\(L10n.display(amount.nutrient.title))：\(amount.value * event.servings, specifier: "%.4g") \(amount.unit.rawValue)\(amount.origin == .manualEstimate || amount.origin == .aiEstimate ? L10n.tr("（估算）") : "")")
                                    }
                                }
                            }
                            if !event.product.sourceText.isEmpty {
                                DisclosureGroup(L10n.tr("数据来源")) {
                                    let generated = event.product.manualNutrition != nil || event.product.mealDetails != nil || event.product.kind == .water || event.product.id == UUID(uuidString: "77920D9C-0586-48DF-A55D-EF07DAA31E55")
                                    Text(generated ? L10n.diagnostic(event.product.sourceText) : event.product.sourceText).font(.caption)
                                }
                            }
                            Text(event.date, format: .dateTime.month().day().hour().minute()).font(.caption)
                            Text(SyncCenter.title(event)).font(.caption).foregroundStyle(.secondary)
                            if let error = event.lastError { Text(L10n.diagnostic(error)).font(.caption).foregroundStyle(.red) }
                            if event.state == .deleted || event.state == .deletionPending {
                                Button(event.state == .deleted ? L10n.tr("恢复记录") : L10n.tr("取消撤销并恢复")) {
                                    Task { do { try await store.restore(event.id) } catch { store.message = error.localizedDescription } }
                                }.buttonStyle(.borderless)
                                Text(L10n.tr("恢复原时间和数量，并重新同步 Apple 健康。"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if event.state != .deleted && event.state != .deletionPending {
                                Button(L10n.tr("撤销"), systemImage: "arrow.uturn.backward", role: .destructive) {
                                    Task { do { try await store.undo(event.id) } catch { store.message = error.localizedDescription } }
                                }
                            }
                        }
                    }
                }
            if store.library.events.isEmpty { Text(L10n.tr("还没有摄入记录")) }
            Text(L10n.tr("左滑记录可撤销；误撤销可恢复原时间与数量。"))
        }.navigationTitle(L10n.tr("记录管理")).disabled(store.busy)
        .sheet(item: $mealRequest) { MealEditor(store: store, request: $0) }
    }
}
