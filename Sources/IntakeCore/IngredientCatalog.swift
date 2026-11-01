import Foundation

/// Stable internal IDs; packaging aliases and interface names are separate concerns.
public enum IngredientCatalog {
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter { $0.isLetter || $0.isNumber }
    }
    public static let aliases: [String: [String]] = {
        var values: [String: [String]] = [
        "fishOil": ["Fish Oil", "Huile de poisson", "鱼油", "魚油", "フィッシュオイル", "어유", "Aceite de pescado", "Fischöl"],
        "omega3": ["Omega-3", "Oméga-3", "Omega-3 fatty acids", "欧米伽3", "ω3", "オメガ3", "오메가3", "Ácidos grasos omega-3"],
        "epa": ["EPA", "Eicosapentaenoic acid", "Acide eicosapentaénoïque", "二十碳五烯酸"],
        "dha": ["DHA", "Docosahexaenoic acid", "Acide docosahexaénoïque", "二十二碳六烯酸"],
        "turmericExtract": ["Turmeric Extract", "Turmeric root extract", "Extrait de curcuma", "姜黄提取物", "姜黄萃取物", "ウコンエキス", "강황 추출물", "Extracto de cúrcuma", "Kurkumaextrakt"],
        "dryHerbEquivalent": ["Equivalent to dried herb", "Equivalent to dry herb", "Équivalent à l'herbe séchée", "Équivalent en herbe sèche", "相当于干燥草本", "等效于干燥草本", "干燥草本等效量", "乾燥ハーブ相当量"],
        "thiamin": ["Vitamin B1", "Vitamine B1", "Thiamin", "Thiamine", "维生素B1", "硫胺素", "ビタミンB1", "티아민", "Vitamina B1"],
        "vitaminD": ["Vitamin D", "Vitamin D2", "Vitamin D3", "Vitamine D2", "Vitamine D3", "维生素D2", "维生素D3", "Vitamine D", "维生素D", "ビタミンD", "비타민D", "Vitamina D"],
        "calcium": ["Calcium", "钙", "カルシウム", "칼슘", "Calcio", "Kalzium"],
        "fatPolyunsaturated": ["Polyunsaturated fat", "多不饱和脂肪", "Gras polyinsaturés"],
        "fatTotal": ["Total fat", "总脂肪", "Lipides", "Gras totaux"],
        "fiber": ["Dietary fiber", "Dietary fibre", "Fiber", "Fibre", "膳食纤维", "Fibres alimentaires"],
        "fatMonounsaturated": ["Monounsaturated fat", "单不饱和脂肪"],
        "fatSaturated": ["Saturated fat", "饱和脂肪"],
        "sugar": ["Sugar", "Sugars", "糖", "Sucres"],
        "water": ["Water", "Eau", "饮水", "水", "Agua", "Wasser"],
        "energyConsumed": ["Energy", "Calories", "Énergie", "能量", "热量", "Energía", "Energie"]
    ]
        // Reviewed linguistic aliases, never chemical-equivalence or mass-conversion rules.
        let localized: [String: [String]] = [
            "vitaminA": ["Vitamin A", "Vitamine A", "Vitamina A", "ビタミンA", "비타민A"],
            "vitaminC": ["Vitamin C", "Vitamine C", "Vitamina C", "ビタミンC", "비타민C"],
            "vitaminE": ["Vitamin E", "Vitamine E", "Vitamina E", "ビタミンE", "비타민E"],
            "vitaminK": ["Vitamin K", "Vitamine K", "Vitamina K", "ビタミンK", "비타민K"],
            "vitaminB6": ["Vitamin B6", "Vitamine B6", "Vitamina B6", "ビタミンB6", "비타민B6"],
            "vitaminB12": ["Vitamin B12", "Vitamine B12", "Vitamina B12", "ビタミンB12", "비타민B12"],
            "riboflavin": ["Riboflavin", "Riboflavine", "Riboflavina", "リボフラビン", "리보플라빈", "Vitamin B2", "核黄素"],
            "niacin": ["Niacin", "Niacine", "Niacina", "ナイアシン", "나이아신", "Vitamin B3"],
            "folate": ["Folate", "Folates", "Folato", "Folsäure", "葉酸", "엽산"],
            "biotin": ["Biotin", "Biotine", "Biotina", "ビオチン", "비오틴"],
            "pantothenicAcid": ["Pantothenic acid", "Acide pantothénique", "Ácido pantoténico", "Pantothensäure", "パントテン酸", "판토텐산", "Vitamin B5"],
            "caffeine": ["Caffeine", "Caféine", "Cafeína", "Koffein", "カフェイン", "카페인"],
            "carbohydrates": ["Carbohydrate", "Carbohydrates", "Glucides", "Hidratos de carbono", "Kohlenhydrate", "炭水化物", "탄수화물"],
            "chloride": ["Chloride", "Chlorure", "Cloruro", "Chlorid", "塩化物", "염화물"],
            "cholesterol": ["Cholesterol", "Cholestérol", "Colesterol", "Cholesterin", "コレステロール", "콜레스테롤"],
            "phosphorus": ["Phosphorus", "Phosphore", "Fósforo", "Phosphor", "リン", "인"],
            "protein": ["Protein", "Protéines", "Proteína", "Eiweiß", "たんぱく質", "단백질"],
            "iron": ["Iron", "Fer", "Hierro", "Eisen", "鉄", "철"],
            "magnesium": ["Magnesium", "Magnésium", "Magnesio", "マグネシウム", "마그네슘"],
            "zinc": ["Zinc", "Zink", "亜鉛", "아연"],
            "selenium": ["Selenium", "Sélénium", "Selenio", "Selen", "セレン", "셀레늄"],
            "copper": ["Copper", "Cuivre", "Cobre", "Kupfer", "銅", "구리"],
            "manganese": ["Manganese", "Manganèse", "Manganeso", "Mangan", "マンガン", "망간"],
            "chromium": ["Chromium", "Chrome", "Cromo", "Chrom", "クロム", "크롬"],
            "molybdenum": ["Molybdenum", "Molybdène", "Molibdeno", "Molybdän", "モリブデン", "몰리브덴"],
            "iodine": ["Iodine", "Iode", "Yodo", "Jod", "ヨウ素", "요오드"],
            "potassium": ["Potassium", "Potasio", "Kalium", "カリウム", "칼륨"],
            "sodium": ["Sodium", "Sodio", "Natrium", "ナトリウム", "나트륨"],
            "fatTotal": ["Fat", "Total fat", "Lipides", "Gras totaux", "Grasa total", "Fett", "脂質", "지방"],
            "fatPolyunsaturated": ["Polyunsaturated fat", "Gras polyinsaturés", "Grasas poliinsaturadas", "Mehrfach ungesättigte Fettsäuren", "多価不飽和脂肪酸", "다중불포화지방"],
            "fatMonounsaturated": ["Monounsaturated fat", "Gras monoinsaturés", "Grasas monoinsaturadas", "Einfach ungesättigte Fettsäuren", "一価不飽和脂肪酸", "단일불포화지방"],
            "fatSaturated": ["Saturated fat", "Gras saturés", "Grasas saturadas", "Gesättigte Fettsäuren", "飽和脂肪酸", "포화지방"],
            "fiber": ["Dietary fiber", "Fibres alimentaires", "Fibra alimentaria", "Ballaststoffe", "食物繊維", "식이섬유"],
            "sugar": ["Sugar", "Sugars", "Sucres", "Azúcares", "Zucker", "糖類", "당류"]
        ]
        for (id, names) in localized { values[id] = (values[id] ?? names.prefix(1).map { $0 }) + names.filter { !(values[id] ?? []).contains($0) } }
        // English display text is deterministic and independent from dictionary/set ordering.
        return values
    }()
    public static func resolve(_ name: String) -> String? {
        let key = normalized(name)
        for (id, names) in aliases where names.contains(where: { normalized($0) == key }) { return id }
        for nutrient in Nutrient.allCases where normalized(nutrient.rawValue) == key || normalized(nutrient.title) == key { return nutrient.rawValue }
        // Generic vitamin prefixes are linguistic aliases, not chemical-form equivalences.
        for prefix in ["vitamine", "vitamina", "vitamin", "维生素", "ビタミン", "비타민"] where key.hasPrefix(normalized(prefix)) {
            let suffix = String(key.dropFirst(normalized(prefix).count))
            let names = ["a":"vitaminA", "c":"vitaminC", "d":"vitaminD", "e":"vitaminE", "k":"vitaminK", "b1":"thiamin", "b2":"riboflavin", "b3":"niacin", "b5":"pantothenicAcid", "b6":"vitaminB6", "b12":"vitaminB12"]
            if let id = names[suffix] { return id }
        }
        return LabelNameEvidence.sharedVitamin(name)
    }
    public static func title(_ id: String?, original: String, language: String = "zh") -> String {
        guard let id else { return original }
        let chinese = ["fishOil":"鱼油", "omega3":"Omega-3", "epa":"EPA", "dha":"DHA", "turmericExtract":"姜黄提取物", "dryHerbEquivalent":"干燥草本等效量"]
        if language.hasPrefix("zh") { return chinese[id] ?? Nutrient(rawValue: id)?.title ?? original }
        return aliases[id]?.first ?? Nutrient(rawValue: id).map { $0.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized } ?? original
    }
}
