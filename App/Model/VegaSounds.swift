import AVFoundation

/// Vega's interface sounds, synthesized on the fly (no audio files): soft bell tones with a
/// quick attack and a long decay.
@MainActor
final class VegaSounds {
    enum Cue {
        /// The briefing is ready: a rising fifth.
        case ready
        /// Vega starts talking: one soft, high note.
        case wake
        /// A focus block starts: two notes up.
        case focusStart
        /// A focus block ends: two notes down.
        case focusEnd
        /// A task is checked off: a tiny tick.
        case done

        /// (frequency in Hz, start offset in seconds, gain)
        var notes: [(Double, Double, Float)] {
            switch self {
            case .ready: [(659.25, 0, 0.22), (987.77, 0.11, 0.2), (1318.5, 0.22, 0.12)]
            case .wake: [(1046.5, 0, 0.12), (1567.98, 0.03, 0.05)]
            case .focusStart: [(587.33, 0, 0.2), (880.0, 0.12, 0.2)]
            case .focusEnd: [(880.0, 0, 0.18), (587.33, 0.14, 0.18)]
            case .done: [(1318.5, 0, 0.1)]
            }
        }
    }

    static let enabledKey = "vega.sounds"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var isRunning = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ cue: Cue) {
        guard Self.isEnabled, let buffer = render(cue) else { return }
        if !isRunning {
            do {
                try engine.start()
                isRunning = true
            } catch {
                return
            }
        }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying { player.play() }
    }

    private func render(_ cue: Cue) -> AVAudioPCMBuffer? {
        let duration = 1.4
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1]
        else { return nil }
        buffer.frameLength = frames
        let rate = format.sampleRate
        for frame in 0..<Int(frames) {
            let t = Double(frame) / rate
            var sample: Float = 0
            for (frequency, offset, gain) in cue.notes where t >= offset {
                let local = t - offset
                let attack = min(local / 0.006, 1)
                let envelope = Float(attack * exp(-local * 4.2))
                // A bell: the fundamental plus a quiet inharmonic partial that fades faster.
                let tone = sin(2 * .pi * frequency * local) + 0.28 * sin(2 * .pi * frequency * 2.76 * local) * exp(-local * 6)
                sample += Float(tone) * envelope * gain
            }
            left[frame] = sample
            right[frame] = sample
        }
        return buffer
    }
}
