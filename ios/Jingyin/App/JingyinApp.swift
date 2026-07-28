import SwiftUI

@main
struct JingyinApp: App {
    @StateObject private var localization = LocalizationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localization)
                .environment(\.locale, Locale(identifier: localization.effectiveLanguageCode))
                .id(localization.effectiveLanguageCode)
                .tint(.mint)
                .task {
                    #if DEBUG
                    LocalizationResolverSmoke.run()
                    #endif
                }
        }
    }
}
