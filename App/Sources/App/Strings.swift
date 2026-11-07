import Foundation

/// The app's text in Greek and English, from strings.json (made by scripts/import_strings.py from the
/// Android app's strings.xml, so both apps say the same thing). The language is the app's own, picked in
/// Settings, not only the phone's: the root view is rebuilt when it changes.
enum Strings {
    /// "el" or "en"
    static var language = "el"

    private struct File: Decodable {
        let en: [String: String]
        let el: [String: String]
        let plurals: [String: [String: [String: String]]]
        let arrays: [String: [String: [String]]]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "strings", withExtension: "json"),
              let bytes = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: bytes)
    }()

    /// The text for `key` in the current language, English when there's no Greek, the key when neither
    static func text(_ key: String) -> String {
        guard let file else { return key }
        let table = language == "el" ? file.el : file.en
        return table[key] ?? file.en[key] ?? key
    }

    /// One of a few forms by number, like Android's plurals: "one" for 1, "other" for the rest
    static func plural(_ key: String, _ count: Int) -> String {
        let forms = file?.plurals[language]?[key] ?? file?.plurals["en"]?[key] ?? [:]
        let form = (count == 1 ? forms["one"] : nil) ?? forms["other"] ?? key
        return fill(form, [count])
    }

    /// A list, e.g. the contributors' names
    static func array(_ key: String) -> [String] {
        file?.arrays[language]?[key] ?? file?.arrays["en"]?[key] ?? []
    }

    private static let placeholder = try! NSRegularExpression(pattern: "%(\\d+)\\$(0?)(\\d*)([sd])")

    /// Puts the arguments in Android's placeholders: %1$s, %2$d, and %2$02d with zero padding
    static func fill(_ format: String, _ args: [Any]) -> String {
        let ns = format as NSString
        var out = ""
        var last = 0
        for match in placeholder.matches(in: format, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let index = Int(ns.substring(with: match.range(at: 1)))! - 1
            let zero = ns.substring(with: match.range(at: 2)) == "0"
            let width = Int(ns.substring(with: match.range(at: 3))) ?? 0
            var value = index < args.count ? "\(args[index])" : ""
            if zero && value.count < width { value = String(repeating: "0", count: width - value.count) + value }
            out += value
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}

/// The text for `key`, with its placeholders filled in: `L("towards", headsign)`
func L(_ key: String, _ args: Any...) -> String {
    let text = Strings.text(key)
    return args.isEmpty ? text : Strings.fill(text, args)
}

/// The form of `key` for `count`: `LP("buses_on_route", 3)` is "3 buses"
func LP(_ key: String, _ count: Int) -> String {
    Strings.plural(key, count)
}

extension Localized {
    /// The text in the app's language
    var text: String { self.get(Strings.language) }
}

extension Stop {
    /// A stop's name as shown where it's picked or opened: "Αφετηρία (αναχωρήσεις)" when it has a qualifier
    var title: String {
        let base = name.text
        guard let extra = qualifier?.text else { return base }
        // An English name that already ends in brackets gets "(Terminal, departures)"
        if base.hasSuffix(")") { return "\(base.dropLast()), \(extra))" }
        return "\(base) (\(extra))"
    }
}

extension ServiceDay {
    /// The name of this kind of day, e.g. "Weekdays"
    var label: String {
        switch self {
        case .weekday: return L("weekday")
        case .saturday: return L("saturday")
        case .sunday: return L("sunday")
        case .wednesday: return L("wednesday")
        }
    }
}

extension Season {
    var label: String { self == .winter ? L("winter") : L("summer") }
}

/// The locale for dates, following the app's language
var appLocale: Locale { Locale(identifier: Strings.language == "el" ? "el_GR" : "en_GB") }
