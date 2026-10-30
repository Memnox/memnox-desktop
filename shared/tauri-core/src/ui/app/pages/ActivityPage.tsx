import type { ActivityFilter, ActivityRow, DecisionView } from '@memnox/core/wire';
import { Copy, History } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { ago } from '../../../core/domain/session-text';
import { activityLine, answeredWords, EFFECT_WORDS, effectTone, isEffect, sourceWords } from '../../../core/domain/studio-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton, SearchField } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { EmptyState, Inspector, Panel, ReadFailed, Row, Section, StatusWord } from '../widgets';

const KINDS = [
  { id: '', title: 'Everything' },
  { id: 'command', title: 'Commands' },
  { id: 'file', title: 'Files' },
  { id: 'mcp', title: 'MCP tools' },
  { id: 'tool', title: 'Other tools' },
] as const;

/**
 * What the agents did, newest first: what was decided beside what happened, and why any one of it came
 * out as it did. Names only, never arguments or file contents.
 */
export function ActivityPage({ parts, width, go }: { parts: SettingsParts; width: WidthClass; go: (route: Route) => void }) {
  const { activity, host } = parts;
  useObserved(activity);
  const [effect, setEffect] = useState<string>('');
  const [kind, setKind] = useState<string>('');
  const [text, setText] = useState('');
  const [note, setNote] = useState<string | undefined>(undefined);
  const filter: ActivityFilter = {
    ...(effect === '' ? {} : { effect: effect as ActivityFilter['effect'] }),
    ...(kind === '' ? {} : { kind: kind as ActivityFilter['kind'] }),
    ...(text.trim() === '' ? {} : { text: text.trim() }),
  };
  const key = JSON.stringify(filter);
  useEffect(() => {
    void activity.show(filter);
  }, [key]);
  useEffect(() => parts.host.onHomeStale?.(() => void activity.show(activity.filter)), []);

  const chip = (on: boolean) => `mx-focus cursor-pointer rounded-full border px-3 py-1 text-footnote ${on ? 'border-primary bg-hover font-medium text-foreground' : 'border-panel-edge text-muted hover:bg-hover'}`;
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          <div className="w-full max-w-[280px] min-w-[160px] flex-1">
            <SearchField value={text} placeholder="Search actions and targets" onChange={setText} />
          </div>
          <div role="group" aria-label="Decided" className="flex flex-wrap gap-1.5">
            <button type="button" className={chip(effect === '')} aria-pressed={effect === ''} onClick={() => setEffect('')}>
              Any
            </button>
            {(['allow', 'ask', 'deny'] as const).map((each) => (
              <button key={each} type="button" className={chip(effect === each)} aria-pressed={effect === each} onClick={() => setEffect(each)}>
                {EFFECT_WORDS[each].title}
              </button>
            ))}
          </div>
          <select value={kind} onChange={(event) => setKind(event.target.value)} aria-label="Kind" className="h-8 rounded-lg border border-field-edge bg-field px-2.5 text-footnote text-foreground">
            {KINDS.map((each) => (
              <option key={each.id} value={each.id}>
                {each.title}
              </option>
            ))}
          </select>
          <span className="flex-1" />
          <KitButton
            icon={Copy}
            onClick={() =>
              void activity.exportBundle().then(async (bundle) => {
                if (bundle === undefined) return setNote('The runtime did not hand over a record.');
                await host.copy(bundle);
                setNote('Copied the signed record of what this view shows. memnox verify checks it.');
              })
            }
          >
            Copy signed record
          </KitButton>
        </div>
        {note !== undefined && <p role="status" className="text-footnote text-muted">{note}</p>}
        {activity.unreadable && activity.rows.length === 0 ? (
          <ReadFailed what="the activity" retry={() => void activity.show(filter)} />
        ) : activity.rows.length === 0 && !activity.loading ? (
          <EmptyState icon={History} title="Nothing here yet" body="What your agents do on this computer appears here as it happens, with what your rules decided." />
        ) : (
          <Panel>
            {activity.rows.map((row) => (
              <ActivityRowView key={row.id} row={row} chosen={activity.decision?.row.id === row.id} open={() => void activity.open(row.id)} />
            ))}
          </Panel>
        )}
        {activity.more && (
          <KitButton disabled={activity.loading} onClick={() => void activity.readOn()}>
            {activity.loading ? 'Reading' : 'Show older'}
          </KitButton>
        )}
      </div>
      {activity.decision !== undefined && (
        <Inspector title="Why" width={width} close={() => activity.close()}>
          <DecisionDetail view={activity.decision} change={() => go({ destination: 'governance', tab: 'policies' })} />
        </Inspector>
      )}
    </div>
  );
}

function ActivityRowView({ row, chosen, open }: { row: ActivityRow; chosen: boolean; open: () => void }) {
  const answered = answeredWords(row);
  return (
    <Row
      chosen={chosen}
      leading={<BrandLogo agent={row.agent} name={row.agentName} size={24} />}
      title={<span className="font-mono">{activityLine(row)}</span>}
      caption={[row.agentName, ago(row.at, Date.now()), row.rule, answered].filter((part) => part !== undefined).join(' · ')}
      trailing={
        <>
          {row.failed !== undefined && <StatusWord tone="bad">{`Failed, exit ${row.failed}`}</StatusWord>}
          <StatusWord tone={effectTone(row.effect)}>{isEffect(row.effect) ? EFFECT_WORDS[row.effect].title : row.effect}</StatusWord>
        </>
      }
      onClick={open}
    />
  );
}

function DecisionDetail({ view, change }: { view: DecisionView; change: () => void }) {
  const { row } = view;
  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-1.5">
        <span className="font-mono text-body break-all text-foreground">{activityLine(row)}</span>
        <StatusWord tone={effectTone(row.effect)}>{isEffect(row.effect) ? EFFECT_WORDS[row.effect].says : row.effect}</StatusWord>
        <span className="text-body text-foreground">{row.reason}</span>
        {view.alternative !== undefined && <span className="text-footnote text-muted">{`Instead: ${view.alternative}`}</span>}
      </div>
      {view.rule !== undefined && (
        <Section title="The rule">
          <p className="text-body text-foreground">{view.rule.name}</p>
          <p className="text-footnote text-muted">
            {[view.rule.source === undefined ? undefined : sourceWords({ source: view.rule.source, ...(view.rule.decidedBy === undefined ? {} : { decidedBy: view.rule.decidedBy }), ...(view.rule.file === undefined ? {} : { file: view.rule.file }) }), view.rule.newerSince === true ? 'It has changed since.' : undefined]
              .filter((part) => part !== undefined)
              .join(' ')}
          </p>
          <KitButton onClick={change}>Change this rule</KitButton>
        </Section>
      )}
      {view.chain !== '' && (
        <Section title="Who it acted for">
          <p className="text-footnote break-words text-foreground">{view.chain}</p>
        </Section>
      )}
      {view.context.length > 0 && (
        <Section title="What was known">
          <Panel>
            {view.context.map((part) => (
              <Row key={part.domain} title={part.domain} caption={part.facts.join(' · ')} trailing={part.decided ? <StatusWord tone="attention">Decided it</StatusWord> : undefined} />
            ))}
          </Panel>
        </Section>
      )}
      {view.before.length > 0 && (
        <Section title="What led up to it">
          <Panel>
            {view.before.map((step) => (
              <Row key={`${step.at}${step.operation}`} title={<span className="font-mono">{activityLine(step)}</span>} caption={ago(step.at, Date.now())} trailing={<StatusWord tone={effectTone(step.effect)}>{isEffect(step.effect) ? EFFECT_WORDS[step.effect].title : step.effect}</StatusWord>} />
            ))}
          </Panel>
        </Section>
      )}
      <Section title="What happened">
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-footnote">
          <dt className="text-muted">Ran as</dt>
          <dd className="text-foreground">{view.trace.mode}</dd>
          {view.trace.exitCode !== undefined && (
            <>
              <dt className="text-muted">Exit</dt>
              <dd className="text-foreground">{view.trace.exitCode}</dd>
            </>
          )}
          {view.trace.approvedBy !== undefined && (
            <>
              <dt className="text-muted">Approved by</dt>
              <dd className="text-foreground">{view.trace.approvedBy}</dd>
            </>
          )}
        </dl>
      </Section>
    </div>
  );
}
