import Foundation

/// Picks one of four languages by plain lookup, not full automatic bundle
/// localization: this app supports exactly these languages, so matching the
/// system to one of them (or falling back to English) is a bounded choice,
/// not a general fallback-resolution problem.
///
/// This is a plain Swift lookup table rather than .strings resources: the
/// app's build script hand-assembles the .app bundle from the raw compiled
/// binary and doesn't copy SwiftPM's generated resource bundles, so
/// `Bundle.module` string lookups would silently fail to load at runtime.
public enum L {
    public enum Language: String, CaseIterable, Sendable {
        case system
        case korean
        case english
        case japanese
        case chinese
    }

    private static let preferenceKey = "TokenGauge.languagePreference"

    /// Persisted so a manual choice survives a relaunch. Defaults to
    /// following the system, which is the behavior before this setting
    /// existed.
    public static var languagePreference: Language {
        get {
            UserDefaults.standard.string(forKey: preferenceKey)
                .flatMap(Language.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
        }
    }

    /// Never `.system` — resolves to one of the four concrete languages,
    /// matched off the system's preferred language when following it.
    public static var resolved: Language {
        let preference = languagePreference
        guard preference == .system else { return preference }

        let code = Locale.preferredLanguages.first ?? ""
        if code.hasPrefix("ko") { return .korean }
        if code.hasPrefix("ja") { return .japanese }
        if code.hasPrefix("zh") { return .chinese }
        return .english
    }

    /// The locale used for formatting (relative dates, numbers) to match
    /// the chosen display language, rather than whatever the system's exact
    /// region settings are — a German system forced to English should still
    /// get English-formatted dates, not German ones mixed into English text.
    public static var formattingLocale: Locale {
        switch resolved {
        case .korean: return Locale(identifier: "ko_KR")
        case .japanese: return Locale(identifier: "ja_JP")
        case .chinese: return Locale(identifier: "zh_CN")
        case .english, .system: return Locale(identifier: "en_US")
        }
    }

    public static func t(ko: String, en: String, ja: String, zh: String) -> String {
        switch resolved {
        case .korean: return ko
        case .japanese: return ja
        case .chinese: return zh
        case .english, .system: return en
        }
    }
}
