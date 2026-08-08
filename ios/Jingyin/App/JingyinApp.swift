import SwiftUI

@main
struct JingyinApp: App {
    @StateObject private var localization = LocalizationManager()
    @StateObject private var entitlements = EntitlementStore()

    init() {
        // SwiftUI's .tint does not reach segmented pickers; set the selected
        // segment color through the UIKit appearance proxy instead.
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(AppPalette.accent.primary)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localization)
                .environmentObject(entitlements)
                .environment(\.locale, Locale(identifier: localization.effectiveLanguageCode))
                .id(localization.effectiveLanguageCode)
                .tint(AppPalette.accent.primary)
                .task {
                    await entitlements.prepare()
                    #if DEBUG
                    LocalizationResolverSmoke.run()
                    VideoCoordinateSpaceSmoke.run()
                    MaskTrackSmoke.run()
                    PhotoProcessor.runSmokeTests()
                    FrameEffectProcessor.runStickerSmokeTest()
                    #endif
                }
        }
    }
}
