import Foundation

/// Heurísticas para no almacenar secretos evidentes en el histórico.
enum SensitiveContentDetector {
    private static let patterns: [NSRegularExpression] = [
        "AKIA[0-9A-Z]{16}",                                            // AWS access key
        "-----BEGIN [A-Z ]*PRIVATE KEY-----",                          // claves privadas
        "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}", // JWT
        "gh[pousr]_[A-Za-z0-9]{30,}",                                  // GitHub tokens
        "xox[baprs]-[A-Za-z0-9-]{10,}",                                // Slack tokens
        "sk-[A-Za-z0-9]{20,}",                                         // API keys estilo OpenAI
        "(?i)(password|passwd|pwd|secret|api[_-]?key|token|bearer)\\s*[:=]\\s*\\S{6,}",
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let cardPattern = try! NSRegularExpression(pattern: "\\b(?:\\d[ -]?){13,19}\\b")

    static func isSensitive(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for p in patterns where p.firstMatch(in: text, range: range) != nil {
            return true
        }
        for m in cardPattern.matches(in: text, range: range) {
            guard let r = Range(m.range, in: text) else { continue }
            let digits = text[r].filter(\.isNumber)
            if digits.count >= 13, luhnValid(digits) { return true }
        }
        return false
    }

    private static func luhnValid(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
        }
        return sum % 10 == 0
    }
}
