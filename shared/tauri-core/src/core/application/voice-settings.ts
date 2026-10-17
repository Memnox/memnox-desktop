import { DAEMON_METHOD, type DaemonRequest, type VoiceAgentStatus } from '@memnox/core/wire';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';

/** The agents the voice can think with, preferred first, or why the daemon could not say. */
export type VoiceAgents = { kind: 'listed'; agents: readonly VoiceAgentStatus[] } | { kind: 'failed'; why: string };

/** Which of the person's own agents the voice thinks with, chosen in settings and kept by the daemon. */
export class VoiceSettings {
  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {}

  /** Every agent the voice knows; `recheck` asks each installed agent again rather than answering from the last check. */
  agents(recheck = false): Promise<VoiceAgents> {
    const request: DaemonRequest = { id: this.ids.next(), method: DAEMON_METHOD.VOICE_AGENTS };
    if (recheck) request.recheck = true;
    return this.answer(request);
  }

  choose(kind: string): Promise<VoiceAgents> {
    return this.answer({ id: this.ids.next(), method: DAEMON_METHOD.CHOOSE_VOICE_AGENT, voiceAgent: kind });
  }

  private async answer(request: DaemonRequest): Promise<VoiceAgents> {
    const response = await requestOnce(this.link, request).catch(() => undefined);
    if (response === undefined) return { kind: 'failed', why: 'Memnox did not answer' };
    if (!response.ok || response.voiceAgents === undefined) return { kind: 'failed', why: response.error ?? 'Memnox did not say' };
    return { kind: 'listed', agents: response.voiceAgents };
  }
}
