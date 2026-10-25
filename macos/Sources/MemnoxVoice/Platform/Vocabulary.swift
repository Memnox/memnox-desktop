import CryptoKit
import Foundation
import MemnoxVoiceCore
import Speech

/// A language model taught the names people say about their agents, built on this Mac from the
/// recognizer hints, so "Claude Code" is heard rather than "clothes code". A hint only nudges the
/// recognizer; a trained model changes which words it expects, and how the odd ones sound.
/// Like the hints it only helps the recognizer hear a word, and nothing acts on one.
enum Vocabulary {
    /// The trained model once it is built, for every recognizer that can take one; nil until then.
    nonisolated(unsafe) static private(set) var trained: SFSpeechLanguageModel.Configuration?
    /// The language the model was trained in, which a recognizer using it has to match.
    nonisolated(unsafe) static private(set) var locale = Locale(identifier: fallbackLocale)

    /// Builds the model in the background, reusing the last one when the names have not changed.
    static func train(names: [String]) async {
        let locale = SFSpeechRecognizer(locale: Locale.current)?.locale ?? Locale(identifier: fallbackLocale)
        guard let folder = folder() else { return }
        let names = Array(Set(names + taughtAgents)).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.sorted()
        let digest = digest(of: names, locale: locale)
        let training = folder.appendingPathComponent(File.training)
        let configuration = SFSpeechLanguageModel.Configuration(
            languageModel: folder.appendingPathComponent(File.model),
            vocabulary: folder.appendingPathComponent(File.vocabulary)
        )
        let digestFile = folder.appendingPathComponent(File.digest)
        let built = FileManager.default.fileExists(atPath: configuration.languageModel.path)
        if built, (try? String(contentsOf: digestFile, encoding: .utf8)) == digest {
            use(configuration, in: locale)
            return
        }
        do {
            try await data(names: names, locale: locale).export(to: training)
            try await prepare(training, configuration)
            try digest.write(to: digestFile, atomically: true, encoding: .utf8)
            use(configuration, in: locale)
            diary.note("trained the recognizer on \(names.count) names")
        } catch {
            diary.note("could not train the recognizer on names: \(error.localizedDescription)")
        }
    }

    private static func use(_ configuration: SFSpeechLanguageModel.Configuration, in locale: Locale) {
        self.locale = locale
        trained = configuration
    }

    private static func data(names: [String], locale: Locale) -> SFCustomLanguageModelData {
        let data = SFCustomLanguageModelData(locale: locale, identifier: identifier, version: version)
        // Spelled out phrase by phrase rather than through a template, whose count is shared among every
        // name in its slot, so with a few hundred names each one was taught about once and never expected.
        for taught in taughtNamePhrases(names: names) {
            data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: taught.phrase, count: taught.count))
        }
        // Memnox's own words and requests go in as they are said.
        for (phrase, count) in SpokenTerms.phrases + SpokenTerms.terms.map({ ($0, termCount) }) {
            data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count))
        }
        // A pronunciation with a sound the recognizer does not know would fail the whole model, so it is left out.
        let known = Set(SFCustomLanguageModelData.supportedPhonemes(locale: locale))
        for pronunciation in taughtPronunciations {
            guard pronunciation.readable(by: known) else {
                diary.note("left out a pronunciation of \(pronunciation.grapheme) the recognizer cannot read: \(pronunciation.phonemes)")
                continue
            }
            data.insert(term: SFCustomLanguageModelData.CustomPronunciation(
                grapheme: pronunciation.grapheme, phonemes: [pronunciation.phonemes]))
        }
        return data
    }

    private static func prepare(_ training: URL, _ configuration: SFSpeechLanguageModel.Configuration) async throws {
        if #available(macOS 26, *) {
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: training, configuration: configuration, ignoresCache: true)
        } else {
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: training, clientIdentifier: identifier, configuration: configuration, ignoresCache: true)
        }
    }

    /// Changes whenever the names or the language do, which is when the model is built again.
    private static func digest(of names: [String], locale: Locale) -> String {
        let source = ([version, locale.identifier] + names).joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: hexByte, $0) }.joined()
    }

    /// Under Application Support with the history, made the first time.
    private static func folder() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent(appFolder).appendingPathComponent(modelFolder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            diary.note("could not make the vocabulary folder: \(error.localizedDescription)")
            return nil
        }
    }

    private enum File {
        static let training = "names.bin"
        static let model = "names.lm"
        static let vocabulary = "names.vocab"
        static let digest = "names.digest"
    }

    /// The bundle identifier, which the system files a custom model under.
    private static let identifier = "com.memnox.voice"
    /// Raised when the templates or pronunciations change, so every Mac builds its model again.
    private static let version = "8"
    /// Each word heard on its own often enough to be expected, well under the requests that hold it.
    private static let termCount = 50
    private static let appFolder = "Memnox"
    private static let modelFolder = "Vocabulary"
    private static let fallbackLocale = "en-US"
    private static let hexByte = "%02x"
}
