import Foundation

/// The rules over the machines a phone is paired with, kept apart from any store so they are tested alone.
public enum PairedMachines {
    /// One record per machine, the newest pairing kept, oldest pairing first.
    public static func distinct(_ machines: [PairedMachine]) -> [PairedMachine] {
        var newest: [String: PairedMachine] = [:]
        for machine in machines {
            if let kept = newest[machine.machineId], kept.pairedAt >= machine.pairedAt { continue }
            newest[machine.machineId] = machine
        }
        return newest.values.sorted { $0.pairedAt < $1.pairedAt }
    }

    /// The machine to talk to: the one last chosen while it is still paired, otherwise the newest pairing.
    public static func active(in machines: [PairedMachine], chosen: String?) -> PairedMachine? {
        if let chosen, let found = machines.first(where: { $0.machineId == chosen }) { return found }
        return machines.last
    }
}
