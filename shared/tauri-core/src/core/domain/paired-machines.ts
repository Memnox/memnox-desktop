/** A server this computer paired with over the relay, as the pages are told of it: no key and no token, which stay in Rust. */
export interface PairedServer {
  readonly machineId: string;
  /** The name it paired under, which every label of its calls says. */
  readonly machine: string;
  /** This computer's id in that server's device registry, which the server stamps on this computer's own asks. */
  readonly deviceId: string;
  /** Epoch milliseconds. */
  readonly pairedAt: number;
}

/** The rules over the servers kept, apart from any store so they are tested alone. Ported from the Mac's `PairedMachines`. */
export const PairedMachines = {
  /** One record per machine, the newest pairing kept, oldest pairing first. */
  distinct(servers: readonly PairedServer[]): PairedServer[] {
    const newest = new Map<string, PairedServer>();
    for (const server of servers) {
      const kept = newest.get(server.machineId);
      if (kept === undefined || kept.pairedAt < server.pairedAt) newest.set(server.machineId, server);
    }
    return [...newest.values()].sort((a, b) => a.pairedAt - b.pairedAt);
  },

  /** The server last chosen while it is still paired, or undefined for this computer. */
  chosen(servers: readonly PairedServer[], chosen: string | undefined): PairedServer | undefined {
    return chosen === undefined ? undefined : servers.find((server) => server.machineId === chosen);
  },
};
