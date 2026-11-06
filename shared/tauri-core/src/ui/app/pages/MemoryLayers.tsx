import { Layers } from 'lucide-react';
import { useEffect, useState } from 'react';
import {
  COST_FOOTNOTE,
  KEEP_TITLE,
  LAYERS_EMPTY,
  PLAN_CONFIRM,
  keepList,
  LayersPageLines,
  layerCards,
  planDiff,
  planSummary,
  sessionCostLines,
  valueLines,
  type LayerCard,
  type MemoryLayersPlan,
  type PlanDiffMark,
} from '../../../core/domain/memory-layers-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Button, Card, ConfirmDialog, Dialog, EmptyState, Note, ReadFailed, Section, Select, Textarea } from '../../kit';

/** The keep list shows four lines before it scrolls, enough for the usual few. */
const KEEP_ROWS = 4;

/**
 * Memory as three layers any agent reads, numbered as the long term stack, ported from the Mac's Layers view: 1
 * MEMORY.md for every chat, 2 the router, 3 SKILL.md for live data. Below them the short term card with the cold
 * cache numbers, then the keep on compact list. Preview asks the runtime for the map, and only a confirm writes it,
 * inside Memnox's fenced blocks, with the plan's digest so a file changed since is refused.
 */
export function MemoryLayersView({ parts, project: picked }: { parts: SettingsParts; /** The repository the page's project filter picked, opened first. */ project?: string }) {
  const { memory } = parts;
  useObserved(memory);
  const [chosen, setChosen] = useState<string | undefined>(picked);
  useEffect(() => setChosen(picked), [picked]);
  const [keep, setKeep] = useState<string | undefined>(undefined);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [reviewing, setReviewing] = useState(false);
  useEffect(() => {
    void memory.refreshLayers();
  }, []);

  const view = memory.layers;
  if (view === undefined) {
    if (memory.layersUnreadable) return <ReadFailed what={LayersPageLines.theLayers} retry={() => void memory.refreshLayers()} />;
    return <p className="text-body-sm text-muted">{LayersPageLines.reading}</p>;
  }
  const project = view.projects.find((each) => each.path === chosen) ?? view.projects[0];
  const value = valueLines(view.value);
  const typed = keep ?? project?.keep.join('\n') ?? '';
  const busy = memory.busy !== undefined;

  const preview = () => {
    if (project === undefined) return;
    void memory.previewLayers(project.path, keepList(typed)).then((why) => {
      setNote(why);
      setReviewing(why === undefined);
    });
  };
  const close = () => {
    setReviewing(false);
    memory.dismissPlan();
  };

  return (
    <div className="flex flex-col gap-7">
      {note !== undefined && <Note>{note}</Note>}
      {value.length > 0 && (
        <div className="flex flex-wrap gap-8">
          {value.map((line) => (
            <div key={line.title} className="flex flex-col gap-0.5">
              <span className="text-meta text-muted">{line.title}</span>
              <span className="text-lg font-semibold tabular-nums text-foreground">{line.figure}</span>
              <span className="text-label text-faint">{line.detail}</span>
            </div>
          ))}
        </div>
      )}
      {project === undefined ? (
        <EmptyState icon={Layers} title={LAYERS_EMPTY.title} body={LAYERS_EMPTY.detail} />
      ) : (
        <>
          {view.projects.length > 1 && (
            <div className="w-full max-w-[320px]">
              <Select
                label={LayersPageLines.project}
                value={project.path}
                options={view.projects.map((each) => ({ value: each.path, label: each.name }))}
                onChange={(path) => {
                  setChosen(path);
                  setKeep(undefined);
                }}
              />
            </div>
          )}
          <Section
            title={LayersPageLines.longTerm}
            trailing={
              <Button kind="primary" disabled={busy} onClick={preview}>
                {LayersPageLines.previewMap}
              </Button>
            }
          >
            <div className="flex flex-col gap-2">
              {layerCards(project).map((card) => (
                <LayerCardView key={card.number} card={card} />
              ))}
            </div>
          </Section>
          <Section title={LayersPageLines.shortTerm}>
            <Card className="flex flex-col gap-3">
              {memory.sessionCost !== undefined && (
                <div className="flex flex-col gap-1.5">
                  {sessionCostLines(memory.sessionCost).map((line) => (
                    <p key={line} className="text-body-sm text-foreground">
                      {line}
                    </p>
                  ))}
                  <p className="text-meta text-faint">{COST_FOOTNOTE}</p>
                </div>
              )}
              <label className="flex flex-col gap-1.5">
                <span className="text-meta font-medium text-muted">{KEEP_TITLE}</span>
                <Textarea value={typed} onValue={setKeep} rows={KEEP_ROWS} className="resize-y" />
              </label>
              <div>
                <Button disabled={busy} onClick={preview}>
                  {LayersPageLines.previewList}
                </Button>
              </div>
            </Card>
          </Section>
        </>
      )}
      {reviewing && memory.plan !== undefined && (
        <PlanDialog
          plan={memory.plan}
          busy={busy}
          cancel={close}
          confirm={() =>
            void memory.confirmLayers().then((outcome) => {
              setNote(outcome.kind === 'failed' ? outcome.why : outcome.note);
              setReviewing(false);
            })
          }
        />
      )}
    </div>
  );
}

/** One numbered layer: its number in a badge, the file, what it is for, and how it stands. */
function LayerCardView({ card }: { card: LayerCard }) {
  return (
    <div className="flex items-center gap-3 rounded-card border border-panel-edge bg-card p-4" role="group" aria-label={LayersPageLines.layerLabel(card.number, card.file, card.role, card.state)}>
      <span
        aria-hidden
        className={`grid size-[26px] shrink-0 place-items-center rounded-full text-body-sm font-semibold tabular-nums ${
          card.settled ? 'bg-[color-mix(in_oklab,var(--mx-success)_14%,transparent)] text-success' : 'bg-[color-mix(in_oklab,var(--mx-faint)_14%,transparent)] text-muted'
        }`}
      >
        {card.number}
      </span>
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="flex flex-wrap items-baseline gap-2">
          <span className="font-code text-body-sm font-medium text-foreground">{card.file}</span>
          <span className="text-meta text-muted">{card.role}</span>
        </span>
        <span className="text-meta text-faint">{card.state}</span>
      </span>
    </div>
  );
}

const MARK: Record<PlanDiffMark, string> = { added: '+', removed: '−', same: ' ' };
const TINT: Record<PlanDiffMark, string> = {
  added: 'bg-[color-mix(in_oklab,var(--mx-success)_14%,transparent)] text-foreground',
  removed: 'bg-[color-mix(in_oklab,var(--mx-destructive)_14%,transparent)] text-foreground',
  same: 'text-muted',
};
const MARK_TINT: Record<PlanDiffMark, string> = { added: 'text-success', removed: 'text-destructive', same: 'text-muted' };

/** The map the runtime would write, file by file as a diff, then a confirm before it writes anything. */
function PlanDialog({ plan, busy, cancel, confirm }: { plan: MemoryLayersPlan; busy: boolean; cancel: () => void; confirm: () => void }) {
  const [confirming, setConfirming] = useState(false);
  const summary = planSummary(plan);
  const changed = plan.files.some((file) => file.changed);
  if (confirming) {
    // The Mac asks with its console confirm, in blue since writing the map takes nothing away.
    return <ConfirmDialog icon={Layers} tone="neutral" title={PLAN_CONFIRM.title} message={summary} detail={PLAN_CONFIRM.detail} confirm={PLAN_CONFIRM.confirm} busy={busy} cancel={() => setConfirming(false)} act={confirm} />;
  }
  return (
    <Dialog
      title={LayersPageLines.mapTitle}
      step={summary}
      close={cancel}
      actions={
        <>
          <span className="flex-1" />
          <Button kind="primary" disabled={busy || !changed} onClick={() => setConfirming(true)}>
            {LayersPageLines.confirm}
          </Button>
        </>
      }
    >
      {plan.files.map((file) => (
        <div key={file.path} className="flex flex-col gap-1.5">
          <p className={`font-code text-meta font-medium ${file.changed ? 'text-foreground' : 'text-faint'}`}>{file.path}</p>
          {file.changed && (
            <div className="overflow-hidden rounded-control border border-panel-edge bg-field py-1.5">
              {planDiff(file.before, file.after).map((line) => (
                <div key={line.index} className={`flex gap-2 px-2 font-code text-meta ${TINT[line.mark]}`}>
                  <span className={MARK_TINT[line.mark]} aria-hidden>
                    {MARK[line.mark]}
                  </span>
                  <span className="min-w-0 whitespace-pre-wrap break-words">{line.text === '' ? ' ' : line.text}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      ))}
    </Dialog>
  );
}
