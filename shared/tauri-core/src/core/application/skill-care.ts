import { SKILLS_METHOD, type DaemonRequest, type DaemonResponse, type SkillCalibration, type SkillStatsView, type SkillView } from '@memnox/core/wire';
import { NOTHING_TO_FIX, noteLine } from '../domain/skill-care-lines';
import { Observed } from './observed';
import { requestOnce, type DaemonLink } from './ports/daemon-link';
import type { RequestIds } from './request-ids';
import type { SkillOutcome } from './skills';

const SILENT = 'The runtime is not answering.';
const REFUSED = 'The runtime refused this.';

/**
 * Skills that improve with use, ported from the Mac's `SkillCare`: each skill's uses, failures and refusals, its fix
 * backlog, and a suggested fix the runtime built by rule. Accepting goes through skill-put like any new version, so
 * one that reaches further waits for a signature on the island and nothing here grants anything.
 */
export class SkillCare extends Observed {
  private counted = new Map<string, SkillStatsView>();
  private suggested: SkillCalibration | undefined;
  private read = false;
  private busyWith: string | undefined;

  constructor(
    private readonly link: DaemonLink,
    private readonly ids: RequestIds,
  ) {
    super();
  }

  stats(name: string): SkillStatsView | undefined {
    return this.counted.get(name);
  }

  /** The suggestion last built, for the skill it names. */
  get calibration(): SkillCalibration | undefined {
    return this.suggested;
  }

  /** Whether the runtime answered the counts at all; an older one does not, and the page leaves them out. */
  get answered(): boolean {
    return this.read;
  }

  get busy(): string | undefined {
    return this.busyWith;
  }

  async refresh(): Promise<void> {
    this.take(await this.ask({ method: SKILLS_METHOD.SKILL_STATS }));
    this.changed();
  }

  /** One line added to the skill's backlog; the skill itself is not touched. */
  async note(name: string, typed: string): Promise<SkillOutcome> {
    const line = noteLine(typed);
    if (line === undefined) return { kind: 'failed', why: 'Say what to note.' };
    const response = await this.working(name, () => this.ask({ method: SKILLS_METHOD.SKILL_NOTE, skillName: name, skillNote: line }));
    const failed = failure(response);
    if (failed !== undefined) return failed;
    this.take(response);
    this.changed();
    return { kind: 'done', note: `Noted for ${name}.` };
  }

  /** Asks the runtime for a suggested fix; nothing changes until Accept. */
  async calibrate(name: string): Promise<SkillOutcome> {
    const response = await this.working(name, () => this.ask({ method: SKILLS_METHOD.SKILL_CALIBRATE, skillName: name }));
    const failed = failure(response);
    if (failed !== undefined) return failed;
    this.suggested = response?.skillCalibration;
    this.changed();
    return { kind: 'done', note: this.suggested === undefined ? NOTHING_TO_FIX : `A fix is suggested for ${name}.` };
  }

  /** Sends the suggested version through skill-put, naming the project it lives in so it lands there. */
  async accept(calibration: SkillCalibration, scope: SkillView['scope'], project: string | undefined): Promise<SkillOutcome> {
    const response = await this.working(calibration.name, () =>
      this.ask({ method: SKILLS_METHOD.SKILL_PUT, skillDraft: calibration.draft, skillScope: scope, ...(project === undefined ? {} : { skillProject: project }) }),
    );
    const failed = failure(response);
    if (failed !== undefined) return failed;
    this.suggested = undefined;
    this.changed();
    if (response?.proposed !== undefined) return { kind: 'proposed', id: response.proposed };
    return { kind: 'done', note: `${calibration.name} ${calibration.draft.version} is in the hub now.` };
  }

  dismissSuggestion(): void {
    this.suggested = undefined;
    this.changed();
  }

  private take(response: DaemonResponse | undefined): void {
    const stats = response?.skillStats;
    if (stats === undefined) return;
    this.read = true;
    this.counted = new Map(stats.map((each) => [each.name, each]));
  }

  private async working<T>(subject: string, body: () => Promise<T>): Promise<T> {
    this.busyWith = subject;
    this.changed();
    const result = await body();
    this.busyWith = undefined;
    this.changed();
    return result;
  }

  private async ask(fields: Omit<DaemonRequest, 'id'>): Promise<DaemonResponse | undefined> {
    try {
      // Cast is safe: every caller passes a skills method and only the fields it reads.
      return await requestOnce(this.link, { id: this.ids.next(), ...fields } as DaemonRequest);
    } catch {
      return undefined;
    }
  }
}

function failure(response: DaemonResponse | undefined): SkillOutcome | undefined {
  if (response === undefined) return { kind: 'failed', why: SILENT };
  if (!response.ok) return { kind: 'failed', why: response.error ?? REFUSED };
  return undefined;
}
