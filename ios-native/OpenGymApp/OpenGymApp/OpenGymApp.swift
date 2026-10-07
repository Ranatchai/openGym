import SwiftUI

@main
struct OpenGymApp: App {
    private let language = AppLanguage.resolved()
    private let accent = AuraAccent.launchAccent

    init() {
        AuraTheme.installLargeTitleFont()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(accent.tint)
                .environment(\.auraAccent, accent)
                .environment(\.language, language)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.layoutDirection)
        }
    }
}
