import type { SkillView, SkillsHubView } from '@memnox/core/wire';
import { X } from 'lucide-react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { SkillOutcome } from '../../../core/application/skills';
import { assignedNote, assignmentChanges, compatibilityLine, conversionLosses, draftFrom, type SkillForm } from '../../../core/domain/skills-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import type { SettingsParts } from '../../settings/parts';

/** A dialog over the page, closed by its X, Escape, or a press outside it. */
export function Dialog({ title, step, close, footer, children }: { title: string; step?: string; close: () => void; footer: ReactNode; children: ReactNode }) {
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [close]);
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 px-4 py-[8vh]" role="presentation" onMouseDown={close}>
      <div role="dialog" aria-modal="true" aria-label={title} className="flex w-full max-w-[560px] flex-col rounded-2xl border border-panel-edge bg-background shadow-2xl" onMouseDown={(event) => event.stopPropagation()}>
        <header className="flex items-center gap-3 border-b border-panel-edge px-5 py-3.5">
          <span className="flex-1 text-headline font-semibold">{title}</span>
          {step !== undefined && <span className="text-footnote text-muted">{step}</span>}
          <button type="button" aria-label="Close" onClick={close} className="mx-focus grid size-7 cursor-pointer place-items-center rounded-md text-muted hover:bg-hover">
            <X size={15} />
          </button>
        </header>
        <div className="flex flex-col gap-4 px-5 py-5">{children}</div>
        <footer className="flex items-center gap-2 border-t border-panel-edge px-5 py-3.5">{footer}</footer>
      </div>
    </div>
  );
}

/**
 * Who a skill is given to, checked per agent with what each keeps of it. Before Continue the dialog says
 * what conversion loses for the agents chosen; giving waits on the island, taking away happens at once.
 */
export function AssignSkillDialog({ parts, view, skill, close, said }: { parts: SettingsParts; view: SkillsHubView; skill: SkillView; close: () => void; said: (note: string) => void }) {
  const { skills, words } = parts;
  const [chosen, setChosen] = useState<ReadonlySet<string>>(() => new Set(skill.agents));
  const [reviewing, setReviewing] = useState(false);
  const [sending, setSending] = useState(false);
  const agents = view.agents.filter((agent) => agent.installed || skill.agents.includes(agent.agent));
  const compatibilityOf = (agent: string) => skill.compatibility.find((each) => each.agent === agent);
  const changes = assignmentChanges(skill.agents, chosen);
  const losses = conversionLosses(skill.compatibility, new Set(changes.give));
  const send = async () => {
    setSending(true);
    const results = await skills.assignTo(skill.name, chosen);
    said(assignedNote(results, words.keyTitle));
    close();
  };
  const toggle = (agent: string) => {
    const next = new Set(chosen);
    if (next.has(agent)) next.delete(agent);
    else next.add(agent);
    setChosen(next);
  };
  const nothing = changes.give.length === 0 && changes.take.length === 0;
  return (
    <Dialog
      title="Assign skill to agents"
      step={reviewing ? 'What changes' : skill.name}
      close={close}
      footer={
        <>
          {reviewing && <KitButton onClick={() => setReviewing(false)}>Back</KitButton>}
          <span className="flex-1" />
          <KitButton kind="primary" disabled={nothing || sending} onClick={() => (reviewing || losses.length === 0 ? void send() : setReviewing(true))}>
            Continue
          </KitButton>
        </>
      }
    >
      {reviewing ? (
        <>
          <p className="text-footnote text-muted">Each agent keeps skills in its own format, and these lose something on the way.</p>
          {losses.map((each) => (
            <div key={each.label} className="flex flex-col gap-1">
              <span className="text-body font-medium text-foreground">{each.label}</span>
              <ul className="flex list-disc flex-col gap-0.5 pl-5 text-footnote text-muted">
                {each.loses.map((loss) => (
                  <li key={loss}>{loss}</li>
                ))}
              </ul>
            </div>
          ))}
        </>
      ) : (
        <div className="flex flex-col gap-1.5">
          {agents.map((agent) => {
            const compatibility = compatibilityOf(agent.agent);
            const takes = compatibility === undefined || compatibility.supported;
            return (
              <label key={agent.agent} className={`flex items-center gap-2.5 rounded-lg px-2 py-1.5 ${takes ? 'cursor-pointer hover:bg-hover' : 'opacity-55'}`}>
                <input type="checkbox" checked={chosen.has(agent.agent)} disabled={!takes} onChange={() => toggle(agent.agent)} />
                <BrandLogo agent={agent.agent} name={agent.label} size={20} />
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="text-body text-foreground">{agent.label}</span>
                  <span className="text-footnote text-muted">{compatibility === undefined ? 'Takes it as written' : compatibilityLine(compatibility)}</span>
                </span>
              </label>
            );
          })}
        </div>
      )}
      <p className="text-footnote text-muted">{`Giving a skill to an agent waits for your signature with ${words.keyTitle} on the island. Taking it away happens at once.`}</p>
    </Dialog>
  );
}

const EMPTY_FORM: SkillForm = { name: '', version: '1.0.0', description: '', category: '', instructions: '', tools: '', commands: '' };

/** A skill written here, kept in the person's Memnox folder; one reaching further than before waits on a signature. */
export function NewSkillDialog({ parts, close, said }: { parts: SettingsParts; close: () => void; said: (outcome: SkillOutcome) => void }) {
  const { skills } = parts;
  const [form, setForm] = useState<SkillForm>(EMPTY_FORM);
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => first.current?.focus(), []);
  const set = (name: keyof SkillForm) => (event: { target: { value: string } }) => setForm({ ...form, [name]: event.target.value });
  const save = async () => {
    const draft = draftFrom(form);
    if (typeof draft === 'string') {
      setProblem(draft);
      return;
    }
    const outcome = await skills.put(draft);
    if (outcome.kind === 'failed') {
      setProblem(outcome.why);
      return;
    }
    said(outcome);
    close();
  };
  const field = 'h-9 w-full rounded-lg border border-field-edge bg-field px-3 text-body text-foreground outline-none placeholder:text-faint focus:border-primary';
  return (
    <Dialog
      title="New skill"
      close={close}
      footer={
        <>
          <span className="flex-1" />
          <KitButton kind="primary" disabled={skills.busy !== undefined} onClick={() => void save()}>
            Add skill
          </KitButton>
        </>
      }
    >
      <div className="grid grid-cols-[minmax(0,1fr)_120px] gap-3">
        <Labelled label="Name">
          <input ref={first} className={field} value={form.name} onChange={set('name')} placeholder="release-notes" />
        </Labelled>
        <Labelled label="Version">
          <input className={field} value={form.version} onChange={set('version')} />
        </Labelled>
      </div>
      <Labelled label="What it is for">
        <input className={field} value={form.description} onChange={set('description')} placeholder="Drafts release notes from merged pull requests" />
      </Labelled>
      <Labelled label="Category, optional">
        <input className={field} value={form.category} onChange={set('category')} placeholder="Writing" />
      </Labelled>
      <Labelled label="Instructions">
        <textarea className={`${field} h-40 py-2 font-mono text-footnote`} value={form.instructions} onChange={set('instructions')} placeholder="What the agent does when this skill applies, step by step." />
      </Labelled>
      <Labelled label="Agent tools it needs, separated by commas">
        <input className={`${field} font-mono`} value={form.tools} onChange={set('tools')} placeholder="Read, Bash" />
      </Labelled>
      <Labelled label="Commands it runs, separated by commas">
        <input className={`${field} font-mono`} value={form.commands} onChange={set('commands')} placeholder="gh, git" />
      </Labelled>
      {problem !== undefined && (
        <p role="alert" className="text-footnote text-destructive">
          {problem}
        </p>
      )}
    </Dialog>
  );
}

export function Labelled({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}
