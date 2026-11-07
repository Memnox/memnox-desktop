import Foundation

// Where the detail card of a picked node stands on the canvas, by the console's own steps (arms-anchor.ts): on the
// node's right where there is room, else its left, else below or above it, and always inside the canvas, with the
// pointer along the edge facing the node so it still points at it when the card is pushed in. Asked again every
// frame, so the card follows the node as the map pans, zooms and turns.

/// Which side of the node the card stands on.
public enum BrainCardSide: String, Sendable {
    case right
    case left
    case below
    case above
}

/// The card's place on the screen: its top left corner, its side, where the pointer sits from that corner on the
/// edge facing the node, and whether the node is on the canvas at all.
public struct BrainCardSpot: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let side: BrainCardSide
    public let pointer: (x: Double, y: Double)
    public let visible: Bool

    public static func == (left: BrainCardSpot, right: BrainCardSpot) -> Bool {
        left.x == right.x && left.y == right.y && left.side == right.side && left.pointer.x == right.pointer.x
            && left.pointer.y == right.pointer.y && left.visible == right.visible
    }
}

public enum BrainCard {
    /// The air between the node's rim and the card, and between the card and the canvas edge, the console's.
    public static let gap = 14.0
    public static let margin = 10.0
    /// The pointer stays this far from the card's corners, so it never runs off a rounded one.
    public static let pointerInset = 16.0

    /// The card beside a node of this radius at this spot, trying the right, the left, below and above in turn,
    /// and where none fits whole, the side with more room pushed inside the canvas.
    public static func place(_ node: (x: Double, y: Double), radius: Double, card: (width: Double, height: Double),
                             canvas: (width: Double, height: Double)) -> BrainCardSpot {
        let visible = node.x >= 0 && node.y >= 0 && node.x <= canvas.width && node.y <= canvas.height
        let sideTop = clamp(node.y - card.height / 2, margin, canvas.height - card.height - margin)
        let sideLeft = clamp(node.x - card.width / 2, margin, canvas.width - card.width - margin)
        let along = { (at: Double, start: Double, length: Double) in clamp(at - start, pointerInset, length - pointerInset) }
        let right = node.x + radius + gap
        let left = node.x - radius - gap - card.width
        let below = node.y + radius + gap
        let above = node.y - radius - gap - card.height
        let beside = { (x: Double, side: BrainCardSide, edge: Double) in
            BrainCardSpot(x: x, y: sideTop, side: side, pointer: (edge, along(node.y, sideTop, card.height)), visible: visible)
        }
        let over = { (y: Double, side: BrainCardSide, edge: Double) in
            BrainCardSpot(x: sideLeft, y: y, side: side, pointer: (along(node.x, sideLeft, card.width), edge), visible: visible)
        }
        if right + card.width <= canvas.width - margin { return beside(right, .right, 0) }
        if left >= margin { return beside(left, .left, card.width) }
        if below + card.height <= canvas.height - margin { return over(below, .below, 0) }
        if above >= margin { return over(above, .above, card.height) }
        let roomy = canvas.width - node.x >= node.x ? beside(right, .right, 0) : beside(left, .left, card.width)
        return BrainCardSpot(x: clamp(roomy.x, margin, canvas.width - card.width - margin), y: roomy.y, side: roomy.side,
                             pointer: roomy.pointer, visible: visible)
    }

    /// A value held between two bounds, the least winning where the bounds cross, as the console clamps.
    private static func clamp(_ value: Double, _ least: Double, _ most: Double) -> Double {
        most < least ? least : min(most, max(least, value))
    }
}
