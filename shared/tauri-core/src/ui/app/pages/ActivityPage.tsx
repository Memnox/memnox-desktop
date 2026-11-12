import type { ActivityFilter, DecisionView } from '@memnox/core/wire';
import { ArrowUp, Copy, History } from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import type { Route, WidthClass } from '../../../core/domain/destinations';
import { agentNameOf, missedRowsLine, newRowsLine, type ShownActivity } from '../../../core/domain/live-activity';
import { ago } from '../../../core/domain/session-text';
import { activityLine, answeredWords, EFFECT_WORDS, effectTone, isEffect, sourceWords } from '../../../core/domain/studio-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { useInspectorHost } from '../inspector-host';
import { Inspector } from '../widgets';
import { ActivityLines } from '../../../core/domain/activity-words';
import { BrandLogo, Button, Chip, ChipGroup, EmptyState, Panel, ReadFailed, Row, SearchInput, Section, Select, StatusWord } from '../../kit';
import { PAGE_METRICS } from '../page-metrics';

/** The Mac's toolbar: the search and the kind, each capped. */
const SEARCH_WIDTH = PAGE_METRICS.activitySearch;
const KIND_WIDTH = PAGE_METRICS.activityKind;

/** An agent's logo at the head of its row. */
const ROW_LOGO = 24;

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

  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-6">
        {/* The pill floats over the top of the list, as the Mac's overlay does, rather than pushing the toolbar down. */}
        <div className="sticky top-0 z-10 -mb-6 flex h-0 justify-center overflow-visible">
          {activity.waiting > 0 && (
            <div className="pt-2">
              <Button
                kind="primary"
                icon={ArrowUp}
                onClick={() => {
                  top.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
                  activity.showWaiting();
                }}
              >
                {newRowsLine(activity.waiting)}
              </Button>
            </div>
          )}
        </div>
        <div ref={top} aria-hidden className="h-0" />
        <div className="flex flex-wrap items-center gap-2">
          <div className="w-full flex-1" style={{ maxWidth: SEARCH_WIDTH }}>
            <SearchInput value={text} placeholder={ActivityLines.search} onChange={setText} />
          </div>
          <ChipGroup label={ActivityLines.decided} role="group">
            <Chip role="toggle" on={effect === ''} pick={() => setEffect('')}>
              {ActivityLines.any}
            </Chip>
            {(['allow', 'ask', 'deny'] as const).map((each) => (
              <Chip key={each} role="toggle" on={effect === each} pick={() => setEffect(each)}>
                {EFFECT_WORDS[each].title}
              </Chip>
            ))}
          </ChipGroup>
          <div style={{ maxWidth: KIND_WIDTH }}>
            <Select look="field" wide value={kind} options={ActivityLines.kinds} onChange={setKind} label={ActivityLines.kind} />
          </div>
          <span className="flex-1" />
          <Button
            icon={Copy}
            onClick={() =>
              void activity.exportBundle().then(async (bundle) => {
                if (bundle === undefined) return setNote(ActivityLines.noRecord);
                await host.copy(bundle);
                setNote(ActivityLines.copied);
              })
            }
          >
            {ActivityLines.copyRecord}
          </Button>
        </div>
        {note !== undefined && <p role="status" className="text-footnote text-muted">{note}</p>}
        {activity.missed > 0 && (
          <div className="flex flex-wrap items-center gap-2">
            <p role="status" className="text-footnote text-muted">{missedRowsLine(activity.missed)}</p>
            <Button onClick={() => void activity.show(filter)}>
              {ActivityLines.refresh}
            </Button>
          </div>
        )}
        {activity.unreadable && shown.length === 0 ? (
          <ReadFailed what={ActivityLines.readWhat} retry={() => void activity.show(filter)} />
        ) : shown.length === 0 && !activity.loading ? (
          <EmptyState icon={History} title={ActivityLines.emptyTitle} body={ActivityLines.emptyBody} />
        ) : (
          <Panel>
            {shown.map((row) => (
              <ActivityRowView key={row.id} row={row} name={agentNameOf(row, names)} chosen={activity.decision?.row.id === row.id} open={() => void activity.open(row.id)} />
            ))}
          </Panel>
        )}
        {activity.more && (
          <Button disabled={activity.loading} onClick={() => void activity.readOn()}>
            {activity.loading ? ActivityLines.reading : ActivityLines.older}
          </Button>
        )}
      </div>
      {activity.decision !== undefined && (
        <Inspector title={ActivityLines.why} width={width} close={() => activity.close()} item={activity.decision.row.id}>
          <DecisionDetail key={activity.decision.row.id} view={activity.decision} change={() => go({ destination: 'rules', tab: 'rules' })} />
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
      leading={<BrandLogo agent={row.agent} name={name} size={ROW_LOGO} />}
      title={<span className="font-code">{activityLine(row)}</span>}
      caption={[name, ago(row.at, Date.now()), row.rule, answered].filter((part) => part !== undefined).join(' · ')}
      trailing={
        <>
          {row.failed !== undefined && <StatusWord tone="bad">{ActivityLines.failedExit(row.failed)}</StatusWord>}
          <StatusWord tone={effectTone(row.effect)}>{isEffect(row.effect) ? EFFECT_WORDS[row.effect].verdict : row.effect}</StatusWord>
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
        <span className="font-code text-body break-all text-foreground">{activityLine(row)}</span>
        <StatusWord tone={effectTone(row.effect)}>{isEffect(row.effect) ? EFFECT_WORDS[row.effect].says : row.effect}</StatusWord>
        <span className="text-body text-foreground">{row.reason}</span>
        {view.alternative !== undefined && <span className="text-footnote text-muted">{ActivityLines.instead(view.alternative)}</span>}
      </div>
      {view.rule !== undefined && (
        <Section title={ActivityLines.theRule}>
          <p className="text-body text-foreground">{view.rule.name}</p>
          <p className="text-footnote text-muted">
            {[view.rule.source === undefined ? undefined : sourceWords({ source: view.rule.source, ...(view.rule.decidedBy === undefined ? {} : { decidedBy: view.rule.decidedBy }), ...(view.rule.file === undefined ? {} : { file: view.rule.file }) }), view.rule.newerSince === true ? ActivityLines.changedSince : undefined]
              .filter((part) => part !== undefined)
              .join(' ')}
          </p>
          <Button onClick={change}>{ActivityLines.changeRule}</Button>
        </Section>
      )}
      {view.chain !== '' && (
        <Section title={ActivityLines.actedFor}>
          <p className="text-footnote break-words text-muted">{view.chain}</p>
        </Section>
      )}
      {view.context.length > 0 && (
        <Section title={ActivityLines.known}>
          <Panel>
            {view.context.map((part) => (
              <Row key={part.domain} title={part.domain} caption={part.facts.join(' · ')} trailing={part.decided ? <StatusWord tone="attention">{ActivityLines.decidedIt}</StatusWord> : undefined} />
            ))}
          </Panel>
        </Section>
      )}
      {view.before.length > 0 && (
        <Section title={ActivityLines.ledUp}>
          <Panel>
            {view.before.map((step) => (
              <Row key={`${step.at}${step.operation}`} title={<span className="font-code">{activityLine(step)}</span>} caption={ago(step.at, Date.now())} trailing={<StatusWord tone={effectTone(step.effect)}>{isEffect(step.effect) ? EFFECT_WORDS[step.effect].verdict : step.effect}</StatusWord>} />
            ))}
          </Panel>
        </Section>
      )}
      <Section title={ActivityLines.happened}>
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-meta">
          <dt className="text-muted">{ActivityLines.ranAs}</dt>
          <dd className="text-foreground">{view.trace.mode}</dd>
          {view.trace.exitCode !== undefined && (
            <>
              <dt className="text-muted">{ActivityLines.exit}</dt>
              <dd className="text-foreground">{view.trace.exitCode}</dd>
            </>
          )}
          {view.trace.approvedBy !== undefined && (
            <>
              <dt className="text-muted">{ActivityLines.approvedBy}</dt>
              <dd className="text-foreground">{view.trace.approvedBy}</dd>
            </>
          )}
        </dl>
      </Section>
    </div>
  );
}
