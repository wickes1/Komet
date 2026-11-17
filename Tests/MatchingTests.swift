import Testing
@testable import Komet

/// Ranks names the way the launcher's list does, best first.
private func ranked(_ query: String, _ apps: [(String, Bool)]) -> [String] {
    apps.compactMap { name, running in matchScore(query, name: name, running: running).map { (name, $0) } }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lowercased() < $1.0.lowercased() }
        .map(\.0)
}

private let installed: [(String, Bool)] = [
    ("Activity Monitor", false), ("BetterDisplay", true), ("Calculator", false), ("Calendar", false),
    ("Claude Code URL Handler", false), ("Code", true), ("Console", false), ("Digital Color Meter", false),
    ("Mail", false), ("Maps", false), ("Automator", false), ("Image Capture", false), ("Microsoft Teams", true),
    ("Notes", false), ("Photos", false), ("Amphetamine", true), ("Terminal", false), ("Visual Studio Code", false),
]

@Suite struct Ranking {
    // The point of a launcher: a few letters from the start of an app's name put that app first,
    // even when other names merely contain those letters ("te" in BetterDisplay, Microsoft Teams).
    @Test func nameStartBeatsLettersElsewhere() {
        #expect(ranked("te", installed).first == "Terminal")
        #expect(ranked("ph", installed).first == "Photos")
        #expect(Array(ranked("ma", installed).prefix(2)) == ["Mail", "Maps"])
    }

    // "c" must not open on Activity Monitor: every name that starts with c comes before names that only contain one.
    @Test func everyPrefixMatchBeforeAnySubstringMatch() {
        let result = ranked("c", installed)
        let lastPrefix = result.lastIndex { $0.lowercased().hasPrefix("c") }!
        let firstOther = result.firstIndex { !$0.lowercased().hasPrefix("c") }!
        #expect(lastPrefix < firstOther)
    }

    // Among equally good matches the app already running is the likelier target.
    @Test func runningAppWinsATie() {
        #expect(ranked("co", installed).first == "Code")
    }

    // A word inside the name counts, and so do the initials of its words.
    @Test func wordStartsAndInitialsMatch() {
        #expect(ranked("teams", installed).first == "Microsoft Teams")
        #expect(ranked("vsc", installed).first == "Visual Studio Code")
        #expect(ranked("display", installed).first == "BetterDisplay")
    }

    // Typos of missing letters still find the app, below every closer match.
    @Test func lettersInOrderStillMatch() {
        #expect(ranked("trml", installed) == ["Terminal"])
        #expect(matchScore("zzz", name: "Terminal", running: false) == nil)
    }

    @Test func wordsSplitAtSpacesPunctuationAndCamelCase() {
        #expect(words(of: "BetterDisplay") == ["better", "display"])
        #expect(words(of: "Claude Code URL Handler") == ["claude", "code", "url", "handler"])
        #expect(words(of: "BaiduNetdisk_mac") == ["baidu", "netdisk", "mac"])
    }
}
