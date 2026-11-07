import Foundation

/// Searching stops and lines by name in Greek, English or Greeklish, with or without accents.
/// The same rules as the Android app's Search.kt.
enum Search {
    private static let stopWords: Set<String> = ["σταση", "στασεισ", "stop", "stops"]
    private static let lineWords: Set<String> = ["γραμμη", "γραμμεσ", "line", "lines", "λεωφορειο", "bus"]
    private static let greekSuffixes = ["ιου", "εως", "εων", "ουσ", "ου", "ησ", "ασ", "οσ", "ων", "εσ", "ει", "α", "η", "ο", "υ", "σ"]

    /// Strips accents, lower-cases, and unifies Greek final sigma
    static func normalize(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "el"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "el"))
            .replacingOccurrences(of: "ς", with: "σ")
    }

    /// Transliterates Greek text into a phonetic Latin form, so Greeklish finds Greek names
    static func phonetic(_ s: String) -> String {
        var res = normalize(s)
        for (a, b) in [("αι", "e"), ("ει", "i"), ("οι", "i"), ("ου", "u"), ("αυ", "av"), ("ευ", "ev"), ("μπ", "b"),
                       ("ντ", "nt"), ("γκ", "gk"), ("γγ", "ng"), ("τσ", "ts"), ("τζ", "tz")] {
            res = res.replacingOccurrences(of: a, with: b)
        }
        let letters: [Character: String] = [
            "α": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "i", "θ": "th", "ι": "i", "κ": "k",
            "λ": "l", "μ": "m", "ν": "n", "ξ": "x", "ο": "o", "π": "p", "ρ": "r", "σ": "s", "τ": "t", "υ": "i",
            "φ": "f", "χ": "ch", "ψ": "ps", "ω": "o",
        ]
        var out = res.map { letters[$0] ?? String($0) }.joined()
        for (a, b) in [("ou", "u"), ("ei", "i"), ("oi", "i"), ("ai", "e"), ("y", "i"), ("c", "k"), ("w", "o"), ("ph", "f")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out
    }

    /// Strips common Greek endings (e.g. genitive -ου, -ης)
    static func stem(_ s: String) -> String {
        let norm = normalize(s)
        for suffix in greekSuffixes where norm.hasSuffix(suffix) && norm.count - suffix.count >= 3 {
            return String(norm.dropLast(suffix.count))
        }
        return norm
    }

    /// Splits the query into words, leaving out filler words like "στάση" when there are others
    private static func tokens(_ query: String, ignoring words: Set<String>) -> [String] {
        let raw = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if raw.count > 1 {
            let filtered = raw.filter { !words.contains(normalize($0)) }
            if !filtered.isEmpty { return filtered }
        }
        return raw
    }

    /// Stops whose Greek or English name, qualifier or Greeklish form match every word, best first
    static func stops(_ stops: [Stop], _ query: String, language: String) -> [Stop] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let words = tokens(trimmed, ignoring: stopWords)
        if words.isEmpty { return [] }
        let fullNorm = normalize(trimmed)
        let fullPhonetic = phonetic(trimmed)

        var matched: [(stop: Stop, rank: Int, name: String)] = []
        for stop in stops {
            var raw = [stop.name.el, stop.name.en]
            if let q = stop.qualifier { raw += [q.el, q.en, stop.name.el + " " + q.el, stop.name.en + " " + q.en] }
            let norm = raw.map(normalize)
            let phon = raw.map(phonetic)
            let stems = norm.map(stem)
            let all = words.allSatisfy { word in
                let n = normalize(word)
                let p = phonetic(word)
                let s = stem(n)
                return norm.contains { $0.contains(n) } || phon.contains { $0.contains(p) } || stems.contains { $0.contains(s) }
                    || (s.count >= 3 && stems.contains { $0.hasPrefix(s) || s.hasPrefix($0) })
            }
            guard all else { continue }
            let rank: Int
            if norm.contains(fullNorm) { rank = 0 }
            else if norm.contains(where: { $0.hasPrefix(fullNorm) }) { rank = 1 }
            else if phon.contains(where: { $0.hasPrefix(fullPhonetic) }) { rank = 2 }
            else { rank = 3 }
            matched.append((stop: stop, rank: rank, name: stop.name.get(language)))
        }
        return matched.sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }.map(\.stop)
    }

    /// Lines by number ("4", "04", "γραμμή 4") or by name, best first
    static func lines(_ lines: [Line], _ query: String) -> [Line] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let words = tokens(trimmed, ignoring: lineWords)
        if words.isEmpty { return [] }
        let clean = words.joined(separator: " ")
        let fullNorm = normalize(clean)
        let fullPhonetic = phonetic(clean)

        var matched: [(line: Line, rank: Int, number: Int)] = []
        for line in lines {
            let bare = String(line.id.drop { $0 == "0" })
            let number = Int(line.id) ?? 999
            if fullNorm == bare || fullNorm == line.id || words.contains(where: { normalize($0) == bare || normalize($0) == line.id }) {
                matched.append((line: line, rank: 0, number: number))
                continue
            }
            let names = [normalize(line.name.el), normalize(line.name.en), phonetic(line.name.el), phonetic(line.name.en)]
            let all = words.allSatisfy { word in
                let n = normalize(word)
                let p = phonetic(word)
                return names.contains { $0.contains(n) || $0.contains(p) }
            }
            if all {
                let rank = names.contains { $0.hasPrefix(fullNorm) || $0.hasPrefix(fullPhonetic) } ? 1 : 2
                matched.append((line: line, rank: rank, number: number))
            }
        }
        return matched.sorted { ($0.rank, $0.number) < ($1.rank, $1.number) }.map(\.line)
    }
}
