import SwiftUI

@main
struct JingyinApp: App {
    @StateObject private var localization = LocalizationManager()
    @StateObject private var entitlements = EntitlementStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localization)
                .environmentObject(entitlements)
                .environment(\.locale, Locale(identifier: localization.effectiveLanguageCode))
                .id(localization.effectiveLanguageCode)
                .tint(.mint)
                .task {
                    await entitlements.prepare()
                    #if DEBUG
                    LocalizationResolverSmoke.run()
                    VideoCoordinateSpaceSmoke.run()
                    MaskTrackSmoke.run()
                    #endif
                }
        }
    }
}
