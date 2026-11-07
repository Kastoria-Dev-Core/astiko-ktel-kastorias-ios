import AVFoundation

/// Reads text out loud with the phone's own voices, in the app's language
final class Announcer {
    private let synthesizer = AVSpeechSynthesizer()

    /// The phone has a voice for the app's language. Greek read by an English voice is noise, so without
    /// one we stay quiet.
    var hasVoice: Bool { voice != nil }

    private var voice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: Strings.language == "el" ? "el-GR" : "en-GB")
    }

    /// Says `text`, cutting off whatever is being said
    func speak(_ text: String) {
        guard let voice else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    /// Goes quiet
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// What is said for a stop: its name, then up to three departures, e.g. "Στάση Αφετηρία 2. Γραμμή 4,
    /// Πανεπιστήμιο, σε 14 λεπτά." Line numbers without the leading zero, times in words a voice reads well.
    static func announcement(stopName: String, departures: [Departure], now: LocalDateTime) -> String {
        if departures.isEmpty { return L("voice_none", stopName) }
        let parts = departures.prefix(3).map { dep -> String in
            let mins = Schedule.minutesUntil(dep, now: now)
            let when: String
            if dep.dayOffset > 0 { when = L("voice_tomorrow_at", spokenTime(dep.minutes)) }
            else if mins <= 0 { when = L("voice_now") }
            else if mins < 60 { when = LP("voice_in_minutes", mins) }
            else { when = L("voice_at", spokenTime(dep.minutes)) }
            let number = String(dep.line.number.drop { $0 == "0" })
            return L("voice_departure", number.isEmpty ? "0" : number, dep.line.name.text, when)
        }
        return L("voice_intro", stopName) + " " + parts.joined(separator: " ")
    }

    private static func spokenTime(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return m % 60 == 0 ? L("voice_time_hour", m / 60) : L("voice_time", m / 60, m % 60)
    }
}
