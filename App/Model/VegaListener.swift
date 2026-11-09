import AVFoundation
import Observation
import Speech

/// Listens for one question with Apple's speech recognition, on device when the Mac supports
/// it. Stops by itself after a short pause, then hands the text over.
@MainActor
@Observable
final class VegaListener {
    enum Status: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    private(set) var status: Status = .idle
    /// What it has heard so far.
    private(set) var transcript = ""

    var isListening: Bool { status == .listening }

    /// Created only once listening starts (after permission): touching the input node any
    /// earlier makes Core Audio wait on the microphone prompt and blocks the main thread.
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?
    @ObservationIgnored private var onFinish: ((String) -> Void)?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    /// After this long without new words, the question is considered finished.
    static let pause: Duration = .milliseconds(1500)
    /// Never listen longer than this.
    static let limit: Duration = .seconds(30)

    /// Starts listening; `finished` gets the final text (empty if nothing was heard).
    func start(finished: @escaping (String) -> Void) {
        guard status != .listening else { return }
        onFinish = finished
        transcript = ""
        Task {
            guard await Self.authorize() else {
                status = .unavailable("Allow Microphone and Speech Recognition for Vega in System Settings › Privacy & Security.")
                return
            }
            do {
                try begin()
            } catch {
                status = .unavailable("Couldn't start listening: \(error.localizedDescription)")
                cleanUp()
            }
        }
    }

    /// Stops and submits what was heard.
    func stop() {
        guard status == .listening else { return }
        finish()
    }

    /// Stops without submitting.
    func cancel() {
        guard status == .listening else { return }
        onFinish = nil
        cleanUp()
        status = .idle
    }

    private func begin() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw ListenerError.recognizerUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        nonisolated(unsafe) let tapRequest = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            tapRequest.append(buffer)
        }
        engine.prepare()
        try engine.start()
        status = .listening

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.status == .listening else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.armSilenceTimer()
                }
                if isFinal || failed { self.finish() }
            }
        }
        // Give up if nothing is said at all.
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, self.transcript.isEmpty else { return }
            self.finish()
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.limit)
            self?.stop()
        }
    }

    private func armSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard let self, !Task.isCancelled else { return }
            self.finish()
        }
    }

    private func finish() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let callback = onFinish
        onFinish = nil
        cleanUp()
        status = .idle
        callback?(text)
    }

    private func cleanUp() {
        silenceTimer?.cancel()
        silenceTimer = nil
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    private enum ListenerError: LocalizedError {
        case recognizerUnavailable
        var errorDescription: String? { "speech recognition isn't available right now" }
    }
}
