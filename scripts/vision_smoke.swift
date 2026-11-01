// Synthetic rendered labels through the production Vision adapter. No health APIs or disk images.
// Build/run via scripts/test_vision.sh on macOS 26+ with Xcode 26+.
import AppKit
import Foundation

@main struct VisionSmoke {
    static func main() async throws {
        func emit(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }
        let en = """
        Synthetic Jamieson Omega-3 + Turmeric
        Each softgel contains:
        Fish Oil 834 mg
        Omega-3 500 mg
        EPA 300 mg
        DHA 200 mg
        Turmeric Extract 20 mg (50:1)
        Equivalent to dried herb 1,000 mg
        Recommended dose: Adults take 2 softgels daily
        """
        let zh = """
        合成测试标签
        每粒含有：
        鱼油 834 毫克
        欧米伽3 500 毫克
        EPA 300 毫克
        DHA 200 毫克
        姜黄提取物 20 毫克（50:1）
        相当于干燥草本 1,000 毫克
        建议服用：成人每天两粒
        """
        let fr = """
        Huile de poisson 834 mg
        Oméga-3 500 mg
        EPA 300 mg
        DHA 200 mg
        Extrait de curcuma 20 mg (50:1)
        Posologie – Adultes: Prendre 2 gélules
        """
        var failures = 0
        let vitaminC = """
        Each tablet contains/Chaque comprimé
        contient :
        Vitamin/Vitamine C ..
        500 mg
        (Ascorbic acid, Sodium ascorbate/
        acide ascorbique, ascorbate de sodium)
        """
        for (name, text) in [("English", en), ("Chinese", zh), ("EnglishFrench", en + "\n" + fr), ("Mixed", zh + "\n" + fr), ("VitaminCRealFailure", vitaminC)] {
            for angle in [-6.0, 0, 6] {
                let width = 1800, height = 1700
                let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                cg.setFillColor(CGColor(gray: 1, alpha: 1)); cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
                cg.translateBy(x: 900, y: 850); cg.rotate(by: angle * .pi / 180); cg.translateBy(x: -900, y: -850)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
                let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 12
                let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
                attributed.draw(in: NSRect(x: 160, y: 180, width: 1450, height: 1400))
                NSGraphicsContext.restoreGraphicsState()
                let doc = try await DocumentOCR.recognize([cg.makeImage()!])
                let label = SemanticValidator.validate(OfflineSemanticProvider.draft(doc), document: doc, provider: "offlineRules")
                var product = Product(name: "Synthetic OCR test", serving: label.serving, confirmedAt: Date())
                product.ingredients = label.ingredients; product.allowBroadMapping = true
                let plan = try HealthPlan.samples(for: product)
                let omega = plan.first { $0.nutrient == .fatPolyunsaturated }
                let accurate = name == "VitaminCRealFailure"
                    ? label.ingredients.count == 1 && plan.count == 1 && plan.first?.nutrient == .vitaminC && plan.first?.value == 500 && label.ingredients.first?.chemicalSources?.count == 2
                    : label.ingredients.first(where: { $0.canonicalID == "fishOil" })?.value == 834 && omega?.value == 500
                // Negative OCR cases must be visible and blocked, never repaired by guessing.
                let damagedName = doc.rawText.contains("欭米伽")
                let damagedBasis = doc.rawText.contains("母粒含有")
                let safelyBlocked = (damagedName || damagedBasis) && omega == nil && !label.warnings.isEmpty
                let pass = accurate || safelyBlocked
                if !pass { failures += 1 }
                emit("VISION_SMOKE \(name) angle=\(angle) engine=\(doc.engine) blocks=\(doc.blocks.count) ingredients=\(label.ingredients.count) accurate=\(accurate) safelyBlocked=\(safelyBlocked) pass=\(pass)")
                // All content here is synthetic fixture text, never a user's scanned label.
                if !pass { emit(doc.rawText); emit(String(describing: label.warnings)) }
            }
        }
        if failures > 0 { exit(1) }
    }
}
