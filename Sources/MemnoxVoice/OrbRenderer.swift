import MetalKit
import MemnoxVoiceCore

/// The particle sphere. Compiled from source at launch, so the package needs no Metal build
/// step, and driven by one number that matters: how loud the voice is right now.
final class OrbRenderer: NSObject, MTKViewDelegate {
    private static let pointCount: UInt32 = 6_000

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let started = CACurrentMediaTime()
    private var level: Float = 0
    private var swirl: Float = 0
    private var hold: Float = 0

    /// Read every frame: the loudness to follow, and the state that decides how it moves.
    var loudness: () -> Float = { 0 }
    var state: VoiceState = .idle

    init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil)
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "orbFragment")
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
        advance()
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let size = view.drawableSize
        var uniforms = OrbUniforms(
            time: Float(CACurrentMediaTime() - started),
            level: level,
            swirl: swirl,
            hold: hold,
            aspect: Float(size.width / max(size.height, 1)),
            scale: Float(view.window?.backingScaleFactor ?? 2)
        )
        var count = Self.pointCount
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        encoder.setVertexBytes(&count, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Int(Self.pointCount))
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Eased toward where the state wants it, so the sphere breathes rather than twitches.
    private func advance() {
        let heard = min(max(loudness(), 0), 1)
        let target: (level: Float, swirl: Float, hold: Float)
        switch state {
        case .idle: target = (0.04, 0, 0)
        case .listening: target = (0.08 + heard, 0, 0)
        case .thinking: target = (0.12, 1, 0)
        case .speaking: target = (0.1 + heard * 1.2, 0, 0)
        case .needsYou: target = (0.02, 0, 1)
        }
        level += (target.level - level) * 0.25
        swirl += (target.swirl - swirl) * 0.05
        hold += (target.hold - hold) * 0.08
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float time; float level; float swirl; float hold; float aspect; float scale; };
    struct Dot { float4 position [[position]]; float size [[point_size]]; float4 color; };

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
        float phi = acos(1.0 - 2.0 * i / float(count));
        float theta = 3.14159265 * (1.0 + sqrt(5.0)) * i;
        float3 p = float3(cos(theta) * sin(phi), sin(theta) * sin(phi), cos(phi));

        float spin = u.time * (0.12 + 0.5 * u.swirl);
        float3x3 turn = float3x3(float3(cos(spin), 0, -sin(spin)), float3(0, 1, 0), float3(sin(spin), 0, cos(spin)));
        float tilt = 0.35;
        float3x3 lean = float3x3(float3(1, 0, 0), float3(0, cos(tilt), sin(tilt)), float3(0, -sin(tilt), cos(tilt)));
        p = lean * (turn * p);

        float wobble = noise(p * 2.3 + float3(0, 0, u.time * 0.5)) - 0.5;
        float breathe = 0.025 * sin(u.time * 1.2);
        float radius = 1.0 + breathe + wobble * (0.06 + 0.45 * u.level) - 0.14 * u.hold;
        p *= radius;

        float depth = p.z + 3.2;
        Dot out;
        out.position = float4(p.x * 2.1 / depth / max(u.aspect, 0.01), p.y * 2.1 / depth, 0.5, 1.0);
        float front = clamp((p.z + 1.2) / 2.4, 0.0, 1.0);
        float3 ember = float3(1.0, 0.52, 0.18);
        float3 rose = float3(0.95, 0.22, 0.62);
        float3 tint = mix(ember, rose, clamp(0.5 - p.y * 0.5 + wobble, 0.0, 1.0));
        out.color = float4(tint, mix(0.32, 1.0, front));
        out.size = (1.8 + 2.4 * front) * u.scale;
        return out;
    }

    fragment float4 orbFragment(Dot in [[stage_in]], float2 at [[point_coord]]) {
        float d = length(at - 0.5);
        float glow = smoothstep(0.5, 0.0, d);
        float a = glow * in.color.a;
        return float4(in.color.rgb * a, a);
    }
    """
}

/// Laid out exactly as the shader's `Uniforms`: six floats in a row.
private struct OrbUniforms {
    var time: Float
    var level: Float
    var swirl: Float
    var hold: Float
    var aspect: Float
    var scale: Float
}
