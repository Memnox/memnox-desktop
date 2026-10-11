import AppKit
import SwiftUI

/// How content leaves and arrives: out quickly with a blur, in a moment later once the island has started to grow.
struct ContentFade: ViewModifier {
    let shown: Bool

    private static let hiddenBlur: CGFloat = 8
    private static let hiddenScale: CGFloat = 0.97

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : Self.hiddenBlur)
            .scaleEffect(shown ? 1 : Self.hiddenScale)
    }
}

/// How long content takes to leave, which is also how long the new content waits before arriving.
private let contentHandoff: TimeInterval = 0.16

extension AnyTransition {
    /// Out in 160 ms, in over 300 ms after a 160 ms wait, so the old content is gone before the new arrives.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: ContentFade(shown: false), identity: ContentFade(shown: true))
                .animation(.easeOut(duration: Memnox.Motion.standard).delay(contentHandoff)),
            removal: .modifier(active: ContentFade(shown: false), identity: ContentFade(shown: true))
                .animation(.easeIn(duration: contentHandoff))
        )
    }
}

/// A side to side shake that dies away, played once each time the count goes up.
struct ShakeEffect: GeometryEffect {
    var times: CGFloat

    /// Six half swings make three back and forths in one shake.
    private static let halfSwings: CGFloat = 6
    private static let reach: CGFloat = 9
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = times - floor(times)
        let offset = sin(progress * .pi * Self.halfSwings) * Self.reach * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}

/// A little swell and back, played once each time the count goes up, hung from the top edge.
struct HopEffect: GeometryEffect {
    var times: CGFloat

    /// The share the island grows by at the top of the hop.
    private static let swell: CGFloat = 0.05
    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let progress = times - floor(times)
        let lift = sin(progress * .pi) * Self.swell
        let scale = CGAffineTransform(translationX: size.width / 2, y: 0)
            .scaledBy(x: 1 + lift, y: 1 + lift)
            .translatedBy(x: -size.width / 2, y: 0)
        return ProjectionTransform(scale)
    }
}

/// A slow breath on the held call's dot, so the eye finds what is waiting.
struct PulseEffect: ViewModifier {
    /// Seconds from rest to full breath; a whole breath in and out takes twice this.
    private static let halfBreath: TimeInterval = 0.9
    private static let swell = 0.35
    private static let fade = 0.4

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let breath = (sin(timeline.date.timeIntervalSinceReferenceDate * .pi / Self.halfBreath) + 1) / 2
            content
                .scaleEffect(1 + Self.swell * breath)
                .opacity(1 - Self.fade * breath)
        }
    }
}

/// A session's logo beside the notch: hopping while a call of its waits on the person, and shivering
/// grey for a moment after something went wrong, so a glance at the bar says which agent it was.
struct LogoMood: ViewModifier {
    let bouncing: Bool
    let stumbling: Bool

    /// How high a hop goes, and how many hops a second, kept small since the logo is sixteen points.
    private static let hopHeight: CGFloat = 3
    private static let hopsPerSecond: Double = 1.1
    private static let shiverReach: CGFloat = 1.5
    private static let shiverRate: Double = 55

    func body(content: Content) -> some View {
        // Paused when there is nothing to show, so a quiet bar costs no frames.
        TimelineView(.animation(minimumInterval: nil, paused: !bouncing && !stumbling)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let hop = bouncing ? -abs(sin(seconds * .pi * Self.hopsPerSecond)) * Self.hopHeight : 0
            let shiver = stumbling ? sin(seconds * Self.shiverRate) * Self.shiverReach : 0
            content
                .offset(x: shiver, y: hop)
                .saturation(stumbling ? 0 : 1)
        }
    }
}
