import Foundation

enum TokenEstimator {
    static func estimate(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }

        var tokenCount = 0
        var latinRunLength = 0

        for scalar in trimmed.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                tokenCount += tokensForLatinRun(latinRunLength)
                latinRunLength = 0
            } else if scalar.properties.isIdeographic {
                tokenCount += tokensForLatinRun(latinRunLength)
                latinRunLength = 0
                tokenCount += 1
            } else if CharacterSet.alphanumerics.contains(scalar) {
                latinRunLength += 1
            } else {
                tokenCount += tokensForLatinRun(latinRunLength)
                latinRunLength = 0
                tokenCount += 1
            }
        }

        tokenCount += tokensForLatinRun(latinRunLength)
        return max(tokenCount, 1)
    }

    private static func tokensForLatinRun(_ length: Int) -> Int {
        guard length > 0 else {
            return 0
        }

        return max(1, Int(ceil(Double(length) / 4.0)))
    }
}
