import MetalKit
import MemnoxVoiceCore

/// The particle sphere. Compiled from source at launch, so the package needs no Metal build
/// step, and driven by one number that matters: how loud the voice is right now.
final class OrbRenderer: NSObject, MTKViewDelegate {
    private static let pointCount: UInt32 = 6_000

    /// The shader's entry points, named as `shader` declares them.
    private enum Function {
        static let vertex = "orbVertex"
        static let fragment = "orbFragment"
    }

    /// The vertex buffer slots, numbered as the shader's `[[buffer(n)]]` attributes number them.
    private enum Slot {
        static let uniforms = 0
        static let count = 1
    }

    /// The scale assumed before the view is on a window, which is a Retina display's.
    private static let fallbackBackingScale: CGFloat = 2

    /// The side at which the orb draws every point at full size; smaller orbs thin them out.
    private static let fullSizeSide: CGFloat = 240
    /// However small the orb, it keeps at least this many points, each at least this share of full size.
    private static let minimumPoints: Double = 300
    private static let minimumDotShare: CGFloat = 0.35

    /// Where each state eases the sphere toward: how much it ripples, spins and pulls in.
    private enum Target {
        static let idleLevel: Float = 0.04
        static let listeningLevel: Float = 0.08
        static let thinkingLevel: Float = 0.12
        static let speakingLevel: Float = 0.1
        /// Speech ripples a little harder than the same loudness heard.
        static let speakingGain: Float = 1.2
        static let needsYouLevel: Float = 0.02
    }

    /// How much of the gap to its target each value closes per frame: ripples fast, spin and hold slowly.
    private enum Easing {
        static let level: Float = 0.25
        static let swirl: Float = 0.05
        static let hold: Float = 0.08
        /// Slow, so thinking reads as the same points rebuilding into a knot rather than a cut.
        static let knot: Float = 0.05
    }

    /// The voice's syllables, each a fast rise in its loudness that sends a lit ring from chin to crown.
    private enum Syllable {
        /// The envelope rises fast and falls slowly, so a syllable shows as a jump and a pause does not.
        static let attack: Float = 0.55
        static let release: Float = 0.18
        /// How far the envelope must jump in one frame to count, and how soon after the last one it may.
        static let rise: Float = 0.06
        static let gap: Double = 0.12
        /// How long a ring takes to climb the sphere and fade, and how many climb at once.
        static let life: Double = 1.2
        static let most = 4
        /// Where a ring starts, just under the sphere, and how far it climbs each second.
        static let start: Float = -1.15
        static let climb: Float = 2.1
    }

    /// How long each gesture lasts, in seconds: a burst lingers, a jitter is over quickly.
    private enum Gesture {
        /// Long enough for the seal and tick to be read before the points fall back into the sphere.
        static let burst: Double = 2.2
        static let stumble: Double = 0.9
        static let settle: Double = 0.8
        static let allowed: Double = 0.7
        static let refused: Double = 0.6
        /// Long enough to be noticed from the corner of the eye, short enough to never read as an answer.
        static let glance: Double = 0.5
        /// The share of a gesture spent rising before it falls away.
        static let attack: Double = 0.15
        /// The share of a burst spent gathering into the tick, and the share spent letting it go.
        static let sealRise: Double = 0.25
        static let sealFall: Double = 0.3
    }

    /// How fast the held bounce eases in and out, so a call arriving never snaps the orb.
    private static let waitingEasing: Float = 0.06

    /// Frames a second: every frame only while the sphere moves, since at rest it breathes too slowly to need them.
    private enum Pace {
        static let moving = 60
        static let resting = 20
        /// On a small, busy or hot Mac, where the agents need the machine more than the orb does.
        static let lightMoving = 30
        static let lightResting = 12
        /// The easings above were tuned one step per frame at this rate, so a slower frame takes several steps.
        static let tuned: Double = 60
        /// A frame after a long stall catches up at most this many steps rather than jumping.
        static let mostSteps: Double = 6
        /// Below this the bounce has settled and no longer needs every frame.
        static let still: Float = 0.01
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let started = CACurrentMediaTime()
    private var level: Float = 0
    private var swirl: Float = 0
    private var hold: Float = 0
    private var knot: Float = 0
    /// The voice envelope, and when each syllable still climbing the sphere began.
    private var voice: Float = 0
    private var onsets: [CFTimeInterval] = []
    private var lastFrame: CFTimeInterval?
    /// How many tuned steps this frame stands for, so the sphere moves at one speed at any frame rate.
    private var steps: Float = 1

    /// Read every frame: the loudness to follow, and the state that decides how it moves.
    var loudness: () -> Float = { 0 }
    var state: VoiceState = .idle
    /// Set while a call waits on the person, so the orb keeps bouncing until somebody answers.
    var waiting = false
    private var bounce: Float = 0
    /// The gesture under way and when it began; a new one replaces it rather than stacking.
    private var gesture: (reaction: Reaction, at: CFTimeInterval)?

    /// Starts a short gesture over whatever the voice state is doing.
    func react(_ reaction: Reaction) {
        gesture = (reaction, CACurrentMediaTime())
    }

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil)
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: Function.vertex)
        descriptor.fragmentFunction = library.makeFunction(name: Function.fragment)
        // Attachment zero always exists on a fresh descriptor.
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = view.colorPixelFormat
        // Additive, so dots in front of one another glow brighter rather than hide each other.
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .one
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.queue = queue
        self.pipeline = pipeline
        super.init()
        view.device = device
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        steps = Float(min((now - (lastFrame ?? now - 1 / Pace.tuned)) * Pace.tuned, Pace.mostSteps))
        lastFrame = now
        advance(at: now)
        pace(view)
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let size = view.drawableSize
        let fit = Self.fit(side: min(view.bounds.width, view.bounds.height))
        let shape = gestureShape(at: now)
        let rings = rings(at: now)
        var uniforms = OrbUniforms(
            time: Float(now - started),
            level: level,
            swirl: swirl,
            hold: hold,
            aspect: Float(size.width / max(size.height, 1)),
            scale: Float(view.window?.backingScaleFactor ?? Self.fallbackBackingScale) * fit.dot,
            burst: shape.burst,
            jitter: shape.jitter,
            drain: shape.drain,
            pull: shape.pull,
            glow: shape.glow,
            bounce: bounce,
            knot: knot,
            seal: shape.seal,
            ringHeight0: rings[0].height, ringHeight1: rings[1].height,
            ringHeight2: rings[2].height, ringHeight3: rings[3].height,
            ringFade0: rings[0].fade, ringFade1: rings[1].fade,
            ringFade2: rings[2].fade, ringFade3: rings[3].fade
        )
        var count = fit.points
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: Slot.uniforms)
        encoder.setVertexBytes(&count, length: MemoryLayout<UInt32>.stride, index: Slot.count)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Int(count))
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Fewer and finer points as the orb gets smaller, since six thousand full size dots on a small
    /// orb glow on top of one another into a flat white disc.
    static func fit(side: CGFloat) -> (points: UInt32, dot: Float) {
        let share = min(1, max(0, side / fullSizeSide))
        let points = UInt32(max(minimumPoints, Double(pointCount) * Double(share * share)))
        return (points, Float(max(minimumDotShare, share)))
    }

    /// Eased toward where the state wants it, so the sphere breathes rather than twitches.
    private func advance(at now: CFTimeInterval) {
        let heard = min(max(loudness(), 0), 1)
        listen(heard, at: now)
        let target: (level: Float, swirl: Float, hold: Float)
        switch state {
        case .idle: target = (Target.idleLevel, 0, 0)
        case .listening: target = (Target.listeningLevel + heard, 0, 0)
        case .thinking: target = (Target.thinkingLevel, 1, 0)
        case .speaking: target = (Target.speakingLevel + heard * Target.speakingGain, 0, 0)
        case .needsYou: target = (Target.needsYouLevel, 0, 1)
        }
        level += (target.level - level) * eased(Easing.level)
        swirl += (target.swirl - swirl) * eased(Easing.swirl)
        hold += (target.hold - hold) * eased(Easing.hold)
        knot += ((state == .thinking ? 1 : 0) - knot) * eased(Easing.knot)
        bounce += ((waiting ? 1 : 0) - bounce) * eased(Self.waitingEasing)
    }

    /// One frame's share of the gap, compounded over however many tuned steps the frame stands for.
    private func eased(_ rate: Float) -> Float {
        1 - pow(1 - rate, steps)
    }

    /// Asks for every frame only while something on the sphere is moving, and fewer on a light machine.
    private func pace(_ view: MTKView) {
        let resting = (state == .idle || state == .needsYou) && gesture == nil && !waiting
            && bounce < Pace.still && onsets.isEmpty
        let light = MachinePace.light
        let frames = resting ? (light ? Pace.lightResting : Pace.resting) : (light ? Pace.lightMoving : Pace.moving)
        if view.preferredFramesPerSecond != frames { view.preferredFramesPerSecond = frames }
    }

    /// Follows the voice envelope and marks a syllable wherever it jumps, only while the orb speaks.
    private func listen(_ heard: Float, at now: CFTimeInterval) {
        let previous = voice
        voice += (heard - voice) * eased(heard > voice ? Syllable.attack : Syllable.release)
        let rested = onsets.last.map { now - $0 > Syllable.gap } ?? true
        if state == .speaking, voice - previous > Syllable.rise, rested {
            onsets.append(now)
        }
        onsets.removeAll { now - $0 >= Syllable.life }
        if onsets.count > Syllable.most { onsets.removeFirst(onsets.count - Syllable.most) }
    }

    /// Where each climbing ring is on the sphere and how bright it still is, unused slots dark.
    private func rings(at now: CFTimeInterval) -> [(height: Float, fade: Float)] {
        let climbing = onsets.map { onset -> (height: Float, fade: Float) in
            let age = now - onset
            let left = Float(max(0, 1 - age / Syllable.life))
            return (Syllable.start + Float(age) * Syllable.climb, left * left)
        }
        return climbing + Array(repeating: (0, 0), count: Syllable.most - climbing.count)
    }

    /// Up quickly, held long enough to read, then let go, with eased corners so nothing snaps.
    private static func plateau(_ progress: Double) -> Float {
        let rise = min(1, progress / Gesture.sealRise)
        let fall = min(1, (1 - progress) / Gesture.sealFall)
        let held = max(0, min(rise, fall))
        return Float(held * held * (3 - 2 * held))
    }

    /// The strength of each part of the gesture right now: a quick rise, then an eased fall to nothing.
    private func gestureShape(at moment: CFTimeInterval) -> GestureShape {
        guard let gesture else { return GestureShape() }
        let length = Self.length(of: gesture.reaction)
        let progress = (moment - gesture.at) / length
        guard progress < 1 else {
            self.gesture = nil
            return GestureShape()
        }
        let falling = (progress - Gesture.attack) / (1 - Gesture.attack)
        let envelope = Float(progress < Gesture.attack ? progress / Gesture.attack : (1 - falling) * (1 - falling))
        var shape = GestureShape()
        switch gesture.reaction {
        case .burst:
            shape.burst = envelope
            shape.glow = envelope
            shape.seal = Self.plateau(progress)
        case .stumble:
            shape.jitter = envelope
            shape.drain = envelope
        case .settle:
            shape.burst = envelope * GestureShape.settleShare
        case .allowed:
            shape.burst = envelope * GestureShape.allowedShare
            shape.glow = envelope
        case .refused:
            shape.pull = envelope
        case .glance:
            shape.glow = envelope
            shape.pull = envelope * GestureShape.glanceShare
        }
        return shape
    }

    private static func length(of reaction: Reaction) -> Double {
        switch reaction {
        case .burst: return Gesture.burst
        case .stumble: return Gesture.stumble
        case .settle: return Gesture.settle
        case .allowed: return Gesture.allowed
        case .refused: return Gesture.refused
        case .glance: return Gesture.glance
        }
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float time; float level; float swirl; float hold; float aspect; float scale;
        float burst; float jitter; float drain; float pull; float glow; float bounce;
        float knot; float seal;
        float ringHeight0; float ringHeight1; float ringHeight2; float ringHeight3;
        float ringFade0; float ringFade1; float ringFade2; float ringFade3;
    };
    struct Dot { float4 position [[position]]; float size [[point_size]]; float4 color; float spark; };

    static float hash(float3 p) {
        p = fract(p * 0.3183099 + 0.1);
        p *= 17.0;
        return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
    }

    static float noise(float3 x) {
        float3 i = floor(x);
        float3 f = fract(x);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(mix(hash(i + float3(0,0,0)), hash(i + float3(1,0,0)), f.x),
                       mix(hash(i + float3(0,1,0)), hash(i + float3(1,1,0)), f.x), f.y),
                   mix(mix(hash(i + float3(0,0,1)), hash(i + float3(1,0,1)), f.x),
                       mix(hash(i + float3(0,1,1)), hash(i + float3(1,1,1)), f.x), f.y), f.z);
    }

    vertex Dot orbVertex(uint id [[vertex_id]],
                         constant Uniforms &u [[buffer(0)]],
                         constant uint &count [[buffer(1)]]) {
        float i = float(id) + 0.5;
        float share = i / float(count);
        float phi = acos(1.0 - 2.0 * share);
        float theta = 3.14159265 * (1.0 + sqrt(5.0)) * i;
        float3 p = float3(cos(theta) * sin(phi), sin(theta) * sin(phi), cos(phi));
        float tau = 6.2831853;

        float spin = u.time * (0.12 + 0.5 * u.swirl);
        float3x3 turn = float3x3(float3(cos(spin), 0, -sin(spin)), float3(0, 1, 0), float3(sin(spin), 0, cos(spin)));
        float tilt = 0.35;
        float3x3 lean = float3x3(float3(1, 0, 0), float3(0, cos(tilt), sin(tilt)), float3(0, -sin(tilt), cos(tilt)));
        p = lean * (turn * p);

        // Thinking braids the same points into a turning torus knot, after Ship Notes' Signal Orb.
        float around = share * tau * 3.0 + u.time * 0.57;
        float braid = share * tau * 8.0 - u.time * 0.48;
        float tube = 0.71 + 0.21 * cos(braid) + 0.12 * sin(theta);
        float lift = 0.34 * sin(braid) + 0.09 * cos(phi);
        float3 knot = float3(tube * cos(around),
                             lift * 0.77 - tube * sin(around) * 0.52,
                             lift * 0.52 + tube * sin(around) * 0.77);
        p = mix(p, knot, u.knot);

        // Each syllable is a lit band climbing from chin to crown, lifting the points it passes.
        float4 heights = float4(u.ringHeight0, u.ringHeight1, u.ringHeight2, u.ringHeight3);
        float4 fades = float4(u.ringFade0, u.ringFade1, u.ringFade2, u.ringFade3);
        float4 reach = (p.y - heights) / 0.15;
        float lit = min(1.0, dot(exp(-reach * reach), fades));

        float wobble = noise(p * 2.3 + float3(0, 0, u.time * 0.5)) - 0.5;
        float breathe = 0.025 * sin(u.time * 1.2);
        // Each point flies its own distance in a burst, so the sphere scatters rather than just growing,
        // and no further than the canvas the orb is drawn on, where it would be cut square.
        float fling = 0.25 + 0.75 * hash(float3(i * 0.0131, i * 0.0071, i * 0.0113));
        float radius = 1.0 + breathe + wobble * (0.06 + 0.45 * u.level) - 0.14 * u.hold
                     + 0.3 * u.burst * fling - 0.2 * u.pull + 0.04 * lit;
        p *= radius;
        // The clock wrapped first, since a raw hour of seconds times forty is past what a float hashes finely.
        float beat = fract(u.time * 7.0) * 31.0;
        float3 shiver = float3(hash(p + beat), hash(p.yzx + beat * 1.3), hash(p.zxy + beat * 1.7)) - 0.5;
        p += shiver * 0.12 * u.jitter;

        // Passing tests gather the points into a seal and a tick: most make the ring, the rest the two strokes.
        float ringShare = 0.65;
        float3 seal;
        if (share < ringShare) {
            float q = share / ringShare * tau;
            float r = 0.9 + 0.047 * sin(theta);
            seal = float3(cos(q) * r, sin(q) * r, 0.04 * sin(theta));
        } else {
            float q = (share - ringShare) / (1.0 - ringShare);
            float2 corner = float2(-0.12, -0.3);
            float2 mark = q < 0.38 ? mix(float2(-0.42, 0.0), corner, q / 0.38)
                                   : mix(corner, float2(0.48, 0.4), (q - 0.38) / 0.62);
            seal = float3(mark + 0.03 * float2(sin(theta), cos(theta)), 0.0);
        }
        p = mix(p, seal, u.seal);

        float depth = p.z + 3.2;
        Dot out;
        float hop = 0.08 * u.bounce * abs(sin(u.time * 3.4));
        out.position = float4(p.x * 2.1 / depth / max(u.aspect, 0.01), p.y * 2.1 / depth + hop, 0.5, 1.0);
        float front = clamp((p.z + 1.2) / 2.4, 0.0, 1.0);
        float3 sky = float3(0.55, 0.80, 1.0);
        float3 primary = float3(0.118, 0.525, 0.933);
        float3 deep = float3(0.06, 0.28, 0.78);
        float shade = clamp(0.5 - p.y * 0.5 + wobble, 0.0, 1.0);
        float3 tint = mix(mix(sky, primary, saturate(shade * 2.0)), deep, saturate(shade * 2.0 - 1.0));
        tint = mix(tint, float3(1.0), 0.55 * u.glow);
        float grey = dot(tint, float3(0.299, 0.587, 0.114));
        tint = mix(tint, float3(grey) * 0.7, 0.85 * u.drain);
        out.color = float4(tint, min(1.0, mix(0.32, 1.0, front) + lit));
        out.size = (1.8 + 2.4 * front) * (1.0 + 0.5 * lit) * u.scale;
        // The nearest points and a passing ring carry a small white core, so the sphere reads as lit from the front.
        out.spark = (max(0.0, front - 0.6) * 0.9 + 0.6 * lit) * (1.0 - u.drain);
        return out;
    }

    fragment float4 orbFragment(Dot in [[stage_in]], float2 at [[point_coord]]) {
        float d = length(at - 0.5);
        float glow = smoothstep(0.5, 0.0, d);
        float core = 1.0 - smoothstep(0.06, 0.12, d);
        float a = glow * in.color.a;
        float s = core * in.spark;
        return float4(in.color.rgb * a + s, a + s);
    }
    """
}

/// Laid out exactly as the shader's `Uniforms`: twenty two floats in a row.
private struct OrbUniforms {
    var time: Float
    var level: Float
    var swirl: Float
    var hold: Float
    var aspect: Float
    var scale: Float
    var burst: Float
    var jitter: Float
    var drain: Float
    var pull: Float
    var glow: Float
    var bounce: Float
    var knot: Float
    var seal: Float
    var ringHeight0: Float
    var ringHeight1: Float
    var ringHeight2: Float
    var ringHeight3: Float
    var ringFade0: Float
    var ringFade1: Float
    var ringFade2: Float
    var ringFade3: Float
}

/// How strongly each part of a gesture shows this frame, all nothing when no gesture is under way.
private struct GestureShape {
    var burst: Float = 0
    var jitter: Float = 0
    var drain: Float = 0
    var pull: Float = 0
    var glow: Float = 0
    var seal: Float = 0

    /// A settle is a burst too small to read as a celebration.
    static let settleShare: Float = 0.18
    /// An allow rings out further than a settle and well short of a burst.
    static let allowedShare: Float = 0.3
    /// A glance draws the orb in a little as it lights, the way an eye narrows to look.
    static let glanceShare: Float = 0.25
}
