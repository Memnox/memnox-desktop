import type { VoiceAgentStatus } from '@memnox/core/wire';
import { Observed } from '../../core/application/observed';
import type { KeyStatus } from '../../core/domain/key-status';
import { permissionSteps, waitingSteps, type PermissionFacts, type PermissionStep } from '../../core/domain/permission-steps';
import { keyStep } from '../../core/domain/platform';
import { agentsDetail, agentsStep, nameStep, serviceStep, voiceDetail, voiceStep, type SetupFacts, type VoiceInstall } from '../../core/domain/setup-steps';
import { needs, type StepState } from '../../core/domain/step-state';
import type { SettingsParts } from './parts';

/**
 * Where every setup step stands, as the Mac's `SetupModel` holds it for the overview, Permissions, Connection,
 * Voice and the first run alike: read when a page shows, and again when the person presses Check again.
 * The rules that turn these readings into steps live in the core; this only gathers them.
 */
export class SetupModel extends Observed {
  private facts: PermissionFacts | undefined;
  private key: KeyStatus | undefined;
  private found: readonly VoiceAgentStatus[] = [];
  private agentsWhy: string | undefined;
  private checking = false;
  private rechecked = false;
  private install: VoiceInstall = { kind: 'idle' };
  private starts: boolean | undefined;
  private serviceReady: boolean | undefined;

  constructor(private readonly parts: SettingsParts) {
    super();
    parts.setup.observe(() => this.changed());
  }

  get permissions(): readonly PermissionStep[] {
    return this.facts === undefined ? waitingSteps() : permissionSteps(this.facts);
  }

  get keyState(): StepState {
    return keyStep(this.key, this.parts.host.platform);
  }

  get agents(): readonly VoiceAgentStatus[] {
    return this.found;
  }

  get checkingAgents(): boolean {
    return this.checking;
  }

  get agentsState(): StepState {
    if (this.agentsWhy !== undefined) return needs(this.agentsWhy);
    return agentsStep(this.found);
  }

  get agentsDetail(): string {
    return agentsDetail(this.found, this.checking);
  }

  get voiceInstall(): VoiceInstall {
    return this.install;
  }

  get startsAtSignIn(): boolean | undefined {
    return this.starts;
  }

  get service(): { state: StepState; detail: string } {
    const { doing, failed, runtime } = this.parts.setup.state;
    const ready = runtime === undefined ? this.serviceReady : runtime.kind === 'ready';
    return serviceStep(ready, doing, failed);
  }

  /** The eight steps the overview counts. */
  setupFacts(name: string): SetupFacts {
    const [hear, type, see] = this.permissions;
    const service = this.service;
    return {
      name: nameStep(name),
      hear: hear?.state ?? needs(''),
      type: type?.state ?? needs(''),
      see: see?.state ?? needs(''),
      service: service.state,
      serviceDetail: service.detail,
      key: this.keyState,
      agents: this.agentsState,
      agentsDetail: this.agentsDetail,
      voice: voiceStep(this.install),
      voiceDetail: voiceDetail(this.install),
    };
  }

  /** Everything that can be checked without asking the person, read as a page opens. */
  async refresh(): Promise<void> {
    await Promise.all([this.readPermissions(), this.readService(), this.readVoice(), this.readStarts(), this.loadAgents(false)]);
  }

  async readPermissions(): Promise<void> {
    this.facts = await this.parts.host.permissionFacts().catch(() => this.facts);
    this.changed();
  }

  /** Check again on the service row: setup installs, starts or updates it, then the key is registered. */
  async checkService(): Promise<void> {
    const state = await this.parts.setup.ensure();
    this.serviceReady = state.kind === 'ready';
    this.key = await this.parts.signer.registerKey();
    this.changed();
  }

  private async readService(): Promise<void> {
    const state = await this.parts.setup.check();
    this.serviceReady = state.kind === 'ready';
    this.key = state.kind === 'ready' ? await this.parts.signer.registerKey() : { kind: 'unreachable' };
    this.changed();
  }

  async checkKey(): Promise<void> {
    this.key = await this.parts.signer.registerKey();
    this.changed();
  }

  /** The agents from the daemon's last check, or every one asked again when the person says so. */
  async loadAgents(recheck: boolean): Promise<void> {
    this.checking = true;
    this.changed();
    const answer = await this.parts.voiceSettings.agents(recheck);
    this.apply(answer);
    this.checking = false;
    this.changed();
  }

  /** On the first run every agent is asked afresh once, since a saved answer can be days old. */
  async recheckOnce(): Promise<void> {
    if (this.rechecked) return;
    this.rechecked = true;
    await this.loadAgents(true);
  }

  async useAgent(kind: string): Promise<void> {
    this.apply(await this.parts.voiceSettings.choose(kind));
    this.changed();
  }

  private apply(answer: Awaited<ReturnType<SettingsParts['voiceSettings']['agents']>>): void {
    if (answer.kind === 'listed') {
      this.found = answer.agents;
      this.agentsWhy = undefined;
    } else {
      this.agentsWhy = answer.why === 'Memnox did not answer' ? 'Waiting for the Memnox service' : answer.why;
    }
  }

  private async readVoice(): Promise<void> {
    if (this.install.kind === 'installing') return;
    const installed = await this.parts.host.voices.installed().catch(() => false);
    this.install = installed ? { kind: 'done' } : this.install.kind === 'failed' ? this.install : { kind: 'idle' };
    this.changed();
  }

  /** Installs the natural voice, the row's Try again; the system voice speaks until it is in. */
  async installVoice(): Promise<void> {
    if (this.install.kind === 'installing') return;
    this.install = { kind: 'installing', percent: undefined };
    this.changed();
    try {
      await this.parts.host.voices.install((step) => {
        this.install = { kind: 'installing', percent: step.total === null || step.total === 0 ? undefined : Math.round((step.done / step.total) * 100) };
        this.changed();
      });
      this.install = { kind: 'done' };
    } catch (error) {
      this.install = { kind: 'failed', why: String(error) };
    }
    this.changed();
  }

  private async readStarts(): Promise<void> {
    this.starts = await this.parts.host.startsAtSignIn().catch(() => undefined);
    this.changed();
  }

  async setStartsAtSignIn(on: boolean): Promise<void> {
    this.starts = on;
    this.changed();
    this.starts = await this.parts.host.setStartsAtSignIn(on).catch(() => !on);
    this.changed();
  }
}
