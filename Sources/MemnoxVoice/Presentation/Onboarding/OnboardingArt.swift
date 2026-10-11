import AppKit
import MetalKit
import SwiftUI

/// The picture beside every step: a Mac on one of the website's pixel landscapes, with the real island and orb playing
/// what Memnox does through `IslandDemo`, so setting up shows the product rather than a picture of it.
struct OnboardingArt: View {
    /// Told which part the notch is playing, so the welcome step lights the same one.
    var highlighted: (Highlight?) -> Void = { _ in }
    @StateObject private var demo = IslandDemo()

    var body: some View {
        Stage(scene: "galata") { MacScene(demo: demo) }
            .onAppear { demo.play(.highlights) }
            .onChange(of: demo.chapter) { _, chapter in highlighted(chapter) }
            .onDisappear { demo.stop() }
    }
}

/// A scene: the landscape in its pixels, cropped to fill a rounded panel, with the device set on it.
private struct Stage<Content: View>: View {
    let scene: String
    @ViewBuilder let content: () -> Content

    private static var radius: CGFloat { 24 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        // The panel takes the room it is given and the landscape fills behind it, so the photo never widens the panel.
        content()
            .padding(ArtMetrics.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if let image = sceneImage(scene) {
                    Image(nsImage: image).resizable().interpolation(.none).scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0x86B3C9), Color(hex: 0x4F7BB3)], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(shape)
        .overlay(shape.strokeBorder(Memnox.ink(Memnox.Ink.rim), lineWidth: Memnox.Stroke.hairline))
        .accessibilityHidden(true)
    }
}

/// One of the website's scenes, from the app's Scenes folder; nil when run outside the bundle, which draws a sky instead.
private func sceneImage(_ name: String) -> NSImage? {
    Bundle.main.url(forResource: name, withExtension: "webp", subdirectory: "Scenes").flatMap(NSImage.init(contentsOf:))
}

private enum ArtMetrics {
    static let inset: CGFloat = 24
    static let bezel = Color(hex: 0x0C0C0D)
}

/// The top of a Mac's screen, close up, as the website frames its notch: the lid's bezel, the sky, the menu bar and
/// the real island grown out of the notch at its real size, so it fills the picture rather than sitting small in it.
/// The bottom fades into the landscape, since this is a crop of a screen rather than the whole laptop.
private struct MacScene: View {
    @ObservedObject var demo: IslandDemo

    private enum Layout {
        static let screen = CGSize(width: 800, height: 620)
        static let bezel: CGFloat = 14
        static let menuBar: CGFloat = 32
        static let screenRadius: CGFloat = 20
        static let lidRadius: CGFloat = 32
        static var whole: CGSize { CGSize(width: screen.width + bezel * 2, height: screen.height + bezel) }
    }

    var body: some View {
        DesignFit(size: Layout.whole) {
            ZStack(alignment: .top) {
                Group {
                    if let sky = sceneImage("sky") {
                        Image(nsImage: sky).resizable().interpolation(.none).scaledToFill()
                    } else {
                        Memnox.Palette.deep
                    }
                }
                .frame(width: Layout.screen.width, height: Layout.screen.height)
                .clipped()
                menuBar
                IslandDemoView(demo: demo)
            }
            .frame(width: Layout.screen.width, height: Layout.screen.height)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: Layout.screenRadius, topTrailingRadius: Layout.screenRadius))
            .padding([.top, .horizontal], Layout.bezel)
            .background(UnevenRoundedRectangle(topLeadingRadius: Layout.lidRadius, topTrailingRadius: Layout.lidRadius)
                .fill(ArtMetrics.bezel))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .frame(width: Layout.whole.width, height: Layout.whole.height)
        }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
    }

    /// The menu bar either side of the notch, which the island covers.
    private var menuBar: some View {
        HStack {
            HStack(spacing: 18) {
                Image(systemName: "apple.logo").font(.system(size: 16))
                Text("Terminal").font(.system(size: 14, weight: .semibold))
                Text("Shell").font(.system(size: 14))
            }
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "wifi")
                Text("9:41 AM")
            }
            .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 20)
        .frame(height: Layout.menuBar)
        .background(Color.black.opacity(0.18))
    }
}
