import Foundation
import WidgetKit

@MainActor enum WidgetPublisher {
    static func refresh(products: [Product]) {
        guard let url = WidgetCatalog.url else { return }
        let favorite = UserDefaults.standard.string(forKey: "widgetFavoriteID") ?? ""
        let preferredID = UUID(uuidString: favorite)
        let quantity = UserDefaults.standard.double(forKey: "widgetFavoriteQuantity")
        let selection = !favorite.isEmpty && preferredID == nil ? nil : QuickIntake.widgetSelection(products: products, preferredID: preferredID,
            quantity: quantity, expectedUnit: UserDefaults.standard.string(forKey: "widgetFavoriteUnit"))
        let items: [WidgetProduct]
        if let (selected, amount) = selection {
            items = [WidgetProduct(id: selected.id, name: selected.name, unit: selected.intakeUnitTitle, defaultQuantity: amount)]
        } else { items = [] }
        do {
            try JSONEncoder().encode(items).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Projection failure must never roll back the private, durable ingestion ledger.
            // Remove stale choices when possible. Actions still validate IDs in the main app.
            try? FileManager.default.removeItem(at: url)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
