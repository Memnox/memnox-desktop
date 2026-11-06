import type { FoundSkillView, SkillView, SkillsHubView } from '@memnox/core/wire';
import { useEffect, useRef, useState } from 'react';
import type { SkillOutcome } from '../../../core/application/skills';
import { assignedNote, assignmentChanges, compatibilityLine, conversionLosses, draftFrom, SkillSheetLines, type SkillForm } from '../../../core/domain/skills-lines';
import { FOUND_UNREADABLE, homeOf, instructionsFile, shortPath, skillDocument } from '../../../core/domain/skill-search';
import { MarkdownText } from '../../cards/MarkdownText';
import type { SettingsParts } from '../../settings/parts';
import { KitLines } from '../../../core/domain/kit-lines';
import { BrandLogo, Button, Checkbox, Dialog, ErrorLine, Field, Input, MiddleCut, Spinner, Textarea } from '../../kit';
import { PAGE_METRICS } from '../page-metrics';

/** `SheetLayout`: an agent's logo in the assign list, the version column, and the instructions editor's height. */
const AGENT_LOGO = 20;
const VERSION_WIDTH = PAGE_METRICS.skillVersion;
const INSTRUCTIONS_HEIGHT = PAGE_METRICS.skillInstructions;

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
      title={SkillSheetLines.assignTitle}
      step={reviewing ? SkillSheetLines.whatChanges : skill.name}
      close={close}
      actions={
        <>
          {reviewing && <Button onClick={() => setReviewing(false)}>{SkillSheetLines.back}</Button>}
          <span className="flex-1" />
          <Button kind="primary" disabled={nothing || sending} onClick={() => (reviewing || losses.length === 0 ? void send() : setReviewing(true))}>
            {SkillSheetLines.continue}
          </Button>
        </>
      }
    >
      {reviewing ? (
        <>
          <p className="text-footnote text-muted">{SkillSheetLines.losesIntro}</p>
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
        <div className="flex flex-col">
          {agents.map((agent) => {
            const compatibility = compatibilityOf(agent.agent);
            const takes = compatibility === undefined || compatibility.supported;
            return (
              <div key={agent.agent} className={`py-1 ${takes ? '' : 'opacity-55'}`}>
                <Checkbox checked={chosen.has(agent.agent)} disabled={!takes} onToggle={() => toggle(agent.agent)}>
                  <span className="flex min-w-0 items-center gap-2.5">
                    <BrandLogo agent={agent.agent} name={agent.label} size={AGENT_LOGO} />
                    <span className="flex min-w-0 flex-col gap-0.5">
                      <span className="text-body text-foreground">{agent.label}</span>
                      <span className="text-footnote text-muted">{compatibility === undefined ? SkillSheetLines.asWritten : compatibilityLine(compatibility)}</span>
                    </span>
                  </span>
                </Checkbox>
              </div>
            );
          })}
        </div>
      )}
      <p className="text-footnote text-muted">{SkillSheetLines.givingWaits(words.keyTitle)}</p>
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
  const set = (name: keyof SkillForm) => (value: string) => setForm({ ...form, [name]: value });
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
  return (
    <Dialog
      title={SkillSheetLines.newTitle}
      close={close}
      actions={
        <>
          <span className="flex-1" />
          <Button kind="primary" disabled={skills.busy !== undefined} onClick={() => void save()}>
            {SkillSheetLines.addSkill}
          </Button>
        </>
      }
    >
      <div className="grid gap-3" style={{ gridTemplateColumns: `minmax(0,1fr) ${VERSION_WIDTH}px` }}>
        <Field label={SkillSheetLines.name}>
          <Input ref={first} wide value={form.name} onValue={set('name')} placeholder={SkillSheetLines.namePlaceholder} />
        </Field>
        <Field label={SkillSheetLines.version}>
          <Input wide value={form.version} onValue={set('version')} aria-label={SkillSheetLines.version} />
        </Field>
      </div>
      <Field label={SkillSheetLines.purpose}>
        <Input wide value={form.description} onValue={set('description')} placeholder={SkillSheetLines.purposePlaceholder} />
      </Field>
      <Field label={SkillSheetLines.category}>
        <Input wide value={form.category} onValue={set('category')} placeholder={SkillSheetLines.categoryPlaceholder} />
      </Field>
      <Field label={SkillSheetLines.instructions}>
        <Textarea mono className="text-footnote" style={{ height: INSTRUCTIONS_HEIGHT }} value={form.instructions} onValue={set('instructions')} placeholder={SkillSheetLines.instructionsPlaceholder} />
      </Field>
      <Field label={SkillSheetLines.tools}>
        <Input wide mono className="text-footnote" value={form.tools} onValue={set('tools')} placeholder={SkillSheetLines.toolsPlaceholder} />
      </Field>
      <Field label={SkillSheetLines.commands}>
        <Input wide mono className="text-footnote" value={form.commands} onValue={set('commands')} placeholder={SkillSheetLines.commandsPlaceholder} />
      </Field>
      {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
    </Dialog>
  );
}

/**
 * A skill an agent already has, read from its own SKILL.md and drawn formatted, as the Mac's `FoundSkillSheet`, with
 * Import at the foot so reading it and bringing it in are one place. Nothing here writes to the agent's file.
 */
export function FoundSkillDialog({ parts, found, label, importing, close, said }: { parts: SettingsParts; found: FoundSkillView; label: string; importing: boolean; close: () => void; said: (outcome: SkillOutcome) => void }) {
  const { skills, host } = parts;
  const file = instructionsFile(found);
  const [text, setText] = useState<string | undefined | null>(null);
  useEffect(() => {
    if (host.readSkillFile === undefined) return setText(undefined);
    void host.readSkillFile(file).then(setText);
  }, [file]);
  const document = typeof text === 'string' ? skillDocument(text) : undefined;
  return (
    <Dialog
      title={found.name}
      step={label}
      close={close}
      cancel={KitLines.close}
      actions={
        <>
          <span className="flex-1" />
          <Button
            kind="primary"
            disabled={skills.busy !== undefined || importing}
            onClick={() => {
              void skills.importFound(found.id, found.name).then(said);
              close();
            }}
          >
            {SkillSheetLines.import}
          </Button>
        </>
      }
    >
      <span className="block min-w-0 overflow-hidden text-muted select-text">
        <MiddleCut text={shortPath(file, homeOf(file))} className="font-code text-label" />
      </span>
      {document !== undefined ? (
        <>
          {document.fields.length > 0 && (
            <>
              <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-footnote">
                {document.fields.map((field) => (
                  <div key={field.key} className="contents">
                    <dt className="text-muted">{field.key}</dt>
                    <dd className="min-w-0 break-words text-foreground">{field.value}</dd>
                  </div>
                ))}
              </dl>
              <hr className="border-panel-edge" />
            </>
          )}
          <MarkdownText source={document.body} tone="window" onLink={(href) => host.openPage(href)} />
        </>
      ) : text === undefined ? (
        <p className="text-footnote text-muted">{FOUND_UNREADABLE}</p>
      ) : (
        <Spinner />
      )}
    </Dialog>
  );
}
