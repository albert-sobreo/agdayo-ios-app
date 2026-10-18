import Foundation
import NaturalLanguage
import Observation
import Translation

/// Which language a place name or address is in, when it isn't English.
/// Pure and framework-light so it can be unit tested.
enum NameLanguage {

    /// The source language to translate `text` from, or `nil` when it's
    /// English, too short to tell, or a Latin-script name that is probably
    /// just a proper noun ("Toyo Eatery", "Pat-Pat's Kansi").
    static func sourceLanguage(for text: String) -> Locale.Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage,
              language != .english, language != .undetermined else { return nil }

        // Other scripts (Chinese, Japanese, Korean, Thai, Arabic, Cyrillic…)
        // are always worth translating.
        if hasNonLatinLetters(trimmed) {
            return Locale.Language(identifier: language.rawValue)
        }

        // Latin script: only when the recognizer is quite sure and there's
        // enough text for that to mean something ("Marché aux Puces").
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        let words = trimmed.split(whereSeparator: \.isWhitespace).count
        if confidence >= 0.85 && words >= 2 {
            return Locale.Language(identifier: language.rawValue)
        }
        return nil
    }

    static func hasNonLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            // Beyond Latin Extended-B: Greek, Cyrillic, Hebrew, Arabic, Thai, CJK, Hangul…
            scalar.value > 0x024F && scalar.properties.isAlphabetic
        }
    }
}

/// Adds an English translation next to place names and addresses that aren't
/// in English, using Apple's on-device Translation framework (free, works
/// offline once a language pack is installed; iOS asks to download one the
/// first time it's needed).
///
/// A translation session handles one source language and only lives inside a
/// SwiftUI `.translationTask`, so texts are grouped by language and each
/// group is translated in turn by publishing a new `configuration`.
@MainActor
@Observable
final class PlaceTranslator {

    /// Original text -> English. Only holds translations that differ.
    private(set) var english: [String: String] = [:]

    /// Bind to `.translationTask(translator.configuration)`.
    private(set) var configuration: TranslationSession.Configuration?

    private var requested: Set<String> = []
    private var queue: [(language: Locale.Language, texts: [String])] = []
    private var currentTexts: [String] = []

    private static let target = Locale.Language(identifier: "en")

    /// The English version of `text`, if it needed and got one.
    func translation(of text: String?) -> String? {
        guard let text, let value = english[text] else { return nil }
        return value
    }

    /// Queues any texts that aren't English and haven't been looked at yet.
    func request(_ texts: [String]) {
        var byLanguage: [String: (language: Locale.Language, texts: [String])] = [:]
        for text in Set(texts) where !requested.contains(text) {
            requested.insert(text)
            guard let language = NameLanguage.sourceLanguage(for: text) else { continue }
            let id = language.minimalIdentifier
            byLanguage[id, default: (language, [])].texts.append(text)
        }
        guard !byLanguage.isEmpty else { return }

        Task {
            let availability = LanguageAvailability()
            for (_, group) in byLanguage {
                // Skip languages the framework can't translate to English.
                let status = await availability.status(from: group.language, to: Self.target)
                guard status != .unsupported else { continue }
                queue.append((group.language, group.texts))
            }
            startNextIfIdle()
        }
    }

    /// Run by `.translationTask` for the current configuration.
    func translate(using session: TranslationSession) async {
        let texts = currentTexts
        let requests = texts.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                let original = response.clientIdentifier ?? response.sourceText
                let translated = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Names that translate to themselves add nothing.
                if !translated.isEmpty,
                   translated.caseInsensitiveCompare(original) != .orderedSame {
                    english[original] = translated
                }
            }
        } catch {
            // The person declined a download, or the pair isn't available:
            // leave these in their original language.
        }
        configuration = nil
        currentTexts = []
        // Next group on the next turn, so the new configuration is seen as a change.
        Task { startNextIfIdle() }
    }

    private func startNextIfIdle() {
        guard configuration == nil, currentTexts.isEmpty, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        currentTexts = next.texts
        configuration = TranslationSession.Configuration(source: next.language, target: Self.target)
    }
}
