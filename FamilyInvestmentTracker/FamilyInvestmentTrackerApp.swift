import SwiftUI
import CoreData

@main
struct FamilyInvestmentTrackerApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var localizationManager = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(localizationManager)
                .environment(\.locale, localizationManager.locale)
        }
    }
}
