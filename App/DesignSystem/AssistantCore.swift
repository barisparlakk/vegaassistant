import MetalKit
import SwiftUI

/// Vega's presence: a real-time 3D crystal star with a living core and orbiting HUD rings,
/// ray-traced on the GPU (`AssistantCoreShader`). It sways when idle, brightens while it speaks
/// (flaring on each word), quickens while preparing a briefing, and leans toward the pointer.
struct AssistantCore: View {
    enum Mood: Equatable {
        case idle, focus, listening, speaking, working

        var energy: Float {
            switch self {
            case .idle: 0.35
            case .focus: 0.5
            case .listening: 0.6
            case .speaking: 0.7
            case .working: 1.0
            }
        }
    }

    var mood: Mood = .idle
    var size: CGFloat = DS.Size.orb
    /// Motion: the sway, the living core, the pointer lean.
    var isAnimated = true
    /// The HUD rings and the speech flare. Off for small sizes.
    var showsRings = true
    /// Bumped on every spoken word; each bump makes the star flare briefly.
    var pulse = 0

    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointer: CGPoint?

    var body: some View {
        AssistantCoreView(
            state: AssistantCoreRenderer.State(
                mood: mood,
                accent: Self.rgba(accent),
                isDark: scheme == .dark,
                showsRings: showsRings,
                isAnimated: isAnimated && !reduceMotion,
                pointer: pointer,
                pulse: pulse
            )
        )
        .frame(width: size, height: size)
        .onContinuousHover { phase in
            guard isAnimated else { return }
            switch phase {
            case let .active(location):
                pointer = CGPoint(x: location.x / size * 2 - 1, y: location.y / size * 2 - 1)
            case .ended:
                pointer = nil
            }
        }
        .accessibilityHidden(true)
    }

    private static func rgba(_ color: Color) -> SIMD4<Float> {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return SIMD4(1, 0.62, 0.26, 1) }
        return SIMD4(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), 1)
    }
}

// MARK: - Metal view

private struct AssistantCoreView: NSViewRepresentable {
    let state: AssistantCoreRenderer.State

    func makeCoordinator() -> AssistantCoreRenderer? { AssistantCoreRenderer() }

    func makeNSView(context: Context) -> NSView {
        guard let renderer = context.coordinator else { return FallbackOrbView() }
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.layer?.isOpaque = false
        view.preferredFramesPerSecond = 60
        view.delegate = renderer
        renderer.apply(state, to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? MTKView else { return }
        context.coordinator?.apply(state, to: view)
    }
}

/// Draws the core shader into an MTKView. Energy and pointer lean are eased per frame.
@MainActor
final class AssistantCoreRenderer: NSObject, MTKViewDelegate {
    struct State: Equatable {
        var mood: AssistantCore.Mood
        var accent: SIMD4<Float>
        var isDark: Bool
        var showsRings: Bool
        var isAnimated: Bool
        var pointer: CGPoint?
        var pulse: Int
    }

    /// Matches `Uniforms` in the shader (64 bytes).
    private struct Uniforms {
        var size: SIMD2<Float>
        var time: Float
        var energy: Float
        var tilt: SIMD2<Float>
        var dark: Float
        var rings: Float
        var pulse: Float
        var accent: SIMD4<Float>
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let start = CACurrentMediaTime()
    private var state: State?
    private var energy: Float = AssistantCore.Mood.idle.energy
    private var lean = SIMD2<Float>(0, 0)
    private var lastFrame = CACurrentMediaTime()
    private var lastPulse = 0
    private var pulseAt: CFTimeInterval = 0

    /// Shared across every core on screen; compiled once.
    private static let library: (MTLDevice, MTLLibrary)? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(source: AssistantCoreShader.source, options: nil)
        else { return nil }
        return (device, library)
    }()

    init?(_: Void = ()) {
        guard let (device, library) = Self.library,
              let queue = device.makeCommandQueue(),
              let vertex = library.makeFunction(name: "coreVertex"),
              let fragment = library.makeFunction(name: "coreFragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func apply(_ newState: State, to view: MTKView) {
        let isFirst = state == nil
        if newState.pulse != lastPulse {
            lastPulse = newState.pulse
            pulseAt = CACurrentMediaTime()
        }
        state = newState
        if isFirst { energy = newState.mood.energy }
        view.isPaused = !newState.isAnimated
        view.enableSetNeedsDisplay = !newState.isAnimated
        if !newState.isAnimated {
            energy = newState.mood.energy
            view.needsDisplay = true
        }
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(in: view) }
    }

    private func render(in view: MTKView) {
        guard let state,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastFrame, 0.1))
        lastFrame = now
        let time = Float((now - start).truncatingRemainder(dividingBy: 3600))

        // Ease toward the mood's energy and the pointer's lean.
        let follow = 1 - exp(-delta * 3.5)
        energy += (state.mood.energy - energy) * follow
        let target = state.pointer.map { SIMD2(Float($0.x) * 0.32, Float($0.y) * 0.24) } ?? .zero
        lean += (target - lean) * (1 - exp(-delta * 5))

        let sway = state.isAnimated ? SIMD2(sin(time * 0.21) * 0.10, cos(time * 0.17) * 0.07) : SIMD2<Float>(0.2, 0.12)
        var uniforms = Uniforms(
            size: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: state.isAnimated ? time : 12,
            energy: energy,
            tilt: sway + lean,
            dark: state.isDark ? 1 : 0,
            rings: state.showsRings ? 1 : 0,
            pulse: state.isAnimated ? Float(exp(-(now - pulseAt) * 5)) : 0,
            accent: state.accent
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// If Metal isn't available: the flat star mark.
private final class FallbackOrbView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = VegaMark.path(in: bounds.insetBy(dx: bounds.width * 0.2, dy: bounds.height * 0.2))
        NSColor.controlAccentColor.setFill()
        path.fill()
    }
}

/// Vega's flat star mark (the logo), as a path in any rect.
enum VegaMark {
    /// Points of the four-point star in a 24×24 box: tips at the edges, inner corners near the middle.
    private static let points: [CGPoint] = [
        CGPoint(x: 12, y: 1.5), CGPoint(x: 14.2, y: 9.8), CGPoint(x: 22.5, y: 12), CGPoint(x: 14.2, y: 14.2),
        CGPoint(x: 12, y: 22.5), CGPoint(x: 9.8, y: 14.2), CGPoint(x: 1.5, y: 12), CGPoint(x: 9.8, y: 9.8),
    ]

    /// A template image for the menu bar: the star, hollow while a briefing is being prepared.
    @MainActor
    static func menuBarImage(isWorking: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let star = path(in: rect.insetBy(dx: 1, dy: 1))
            NSColor.black.set()
            if isWorking {
                star.lineWidth = 1.3
                star.stroke()
            } else {
                star.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func path(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(x: rect.minX + point.x / 24 * rect.width, y: rect.minY + point.y / 24 * rect.height)
            if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
        }
        path.close()
        return path
    }
}

/// The flat star mark for SwiftUI.
struct VegaMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(VegaMark.path(in: rect).cgPath)
    }
}

#Preview("Core — dark") {
    HStack(spacing: 40) {
        AssistantCore(mood: .idle, size: 220)
        AssistantCore(mood: .working, size: 220)
        AssistantCore(size: 52, showsRings: false)
    }
    .padding(40)
    .background(DS.Color.background)
    .environment(\.accent, DS.Color.defaultAccent)
    .preferredColorScheme(.dark)
}

#Preview("Core — light") {
    HStack(spacing: 40) {
        AssistantCore(mood: .idle, size: 220)
        AssistantCore(mood: .focus, size: 220)
    }
    .padding(40)
    .background(DS.Color.background)
    .environment(\.accent, DS.Color.defaultAccent)
    .preferredColorScheme(.light)
}
