import SwiftUI
import Charts

struct NutritionDetails: View {
    @ObservedObject var store: IntakeStore
    @State private var nutrient: Nutrient = .energyConsumed
    @State private var days = 7
    @State private var date = Date()
    var body: some View {
        List {
            Section {
                DatePicker(L10n.tr("日期"), selection: $date, displayedComponents: .date)
                Picker(L10n.tr("营养素"), selection: $nutrient) { ForEach(Nutrient.allCases, id: \.self) { Text(L10n.display($0.title)).tag($0) } }
                Picker(L10n.tr("趋势"), selection: $days) { Text(L10n.tr("日")).tag(1); Text(L10n.tr("周")).tag(7); Text(L10n.tr("月")).tag(30) }.pickerStyle(.segmented)
                Chart {
                    ForEach(0..<days, id: \.self) { offset in
                        if let day = Calendar.current.date(byAdding: .day, value: offset-days+1, to: date), let value = NutritionRegistry.recorded(nutrient, events: store.library.events, date: day) {
                            BarMark(x: .value(L10n.tr("日期"), day, unit: .day), y: .value(NutritionRegistry.displayUnit(nutrient).rawValue, value)).foregroundStyle(.blue)
                        }
                    }
                }.frame(height: 150)
                Text(L10n.tr("仅显示本应用记录的已知部分；空缺不是零，也不是完整饮食总量。")).font(.caption)
            }
            ForEach(NutritionRegistry.Group.allCases, id: \.self) { group in
                Section(L10n.display(group.title)) {
                    ForEach(Nutrient.allCases.filter { NutritionRegistry.group($0) == group }, id: \.self) { nutrient in
                        VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(L10n.display(nutrient.title)) {
                            let value = NutritionRegistry.recorded(nutrient, events: store.library.events, date: date)
                            Text(value.map { $0.formatted(.number.precision(.significantDigits(1...4))) + " " + NutritionRegistry.displayUnit(nutrient).rawValue } ?? L10n.tr("未知"))
                        }
                        let coverage = NutritionRegistry.coverage(nutrient, events: store.library.events, date: date)
                        Text(L10n.tr("已知项目：\(coverage.known)/\(coverage.total)；仅代表已记录内容。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section { Text(L10n.tr("总糖不等于添加糖。当前 HealthKit 没有专用添加糖字段。资料未提供的营养保持未知。")) }
        }.navigationTitle(L10n.tr("全部营养与趋势"))
    }
}

struct FoodReferenceInformation: View {
    var body: some View {
        Form {
            Section("USDA FoodData Central") {
                Text("SR Legacy · April 2018 · 7,793 foods · CC0 1.0")
                Text("U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, 2019.")
                Link("FoodData Central", destination: URL(string: "https://fdc.nal.usda.gov/download-datasets/")!)
                Link("CC0 1.0", destination: URL(string: "https://fdc.nal.usda.gov/api-guide/")!)
            }
            Section { Text(L10n.tr("参考资料不是具体商品标签。请选择实际品种、生熟状态及可食用重量。中文别名覆盖有限，可用英文搜索；饮料需要体积标签数据或可靠重量，不能默认毫升等于克。")) }
            Section { Text(L10n.tr("RAE、DFE、食物含水量和添加糖单独保留，不套用通用质量换算写入健康。未提供的数据保持未知。")) }
        }.navigationTitle(L10n.tr("离线食物资料与许可"))
    }
}
