import AppKit
import MetalKit
import MemnoxVoiceCore
import SwiftUI

/// The Metal orb, hosted as it is so the renderer keeps drawing at whatever size the island gives it.
struct IslandOrbSurface: NSViewRepresentable {
    let view: MTKView
    func makeNSView(context: Context) -> MTKView { view }
    func updateNSView(_ nsView: MTKView, context: Context) {}
}

/// The waveform steps thirty times a second.
private let waveformTick: TimeInterval = 1.0 / 30
/// The level a bar rests at when nothing is heard, and the lowest it ever falls.
private let restingLevel: Float = 0.05
private let barCount = 7

/// Seven bars that move with the voice in or out, and rest low when neither is speaking.
struct IslandWaveform: View {
    let loudness: () -> Float
    let state: VoiceState
    @StateObject private var levels = WaveformLevels()

    private static let barSpacing: CGFloat = 3
    private static let barWidth: CGFloat = 3
    /// A bar's height at rest, and how much taller it grows at full loudness.
    private static let barFloor: CGFloat = 4
    private static let barRise: CGFloat = 12
    /// A bar's opacity at rest, and how much more it gains at full loudness.
    private static let barOpacityFloor = 0.45
    private static let barOpacityRise = 0.55

    var body: some View {
        TimelineView(.animation(minimumInterval: waveformTick)) { timeline in
            let values = levels.next(at: timeline.date, heard: live ? loudness() : restingLevel)
            HStack(alignment: .center, spacing: Self.barSpacing) {
                ForEach(values.indices, id: \.self) { index in
                    Capsule()
                        .fill(Memnox.Palette.sky.opacity(Self.barOpacityFloor + Double(values[index]) * Self.barOpacityRise))
                        .frame(width: Self.barWidth, height: Self.barFloor + CGFloat(values[index]) * Self.barRise)
                }
            }
        }
    }

    private var live: Bool { state == .listening || state == .speaking }
}

/// The waveform's recent levels, kept outside the view so redrawing never resets them.
@MainActor
final class WaveformLevels: ObservableObject {
    private var history = [Float](repeating: restingLevel, count: barCount)
    private var last = Date.distantPast

    func next(at moment: Date, heard: Float) -> [Float] {
        if moment.timeIntervalSince(last) >= waveformTick {
            last = moment
            history.removeFirst()
            history.append(min(max(heard, restingLevel), 1))
        }
        return history
    }
}
