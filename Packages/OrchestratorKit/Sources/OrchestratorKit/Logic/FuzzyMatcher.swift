import Foundation

/// Fuzzy matching (Shortcuts' site search): every query token has to match the text, so
/// "ci net" finds "citynet.ge". Tokens may come in any order.
///
/// Per token, the best of:
/// - prefix of a word ("dep" in "Deploy"), best;
/// - contiguous substring ("net" in "citynet");
/// - in-order subsequence ("cnt" in "citynet"), weakest, rewarding consecutive runs.
public enum FuzzyMatcher {
    /// `nil` when the text does not match. Higher is better. An empty query matches with 0.
    public static func score(_ query: String, in text: String) -> Double? {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return 0 }
        let haystack = text.lowercased()
        let words = Self.words(in: haystack)

        var total = 0.0
        for token in tokens {
            guard let tokenScore = score(token: token, haystack: haystack, words: words) else { return nil }
            total += tokenScore
        }
        // Prefer shorter texts slightly, so "Deploy a" beats "Deploy a-very-long-name".
        return total - Double(haystack.count) * 0.01
    }

    private static func score(token: String, haystack: String, words: [(offset: Int, word: Substring)]) -> Double? {
        let length = Double(token.count)

        for (index, entry) in words.enumerated() where entry.word.hasPrefix(token) {
            // Earlier words (the verb) weigh a little more; a full-word match more still.
            let fullWord = entry.word.count == token.count ? 2.0 : 0
            return 10 + length * 2 + fullWord - Double(index) * 0.1
        }
        if haystack.contains(token) {
            return 5 + length
        }
        return subsequenceScore(token, in: haystack)
    }

    private static func subsequenceScore(_ token: String, in haystack: String) -> Double? {
        var score = 0.0
        var run = 0
        var position = haystack.startIndex
        for character in token {
            guard let found = haystack[position...].firstIndex(of: character) else { return nil }
            run = found == position ? run + 1 : 1
            score += Double(run)
            position = haystack.index(after: found)
        }
        return 1 + score * 0.5
    }

    /// Words split on spaces and punctuation, keeping dots inside domains together as
    /// separate words too: "citynet.ge" yields "citynet.ge", "citynet" and "ge".
    private static func words(in text: String) -> [(offset: Int, word: Substring)] {
        var result: [(Int, Substring)] = []
        let separators: (Character) -> Bool = { $0.isWhitespace || "·,:/()".contains($0) }
        for chunk in text.split(whereSeparator: separators) {
            let offset = text.distance(from: text.startIndex, to: chunk.startIndex)
            result.append((offset, chunk))
            let parts = chunk.split(whereSeparator: { ".-_".contains($0) })
            if parts.count > 1 {
                for part in parts {
                    result.append((text.distance(from: text.startIndex, to: part.startIndex), part))
                }
            }
        }
        return result.sorted { $0.0 < $1.0 }.map { (offset: $0.0, word: $0.1) }
    }
}
