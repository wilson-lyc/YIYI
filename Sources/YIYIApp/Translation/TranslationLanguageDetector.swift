import NaturalLanguage

enum TranslationLanguageDetector {
    static func defaultTargetLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        switch recognizer.dominantLanguage {
        case .simplifiedChinese, .traditionalChinese:
            return "英语"
        default:
            return "简体中文"
        }
    }
}
