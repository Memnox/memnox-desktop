import type { DaemonRequest, DaemonResponse } from '@memnox/core/wire';

/** How the app reaches the daemon: the socket or the named pipe in Rust, a script in tests. */
export interface DaemonLink {
  /** Every line the daemon writes back for one request, until it closes. Throws when nothing answered. */
  stream(request: DaemonRequest): AsyncIterable<DaemonResponse>;
}

/** Thrown when the daemon closed before it answered at all. */
export class DaemonClosed extends Error {
  constructor() {
    super('the daemon closed before it answered');
  }
}

/** The first answer, for the methods that answer once. */
export async function requestOnce(link: DaemonLink, request: DaemonRequest): Promise<DaemonResponse> {
  for await (const response of link.stream(request)) return response;
  throw new DaemonClosed();
}
