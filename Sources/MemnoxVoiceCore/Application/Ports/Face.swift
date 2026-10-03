import Foundation

/// The orb and the pill, told what to show.
public protocol Face: AnyObject {
    func show(_ state: VoiceState, caption: String)
}
