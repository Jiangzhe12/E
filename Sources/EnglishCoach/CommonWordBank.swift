import Foundation
import SQLite3

/// Daily-learning word bank, sourced from the bundled ECDICT database
/// (`Resources/ecdict.db`). Words are drawn from ECDICT's exam tags so the
/// deck matches a recognised, standard vocabulary list instead of a hand-rolled
/// word list:
///
/// - `coreWords` = the CET-4 list (~3.8k words) — the everyday core deck.
/// - `extendedWords` = the CET-6 list minus anything already in CET-4
///   (~1.5k extra words) — used to top up the daily quota once the core list is
///   exhausted.
///
/// Reading happens once, synchronously, on first access. When `ecdict.db` is
/// not bundled (e.g. plain `swift run` without an app bundle) both lists are
/// empty and `wordSourceAvailable` is false; the stats card surfaces that so
/// the user knows the bank is running in a degraded mode.
enum CommonWordBank {
    static var coreWords: [String] { bundle.core }
    static var extendedWords: [String] { bundle.extended }

    /// Whether the bundled `ecdict.db` was successfully read on first access.
    static var wordSourceAvailable: Bool { bundle.available }

    static var totalWordCount: Int {
        coreWords.count + extendedWords.count
    }

    static func exampleSentence(for word: String) -> String {
        let lowercased = word.lowercased()
        if commonVerbs.contains(lowercased) {
            return "I try to \(lowercased) in English every day."
        }
        if commonAdjectives.contains(lowercased) {
            return "The explanation is clear and \(lowercased)."
        }
        return "\"\(lowercased)\" is a useful word in daily English conversations."
    }

    // MARK: - Loading

    private static let bundle: (core: [String], extended: [String], available: Bool) = load()

    private static func load() -> (core: [String], extended: [String], available: Bool) {
        guard let url = Bundle.main.url(forResource: "ecdict", withExtension: "db") else {
            NSLog("[CommonWordBank] ecdict.db not bundled; word bank disabled")
            return (core: [], extended: [], available: false)
        }

        var handle: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, let db = handle else {
            NSLog("[CommonWordBank] ecdict.db open failed with status %d", status)
            if handle != nil { sqlite3_close(handle) }
            return (core: [], extended: [], available: false)
        }
        defer { sqlite3_close(db) }

        // Pull every CET-4/CET-6 single word in one pass, then classify in Swift.
        // Wrapping `tag` in spaces makes the LIKE match whole tags only, so
        // "cet4" never matches a longer tag by accident. The GLOB pair keeps the
        // result to single alphabetic words (no phrases, hyphens, or digits).
        let sql = """
        SELECT word, tag FROM stardict
        WHERE ((' ' || tag || ' ') LIKE '% cet4 %' OR (' ' || tag || ' ') LIKE '% cet6 %')
          AND word GLOB '[A-Za-z]*'
          AND word NOT GLOB '*[^A-Za-z]*'
          AND length(word) BETWEEN 2 AND 20
        ORDER BY word COLLATE NOCASE;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            NSLog("[CommonWordBank] prepare failed: %@", String(cString: sqlite3_errmsg(db)))
            return (core: [], extended: [], available: false)
        }
        defer { sqlite3_finalize(statement) }

        var core: [String] = []
        var extended: [String] = []
        var seen: Set<String> = []
        core.reserveCapacity(4000)
        extended.reserveCapacity(2000)

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let wordC = sqlite3_column_text(statement, 0) else { continue }
            let word = String(cString: wordC).lowercased()
            guard seen.insert(word).inserted else { continue }

            let tag = sqlite3_column_text(statement, 1).map { " \(String(cString: $0)) " } ?? ""
            if tag.contains(" cet4 ") {
                core.append(word)
            } else {
                extended.append(word)
            }
        }

        if core.isEmpty && extended.isEmpty {
            NSLog("[CommonWordBank] ecdict.db yielded no tagged words; word bank degraded")
            return (core: [], extended: [], available: false)
        }

        return (core: core, extended: extended, available: true)
    }

    // MARK: - Example-sentence helpers

    private static let commonVerbs: Set<String> = [
        "be", "have", "do", "say", "get", "make", "go", "know", "take", "see", "come", "think", "look",
        "want", "give", "use", "find", "tell", "ask", "work", "seem", "feel", "try", "leave", "call",
        "need", "become", "start", "play", "move", "live", "believe", "bring", "happen", "write", "sit",
        "stand", "lose", "pay", "meet", "include", "continue", "set", "learn", "change", "lead", "understand",
        "watch", "follow", "stop", "create", "speak", "read", "allow", "add", "spend", "grow", "open",
        "walk", "win", "offer", "remember", "love", "consider", "appear", "buy", "wait", "serve", "die",
        "send", "expect", "build", "stay", "fall", "cut", "reach", "kill", "raise", "pass", "sell",
        "require", "report", "decide", "pull", "return", "explain", "hope", "develop", "carry", "break",
        "receive", "agree", "support", "hit", "produce", "eat", "cover", "catch", "draw", "choose",
        "cause", "point", "listen", "realize", "place", "close", "involve", "increase", "improve", "practice"
    ]

    private static let commonAdjectives: Set<String> = [
        "good", "new", "first", "last", "long", "great", "little", "own", "other", "old", "right", "big",
        "high", "different", "small", "large", "next", "early", "young", "important", "few", "public", "bad",
        "same", "able", "clear", "full", "easy", "hard", "free", "strong", "simple", "available", "likely",
        "ready", "short", "single", "special", "whole", "best", "major", "real", "common", "main", "local",
        "sure", "human", "general", "specific", "recent", "current", "basic", "final", "happy", "serious"
    ]
}
