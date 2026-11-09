import AVFoundation
import Observation

/// Vega's voice: speaks a script line by line with the Mac's on-device voices, and reports
/// which line and which word it's on so the UI can caption it and the star can pulse.
@MainActor
@Observable
final class VegaVoice: NSObject {
    enum Status: Equatable { case idle, speaking, paused }

    private(set) var status: Status = .idle
    /// The script being spoken (or last spoken).
    private(set) var lines: [VegaLine] = []
    /// Index of the line being spoken; `lines.count` once finished.
    private(set) var currentLine = 0
    /// Characters of the current line already spoken.
    private(set) var spokenLength = 0
    /// Bumped on every word; drives the star's flare.
    private(set) var wordTick = 0

    var isSpeaking: Bool { status == .speaking }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var utterances: [ObjectIdentifier: Int] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `lines` from the start. With `silently`, shows them all at once without speaking.
    func speak(_ lines: [VegaLine], silently: Bool = false) {
        synthesizer.stopSpeaking(at: .immediate)
        utterances = [:]
        self.lines = lines
        guard !silently, !lines.isEmpty else {
            finish()
            return
        }
        currentLine = 0
        spokenLength = 0
        status = .speaking
        let voice = VegaVoice.selectedVoice
        for (index, line) in lines.enumerated() {
            let utterance = AVSpeechUtterance(string: line.text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
            utterance.pitchMultiplier = 1.0
            utterance.postUtteranceDelay = 0.35
            utterance.preUtteranceDelay = index == 0 ? 0.2 : 0
            utterances[ObjectIdentifier(utterance)] = index
            synthesizer.speak(utterance)
        }
    }

    func pause() {
        guard status == .speaking else { return }
        synthesizer.pauseSpeaking(at: .word)
        status = .paused
    }

    func resume() {
        guard status == .paused else { return }
        synthesizer.continueSpeaking()
        status = .speaking
    }

    func togglePause() {
        switch status {
        case .speaking: pause()
        case .paused: resume()
        case .idle: replay()
        }
    }

    func replay() {
        speak(lines)
    }

    /// Stops speaking and shows the whole script.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        utterances = [:]
        currentLine = lines.count
        spokenLength = 0
        status = .idle
    }

    // MARK: Voices

    static let voiceKey = "vega.voiceID"

    /// English voices on this Mac, best quality first.
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    /// The chosen voice, or the best English voice installed.
    static var selectedVoice: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: voiceKey), let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        return availableVoices.first { $0.language == Locale.current.identifier.replacingOccurrences(of: "_", with: "-") }
            ?? availableVoices.first
    }

    // MARK: Delegate (called by AVFoundation; hop to the main actor)

    fileprivate func didStart(_ id: ObjectIdentifier) {
        guard let index = utterances[id] else { return }
        currentLine = index
        spokenLength = 0
    }

    fileprivate func willSpeak(_ id: ObjectIdentifier, range: NSRange) {
        guard let index = utterances[id] else { return }
        currentLine = index
        spokenLength = range.location + range.length
        wordTick &+= 1
    }

    fileprivate func didFinish(_ id: ObjectIdentifier) {
        guard let index = utterances[id] else { return }
        spokenLength = lines.indices.contains(index) ? (lines[index].text as NSString).length : 0
        if index == lines.count - 1 { finish() }
    }
}

extension VegaVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didStart(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.willSpeak(id, range: characterRange) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didFinish(id) }
    }
}

/// One thing Vega says, with what to show under it.
struct VegaLine: Identifiable, Equatable {
    enum Attachment: Equatable {
        case none
        case focusTasks
        case overnight
        case decisions
        case agenda
        case news
        case fallback
    }

    let id: String
    let text: String
    var attachment: Attachment = .none
    /// The first line is set larger.
    var isOpening = false
}
