import type { ActivityFilter, DecisionView } from '@memnox/core/wire';
import { ArrowUp, Copy, FileText, History, RotateCw } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { agentNameOf, missedRowsLine, newRowsLine, type ShownActivity } from '../../../core/domain/live-activity';
import { ago } from '../../../core/domain/session-text';
import { filePressLine } from '../../../core/domain/memory-lines';
import { activityLine, answeredWords, decisionFiles, EFFECT_WORDS, effectTone, isEffect, sourceWords } from '../../../core/domain/studio-lines';
import { BrandLogo } from '../../kit/logos';
import { openOrCopy, type SettingsHost } from '../../settings/host';
import { KitButton, SearchField } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { useInspectorHost } from '../inspector-host';
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
  useEffect(() => parts.host.onLiveActivity?.((rows, missed) => activity.heard(rows, missed)), []);
  // A popped out Why window opens on the decision its link names.
  const linked = useInspectorHost().item;
  useEffect(() => {
    if (linked !== undefined) void activity.open(linked);
  }, []);
  const top = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const mark = top.current;
    if (mark === null) return;
    const watch = new IntersectionObserver((seen) => activity.atTop(seen.some((each) => each.isIntersecting)));
    watch.observe(mark);
    return () => watch.disconnect();
  }, []);
  const names = useMemo(() => new Map(activity.rows.map((row) => [row.agent, row.agentName])), [activity.rows]);
  const shown: readonly ShownActivity[] = [...activity.live, ...activity.rows];

  const chip = (on: boolean) => `mx-focus cursor-pointer inline-flex h-8 items-center rounded-lg border px-3 text-body-sm ${on ? 'border-primary/45 bg-primary/[0.07] font-medium text-foreground' : 'border-panel-edge bg-card text-muted hover:bg-hover hover:text-foreground'}`;
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-4">
        <div ref={top} aria-hidden className="h-px" />
        {activity.waiting > 0 && (
          <div className="sticky top-2 z-10 flex justify-center">
            <KitButton
              kind="primary"
              icon={ArrowUp}
              onClick={() => {
                top.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
                activity.showWaiting();
              }}
            >
              {newRowsLine(activity.waiting)}
            </KitButton>
          </div>
        )}
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
          <select value={kind} onChange={(event) => setKind(event.target.value)} aria-label="Kind" className="h-8 mx-field rounded-lg border border-field-edge bg-field px-2.5 text-footnote text-foreground">
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
        {activity.missed > 0 && (
          <div className="flex flex-wrap items-center gap-2">
            <p role="status" className="text-footnote text-muted">{missedRowsLine(activity.missed)}</p>
            <KitButton icon={RotateCw} onClick={() => void activity.show(filter)}>
              Refresh
            </KitButton>
          </div>
        )}
        {activity.unreadable && shown.length === 0 ? (
          <ReadFailed what="the activity" retry={() => void activity.show(filter)} />
        ) : shown.length === 0 && !activity.loading ? (
          <EmptyState icon={History} title="Nothing here yet" body="What your agents do on this computer appears here as it happens, with what your rules decided." />
        ) : (
          <Panel>
            {shown.map((row) => (
              <ActivityRowView key={row.id} row={row} name={agentNameOf(row, names)} chosen={activity.decision?.row.id === row.id} open={() => void activity.open(row.id)} />
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
        <Inspector title="Why" width={width} close={() => activity.close()} item={activity.decision.row.id}>
          <DecisionDetail key={activity.decision.row.id} view={activity.decision} host={host} change={() => go({ destination: 'governance', tab: 'policies' })} />
        </Inspector>
      )}
    </div>
  );
}

/** A row paged in whole, or one that arrived live with names only, which says less until the list is read again. */
function ActivityRowView({ row, name, chosen, open }: { row: ShownActivity; name: string; chosen: boolean; open: () => void }) {
  const answered = answeredWords(row);
  return (
    <Row
      chosen={chosen}
      leading={<BrandLogo agent={row.agent} name={name} size={24} />}
      title={<span className="font-mono">{activityLine(row)}</span>}
      caption={[name, ago(row.at, Date.now()), row.rule, answered].filter((part) => part !== undefined).join(' · ')}
      trailing={
        <>
          {row.failed !== undefined && <StatusWord tone="bad">{`Failed, exit ${row.failed}`}</StatusWord>}
          <StatusWord tone={effectTone(row.effect)}>{isEffect(row.effect) ? EFFECT_WORDS[row.effect].verdict : row.effect}</StatusWord>
        </>
      }
      onClick={open}
    />
  );
}

function DecisionDetail({ view, host, change }: { view: DecisionView; host: SettingsHost; change: () => void }) {
  const { row } = view;
  const files = decisionFiles(view);
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
              <Row key={`${step.at}${step.operation}`} title={<span className="font-mono">{activityLine(step)}</span>} caption={ago(step.at, Date.now())} trailing={<StatusWord tone={effectTone(step.effect)}>{isEffect(step.effect) ? EFFECT_WORDS[step.effect].verdict : step.effect}</StatusWord>} />
            ))}
          </Panel>
        </Section>
      )}
      {files.length > 0 && <LocalFiles host={host} files={files} />}
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

/** The files a decision names, each opened in its own app, or its whole path copied when it is gone or is not a document. */
function LocalFiles({ host, files }: { host: SettingsHost; files: readonly { title: string; path: string }[] }) {
  const [pressed, setPressed] = useState<{ path: string; opened: boolean } | undefined>(undefined);
  return (
    <div className="flex flex-col gap-1.5">
      {files.map((file) => (
        <div key={file.title} className="flex min-w-0 flex-wrap items-center gap-2">
          <KitButton icon={FileText} onClick={() => void openOrCopy(host, file.path).then((opened) => setPressed({ path: file.path, opened }))}>
            {file.title}
          </KitButton>
          <span className="min-w-0 truncate font-mono text-footnote text-muted" title={file.path}>
            {file.path}
          </span>
          {pressed !== undefined && pressed.path === file.path && <span className="text-footnote text-muted">{filePressLine(pressed.opened)}</span>}
        </div>
      ))}
    </div>
  );
}
