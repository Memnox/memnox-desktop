import MemnoxVoiceCore
import SwiftUI

/// Hand over: the one action people keep saying yes to, offered as a rule that lets it run on its own. Budgets and
/// autopilot join it as tabs once this Mac's runtime answers them, so nothing here is a promise.
struct HandOverDestination: View {
    @ObservedObject var home: HomeModel
    let width: WidthClass

    var body: some View {
        ShellScroll(width: width) {
            if let ready = home.home?.ready {
                HomeReadyCard(ready: ready, busy: home.handingOver, note: home.handOverNote) { home.handOver(ready) }
            } else {
                EmptyState(symbol: "gauge.with.dots.needle.67percent", title: "Nothing to hand over yet",
                           detail: HomeBriefBlock.ready.none)
            }
        }
    }
}
