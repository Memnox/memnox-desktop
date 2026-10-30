import type { PolicyRuleView, RuleVerdictView } from '@memnox/core/wire';
import { Download, FlaskConical, Plus, ShieldCheck, Upload } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { RuleDraftInput, StudioOutcome } from '../../../core/application/studio';
import type { WidthClass } from '../../../core/domain/destinations';
import { canInstall, installWaitsLine, latestLine, publisherLine } from '../../../core/domain/index-lines';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { ALWAYS_ASK, almostLine, autopilotLine, countsByEffect, draftSentence, EFFECT_WORDS, effectTone, exportedCount, sourceWords, switchOn, weekLine, type Effect } from '../../../core/domain/studio-lines';
import { KitButton, Switch } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { EmptyState, Inspector, Panel, ReadFailed, Row, Section, StatusWord } from '../widgets';

type Filter = 'all' | Effect;

/**
 * What agents may do here, read first and changed second. Every rule is said as a sentence before its
 * fields, and a rule built here only goes in force once the person signs it on the island.
 */
export function PoliciesPage({ parts, width }: { parts: SettingsParts; width: WidthClass }) {
  const { studio } = parts;
  useObserved(studio);
  useEffect(() => {
    void studio.refresh();
  }, []);
  useEffect(() => parts.host.onHomeStale?.(() => void studio.refresh()), []);
  const [filter, setFilter] = useState<Filter>('all');
  const [chosen, choose] = useState<string | undefined>(undefined);
  const [building, setBuilding] = useState<Partial<RuleDraftInput> | undefined>(undefined);
  const [note, setNote] = useState<string | undefined>(undefined);
  const said = (outcome: StudioOutcome) => setNote(noteOf(outcome, parts.words.keyTitle));

  const view = studio.rules;
  if (view === undefined) return studio.unreadable ? <ReadFailed what="the rules" retry={() => void studio.refresh()} /> : null;
  const counts = countsByEffect(view.rules);
  const shown = view.rules.filter((rule) => filter === 'all' || rule.effect === filter);
  const picked = view.rules.find((rule) => rule.name === chosen);
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-6">
        {note !== undefined && <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote">{note}</p>}
        <div className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-2.5">
          {(Object.keys(EFFECT_WORDS) as Effect[]).map((effect) => (
            <div key={effect} className="flex flex-col gap-1 rounded-xl border border-panel-edge bg-card px-3.5 py-3">
              <StatusWord tone={effectTone(effect)}>{EFFECT_WORDS[effect].title}</StatusWord>
              <span className="text-footnote text-muted">{EFFECT_WORDS[effect].says}</span>
            </div>
          ))}
        </div>

        <LetGo parts={parts} said={said} />

        <Section title="Always ask me before">
          <Panel>
            {ALWAYS_ASK.map((each) => {
              const on = switchOn(view.rules, each.draft.action, 'branches' in each.draft ? each.draft.branches : undefined);
              return (
                <Row
                  key={each.id}
                  title={each.title}
                  caption={on ? 'A rule asks about this now' : 'Agents go ahead unless another rule says otherwise'}
                  trailing={
                    <Switch
                      on={on}
                      label={each.title}
                      disabled={on || studio.busy !== undefined}
                      onChange={() => void studio.propose(each.draft as unknown as RuleDraftInput).then(said)}
                    />
                  }
                />
              );
            })}
          </Panel>
        </Section>

        <Section
          title="Rules in force"
          trailing={
            <div className="flex flex-wrap items-center gap-2">
              <PackButtons parts={parts} said={said} />
              <KitButton kind="primary" icon={Plus} onClick={() => setBuilding({ effect: 'ask' })}>
                New rule
              </KitButton>
            </div>
          }
        >
          <div role="tablist" className="flex flex-wrap gap-1.5">
            {(['all', 'allow', 'ask', 'deny'] as const).map((each) => (
              <button
                key={each}
                type="button"
                role="tab"
                aria-selected={filter === each}
                onClick={() => setFilter(each)}
                className={`mx-focus cursor-pointer rounded-full border px-3 py-1 text-footnote ${filter === each ? 'border-primary bg-hover font-medium text-foreground' : 'border-panel-edge text-muted hover:bg-hover'}`}
              >
                {each === 'all' ? `All ${view.rules.length}` : `${EFFECT_WORDS[each].title} ${counts[each]}`}
              </button>
            ))}
          </div>
          {view.problems.length > 0 && (
            <div role="alert" className="flex flex-col gap-1 rounded-xl border border-panel-edge bg-card px-4 py-3">
              {view.problems.map((problem) => (
                <StatusWord key={problem.file} tone="bad">{`${problem.file}: ${problem.issues.join(' ')}`}</StatusWord>
              ))}
            </div>
          )}
          {shown.length === 0 ? (
            <EmptyState icon={ShieldCheck} title="No rules of this kind" body="Build one with New rule, or turn on a switch above." />
          ) : (
            <Panel>
              {shown.map((rule) => (
                <Row
                  key={rule.name}
                  chosen={rule.name === chosen}
                  title={rule.sentence}
                  caption={sourceWords(rule)}
                  trailing={<StatusWord tone={effectTone(rule.effect)}>{EFFECT_WORDS[rule.effect as Effect].title}</StatusWord>}
                  onClick={() => choose(rule.name)}
                />
              ))}
            </Panel>
          )}
        </Section>

        {parts.support.supports('index-list') === true && <IndexPacks parts={parts} said={setNote} />}

        <TryAction parts={parts} />
      </div>
      {picked !== undefined && (
        <Inspector title={picked.name} width={width} close={() => choose(undefined)}>
          <RuleDetail rule={picked} remove={() => void studio.remove(picked.name).then((outcome) => (said(outcome), outcome.kind === 'done' && choose(undefined)))} busy={studio.busy === picked.name} />
        </Inspector>
      )}
      {building !== undefined && <RuleBuilder parts={parts} start={building} close={() => setBuilding(undefined)} said={said} />}
    </div>
  );
}

function noteOf(outcome: StudioOutcome, keyTitle: string): string {
  if (outcome.kind === 'proposed') return `Waiting for you on the island: confirm it with ${keyTitle} and it goes in force.`;
  if (outcome.kind === 'failed') return outcome.why;
  return outcome.note;
}

function RuleDetail({ rule, remove, busy }: { rule: PolicyRuleView; remove: () => void; busy: boolean }) {
  const fields: [string, readonly string[] | undefined][] = [
    ['Actions', rule.match.actions],
    ['Targets', rule.match.targets],
    ['Agents', rule.match.agents],
    ['Folders', rule.match.workingDirectories],
    ['Branches', rule.match.branches],
    ['Kinds', rule.match.classes],
  ];
  return (
    <div className="flex flex-col gap-5">
      <p className="text-headline font-semibold text-foreground">{rule.sentence}</p>
      <StatusWord tone={effectTone(rule.effect)}>{EFFECT_WORDS[rule.effect as Effect].says}</StatusWord>
      {rule.reason !== undefined && <p className="text-body text-foreground">{rule.reason}</p>}
      <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-footnote">
        {fields
          .filter((field): field is [string, readonly string[]] => field[1] !== undefined && field[1].length > 0)
          .map(([name, values]) => (
            <div key={name} className="contents">
              <dt className="text-muted">{name}</dt>
              <dd className="font-mono break-all text-foreground">{values.join(', ')}</dd>
            </div>
          ))}
        <dt className="text-muted">From</dt>
        <dd className="text-foreground">{sourceWords(rule)}</dd>
        {rule.until !== undefined && (
          <>
            <dt className="text-muted">Until</dt>
            <dd className="text-foreground">{new Date(rule.until).toLocaleString()}</dd>
          </>
        )}
      </dl>
      {rule.editable ? (
        <div className="border-t border-panel-edge pt-4">
          <KitButton disabled={busy} onClick={remove}>
            {rule.effect === 'allow' ? 'Remove' : 'Propose removing it'}
          </KitButton>
          {rule.effect !== 'allow' && <p className="pt-2 text-footnote text-muted">Removing a rule that asks or refuses lets agents do more, so it waits for your signature.</p>}
        </div>
      ) : (
        <p className="text-footnote text-muted">This rule is not one set on this computer, so it is changed where it came from.</p>
      )}
    </div>
  );
}

/** When, then, and scope, read back as a sentence before it is proposed; the TOML is there for those who want it. */
function RuleBuilder({ parts, start, close, said }: { parts: SettingsParts; start: Partial<RuleDraftInput>; close: () => void; said: (outcome: StudioOutcome) => void }) {
  const { studio, hub } = parts;
  const [effect, setEffect] = useState<Effect>((start.effect as Effect | undefined) ?? 'ask');
  const [action, setAction] = useState(start.action ?? '');
  const [agent, setAgent] = useState('');
  const [target, setTarget] = useState('');
  const [branch, setBranch] = useState('');
  const [folder, setFolder] = useState('');
  const [reason, setReason] = useState('');
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => first.current?.focus(), []);
  const agents = hub.hub?.agents.map((each) => each.agent) ?? [];
  const known = [...new Set((studio.rules?.rules ?? []).flatMap((rule) => rule.match.actions))].sort();
  const list = (value: string) => (value.trim() === '' ? undefined : [value.trim()]);
  const draft: RuleDraftInput = {
    effect,
    action: action.trim(),
    reason: reason.trim() === '' ? `you chose to ${effect} this` : reason.trim(),
    ...(list(agent) === undefined ? {} : { agents: list(agent) }),
    ...(list(target) === undefined ? {} : { targets: list(target) }),
    ...(list(branch) === undefined ? {} : { branches: list(branch) }),
    ...(list(folder) === undefined ? {} : { workingDirectories: list(folder) }),
  } as RuleDraftInput;
  const field = 'h-9 w-full rounded-lg border border-field-edge bg-field px-3 text-body text-foreground outline-none placeholder:text-faint focus:border-primary';
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 px-4 py-[8vh]" role="presentation" onMouseDown={close}>
      <div role="dialog" aria-modal="true" aria-label="New rule" className="flex w-full max-w-[560px] flex-col rounded-2xl border border-panel-edge bg-background shadow-2xl" onMouseDown={(event) => event.stopPropagation()}>
        <header className="border-b border-panel-edge px-5 py-3.5 text-headline font-semibold">New rule</header>
        <div className="flex flex-col gap-4 px-5 py-5">
          <fieldset className="flex flex-col gap-2">
            <legend className="pb-1.5 text-footnote font-semibold text-muted">When</legend>
            <select className={field} value={agent} onChange={(event) => setAgent(event.target.value)} aria-label="Which agent">
              <option value="">Any agent</option>
              {agents.map((each) => (
                <option key={each} value={each}>
                  {agentLabel(each)}
                </option>
              ))}
            </select>
            <input ref={first} list="known-actions" className={`${field} font-mono`} placeholder="git.push" value={action} onChange={(event) => setAction(event.target.value)} aria-label="The action" />
            <datalist id="known-actions">{known.map((each) => <option key={each} value={each} />)}</datalist>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <input className={field} placeholder="On, optional" value={target} onChange={(event) => setTarget(event.target.value)} aria-label="Target" />
              <input className={field} placeholder="Branch, optional" value={branch} onChange={(event) => setBranch(event.target.value)} aria-label="Branch" />
              <input className={field} placeholder="Folder, optional" value={folder} onChange={(event) => setFolder(event.target.value)} aria-label="Folder" />
            </div>
          </fieldset>
          <fieldset className="flex flex-col gap-2">
            <legend className="pb-1.5 text-footnote font-semibold text-muted">Then</legend>
            <div role="radiogroup" className="grid grid-cols-3 gap-2">
              {(Object.keys(EFFECT_WORDS) as Effect[]).map((each) => (
                <button key={each} type="button" role="radio" aria-checked={effect === each} onClick={() => setEffect(each)} className={`mx-focus cursor-pointer rounded-xl border px-3 py-2.5 text-left ${effect === each ? 'border-primary bg-hover' : 'border-panel-edge hover:bg-hover'}`}>
                  <StatusWord tone={effectTone(each)}>{EFFECT_WORDS[each].title}</StatusWord>
                  <span className="block pt-1 text-micro text-muted">{EFFECT_WORDS[each].says}</span>
                </button>
              ))}
            </div>
            <input className={field} placeholder="Why, in your words" value={reason} onChange={(event) => setReason(event.target.value)} aria-label="Why" />
          </fieldset>
          <p className="rounded-lg bg-card px-3.5 py-3 text-body text-foreground">{draftSentence(draft, agentLabel)}</p>
          <details>
            <summary className="mx-focus cursor-pointer text-footnote text-muted">Show the rule as written</summary>
            <pre className="mt-2 max-h-48 overflow-auto rounded-lg bg-card p-3 font-mono text-micro">{JSON.stringify(draft, null, 2)}</pre>
          </details>
        </div>
        <footer className="flex items-center gap-2 border-t border-panel-edge px-5 py-3.5">
          <span className="flex-1 text-footnote text-muted">{`It goes in force when you sign it with ${parts.words.keyTitle}.`}</span>
          <KitButton onClick={close}>Cancel</KitButton>
          <KitButton kind="primary" disabled={action.trim() === '' || studio.busy !== undefined} onClick={() => void studio.propose(draft).then((outcome) => (said(outcome), outcome.kind !== 'failed' && close()))}>
            Propose
          </KitButton>
        </footer>
      </div>
    </div>
  );
}

/** What could run without asking, how close the rest is, and what the autopilot already answers. */
function LetGo({ parts, said }: { parts: SettingsParts; said: (outcome: StudioOutcome) => void }) {
  const { studio, home, words } = parts;
  const progress = studio.progress;
  if (progress === undefined) return null;
  return (
    <Section title="Let go">
      <div className="flex flex-col gap-1 rounded-xl border border-panel-edge bg-card px-4 py-3.5">
        <span className="text-body font-semibold text-foreground">{progress.ladder.says}</span>
        {progress.ladder.needs !== undefined && <span className="text-footnote text-muted">{progress.ladder.needs}</span>}
        <span className="text-footnote text-muted">{`${weekLine(progress)} ${autopilotLine(progress.thisWeek.answeredByAutopilot)}`}</span>
        <ol className="flex flex-wrap gap-1.5 pt-2" aria-label="Autonomy ladder">
          {progress.ladder.rungs.map((rung) => (
            <li key={rung} className={`rounded-full border px-2.5 py-0.5 text-micro ${rung === progress.ladder.level ? 'border-primary font-semibold text-foreground' : 'border-panel-edge text-muted'}`}>
              {rung}
            </li>
          ))}
        </ol>
      </div>
      {(progress.ready.length > 0 || progress.almost.length > 0 || progress.grants.length > 0) && (
        <Panel>
          {progress.ready.map((ready) => (
            <Row
              key={ready.action}
              title={`${ready.action}, said yes ${ready.approvals} times`}
              caption={ready.because}
              trailing={
                <KitButton kind="primary" disabled={home.handingOver} onClick={() => void home.handOver(ready, words.keyTitle)}>
                  Let it run on its own
                </KitButton>
              }
            />
          ))}
          {progress.almost.map((almost) => (
            <Row key={almost.action} title={almostLine(almost)} caption="It needs the same yes a few more times, with no refusal." />
          ))}
          {progress.grants.map((grant) => (
            <Row
              key={grant.id}
              title={grant.says}
              caption={`The autopilot answers this until ${new Date(grant.until).toLocaleDateString()}`}
              trailing={
                <KitButton disabled={studio.busy === grant.id} onClick={() => void studio.revoke(grant.id).then(said)}>
                  Take it back
                </KitButton>
              }
            />
          ))}
        </Panel>
      )}
    </Section>
  );
}

function TryAction({ parts }: { parts: SettingsParts }) {
  const { studio } = parts;
  const [action, setAction] = useState('');
  const [target, setTarget] = useState('');
  const [verdict, setVerdict] = useState<RuleVerdictView | string | undefined>(undefined);
  const field = 'h-9 min-w-[140px] flex-1 rounded-lg border border-field-edge bg-field px-3 text-body text-foreground outline-none placeholder:text-faint focus:border-primary';
  return (
    <Section title="Try an action">
      <p className="text-footnote text-muted">See what your rules would do, without anything running or being recorded.</p>
      <div className="flex flex-wrap gap-2">
        <input className={`${field} font-mono`} placeholder="git.push" value={action} onChange={(event) => setAction(event.target.value)} aria-label="Action to try" />
        <input className={field} placeholder="On, optional" value={target} onChange={(event) => setTarget(event.target.value)} aria-label="Target to try" />
        <KitButton icon={FlaskConical} disabled={action.trim() === ''} onClick={() => void studio.test({ action: action.trim(), ...(target.trim() === '' ? {} : { target: target.trim() }) }).then(setVerdict)}>
          Try it
        </KitButton>
      </div>
      {typeof verdict === 'string' && <StatusWord tone="bad">{verdict}</StatusWord>}
      {verdict !== undefined && typeof verdict !== 'string' && (
        <div className="flex flex-col gap-1 rounded-xl border border-panel-edge bg-card px-4 py-3">
          <StatusWord tone={effectTone(verdict.effect)}>{EFFECT_WORDS[verdict.effect as Effect].says}</StatusWord>
          <span className="text-body text-foreground">{verdict.reason}</span>
          {verdict.rule !== undefined && <span className="text-footnote text-muted">{`Rule: ${verdict.rule}`}</span>}
          {verdict.instead !== undefined && <span className="text-footnote text-muted">{`Instead: ${verdict.instead}`}</span>}
        </div>
      )}
    </Section>
  );
}

/** Rule packs from the community index, beside import and export; installing proposes each rule, signed on its own. */
function IndexPacks({ parts, said }: { parts: SettingsParts; said: (note: string) => void }) {
  const { index, words } = parts;
  useObserved(index);
  useEffect(() => {
    void index.readPacks();
  }, []);
  const packs = index.packs;
  if (packs === undefined || packs.length === 0) return null;
  return (
    <Section title="Rule packs from the community index">
      <Panel>
        {packs.map((pack) => (
          <Row
            key={pack.id}
            title={pack.name}
            caption={`${pack.description} · ${publisherLine(pack.publisher)} · ${latestLine(pack)}`}
            trailing={
              canInstall(pack) ? (
                <KitButton icon={Download} disabled={index.busy === pack.name} onClick={() => void index.install(pack.name, pack.latest?.version).then((outcome) => said(outcome.kind === 'failed' ? outcome.why : outcome.note))}>
                  Install
                </KitButton>
              ) : (
                <StatusWord tone="bad">Marked unsafe</StatusWord>
              )
            }
          />
        ))}
      </Panel>
      <p className="text-footnote text-muted">{installWaitsLine('rule_pack', words.keyTitle)}</p>
    </Section>
  );
}

/** A pack is a TOML file: exported to the clipboard, and imported one rule proposal at a time. */
function PackButtons({ parts, said }: { parts: SettingsParts; said: (outcome: StudioOutcome) => void }) {
  const { studio, host } = parts;
  const picker = useRef<HTMLInputElement>(null);
  return (
    <>
      <KitButton
        icon={Download}
        onClick={() =>
          void studio.exportToml().then(async (toml) => {
            if (toml === undefined || exportedCount(toml) === 0) return said({ kind: 'done', note: 'No rule set on this computer to export yet.' });
            await host.copy(toml);
            said({ kind: 'done', note: `Copied ${exportedCount(toml)} rules as TOML, ready to save or share.` });
          })
        }
      >
        Export
      </KitButton>
      <KitButton icon={Upload} onClick={() => picker.current?.click()}>
        Import
      </KitButton>
      <input
        ref={picker}
        type="file"
        accept=".toml,text/plain"
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0];
          if (file !== undefined) void file.text().then((toml) => studio.importPack(toml)).then(said);
          event.target.value = '';
        }}
      />
    </>
  );
}
