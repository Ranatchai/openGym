import SwiftUI

/// The app's language, chosen the way the web chooses it (`matchLocale` in
/// frontend/src/lib/default-lang.js) rather than by iOS bundle matching, which resolves
/// zh-Hant and zh-HK to English because the catalogue only has `zh`.
struct AppLanguage {
    /// `LANGS` in frontend/src/lib/i18n-core.js, in its order.
    static let supported = [
        "en", "de", "de-CH", "es", "fr", "it", "pt", "pt-BR", "pl",
        "tr", "ru", "uk", "zh", "ko", "hi", "th", "hu", "ar",
    ]
    static let rightToLeft: Set = ["ar"]

    let code: String
    private let strings: Bundle
    private let english: Bundle

    init(code: String, bundle: Bundle = .main) {
        self.code = code
        english = bundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
        strings = bundle.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? english
    }

    static func resolved() -> AppLanguage {
        AppLanguage(code: resolve(Locale.preferredLanguages))
    }

    static func resolve(_ preferred: [String]) -> String {
        preferred.lazy.compactMap(match).first ?? "en"
    }

    static func match(_ tag: String) -> String? {
        let want = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        guard !want.isEmpty else { return nil }
        if let exact = supported.first(where: { $0.lowercased() == want }) { return exact }
        let base = String(want.split(separator: "-", omittingEmptySubsequences: false)[0])
        return supported.contains(base) ? base : nil
    }

    /// Every catalogue string is a format string (`%%` for a literal percent), so lookups
    /// always pass through `String(format:)`, with or without arguments.
    func callAsFunction(_ key: String, _ arguments: any CVarArg...) -> String {
        let fallback = english.localizedString(forKey: key, value: key, table: nil)
        let format = strings.localizedString(forKey: key, value: fallback, table: nil)
        return String(format: format, arguments: arguments)
    }

    var locale: Locale { Locale(identifier: code) }

    var layoutDirection: LayoutDirection {
        Self.rightToLeft.contains(code) ? .rightToLeft : .leftToRight
    }
}

extension EnvironmentValues {
    @Entry var language = AppLanguage(code: "en")
}
