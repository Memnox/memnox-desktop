import AppKit
import SwiftUI

extension View {
    /// The pointing hand while the pointer is over this, so anything clickable says so before it is pressed.
    func pointingHand() -> some View {
        modifier(PointingHand())
    }
}

/// Pushes the hand once on entering and pops it once on leaving, so the cursor stack never holds a stray hand.
private struct PointingHand: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { over in show(over && isEnabled) }
            // A disabled button is not clickable, so it drops the hand it was showing.
            .onChange(of: isEnabled) { _, enabled in if !enabled { show(false) } }
            // A view that goes away under the pointer gets no exit, so it hands the hand back here.
            .onDisappear { show(false) }
    }

    private func show(_ hand: Bool) {
        guard hand != pushed else { return }
        pushed = hand
        if hand { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}
