import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHant = "zh-Hant"
    case ja
    case es

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .system: return "settings.language.option.system"
        case .en: return "settings.language.option.en"
        case .zhHant: return "settings.language.option.zh-Hant"
        case .ja: return "settings.language.option.ja"
        case .es: return "settings.language.option.es"
        }
    }

    var resolvedLocale: Locale {
        switch self {
        case .system:
            let identifier = Locale.preferredLanguages.first ?? "en"
            return Locale(identifier: identifier)
        case .en:
            return Locale(identifier: "en")
        case .zhHant:
            return Locale(identifier: "zh-Hant")
        case .ja:
            return Locale(identifier: "ja")
        case .es:
            return Locale(identifier: "es")
        }
    }
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: AppLanguage = .system
    @Published var locale: Locale = .current
    private var bundle: Bundle = .main

    private init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? AppLanguage.system.rawValue
        if let language = AppLanguage(rawValue: savedLanguage) {
            setLanguage(language, persistSelection: false)
        } else {
            loadBundle(for: .system)
        }
    }

    func setLanguage(_ language: AppLanguage, persistSelection: Bool = true) {
        currentLanguage = language

        if persistSelection {
            UserDefaults.standard.set(language.rawValue, forKey: "selectedLanguage")
        }

        loadBundle(for: language)
    }

    private func loadBundle(for language: AppLanguage) {
        switch language {
        case .system:
            bundle = .main
            locale = .autoupdatingCurrent
            return
        default:
            let identifier = language.rawValue
            if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
               let languageBundle = Bundle(path: path) {
                bundle = languageBundle
                locale = Locale(identifier: identifier)
                return
            }
        }

        bundle = .main
        locale = .autoupdatingCurrent
    }

    func localizedString(for key: String, fallback: String? = nil) -> String {
        let localizedString = bundle.localizedString(forKey: key, value: nil, table: nil)

        // If the key wasn't found in the current language bundle, try English as fallback
        if localizedString == key, currentLanguage != .en {
            if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
               let englishBundle = Bundle(path: path) {
                let englishString = englishBundle.localizedString(forKey: key, value: nil, table: nil)
                if englishString != key {
                    return englishString
                }
            }
        }

        // If still not found, return the fallback or the key itself
        return localizedString != key ? localizedString : (fallback ?? key)
    }

    func localizedString(for key: String, arguments: CVarArg...) -> String {
        let format = localizedString(for: key)
        return String(format: format, arguments: arguments)
    }
}

// SwiftUI extension for easier usage
extension LocalizationManager {
    func text(_ key: String) -> Text {
        Text(localizedString(for: key))
    }

    func text(_ key: String, arguments: CVarArg...) -> Text {
        Text(localizedString(for: key, arguments: arguments))
    }
}
