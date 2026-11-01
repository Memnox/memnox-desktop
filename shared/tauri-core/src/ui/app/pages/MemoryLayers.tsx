import { Layers } from 'lucide-react';
import { useEffect, useState } from 'react';
import {
  COST_FOOTNOTE,
  KEEP_TITLE,
  LAYERS_EMPTY,
  PLAN_CONFIRM,
  keepList,
  layerCards,
  planDiff,
  planSummary,
  sessionCostLines,
  valueLines,
  type LayerCard,
  type MemoryLayersPlan,
  type PlanDiffMark,
} from '../../../core/domain/memory-layers-lines';
import { KitButton, SelectMenu } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Dialog } from './SkillDialogs';
import { EmptyState, ReadFailed, Section } from '../widgets';

/**
 * Memory as three layers any agent reads, numbered as the long term stack, ported from the Mac's Layers view: 1
 * MEMORY.md for every chat, 2 the router, 3 SKILL.md for live data. Below them the short term card with the cold
 * cache numbers, then the keep on compact list. Preview asks the runtime for the map, and only a confirm writes it,
 * inside Memnox's fenced blocks, with the plan's digest so a file changed since is refused.
 */
export function MemoryLayersView({ parts }: { parts: SettingsParts }) {
  const { memory } = parts;
  useObserved(memory);
  const [chosen, setChosen] = useState<string | undefined>(undefined);
  const [keep, setKeep] = useState<string | undefined>(undefined);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [reviewing, setReviewing] = useState(false);
  useEffect(() => {
    void memory.refreshLayers();
  }, []);

  const view = memory.layers;
  if (view === undefined) {
    if (memory.layersUnreadable) return <ReadFailed what="the memory layers" retry={() => void memory.refreshLayers()} />;
    return <p className="text-body-sm text-muted">Reading the memory layers.</p>;
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
      {note !== undefined && (
        <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote text-foreground">
          {note}
        </p>
      )}
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
              <SelectMenu
                label="Project"
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
            title="Long-term memory"
            trailing={
              <KitButton kind="primary" disabled={busy} onClick={preview}>
                Preview the map
              </KitButton>
            }
          >
            <div className="flex flex-col gap-2">
              {layerCards(project).map((card) => (
                <LayerCardView key={card.number} card={card} />
              ))}
            </div>
          </Section>
          <Section title="Short-term memory">
            <div className="flex flex-col gap-3 rounded-xl border border-panel-edge bg-card p-4">
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
                <textarea
                  value={typed}
                  onChange={(event) => setKeep(event.target.value)}
                  rows={4}
                  className="mx-field w-full resize-y rounded-lg border border-field-edge bg-field px-3 py-2 text-body-sm text-foreground outline-none"
                />
              </label>
              <div>
                <KitButton disabled={busy} onClick={preview}>
                  Preview with this list
                </KitButton>
              </div>
            </div>
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
    <div
      className="flex items-center gap-3 rounded-xl border border-panel-edge bg-card p-4"
      role="group"
      aria-label={`Layer ${card.number}, ${card.file}, ${card.role}. ${card.state}`}
    >
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
    return (
      <Dialog
        title={PLAN_CONFIRM.title}
        close={() => setConfirming(false)}
        footer={
          <>
            <span className="flex-1" />
            <KitButton onClick={() => setConfirming(false)}>Cancel</KitButton>
            <KitButton kind="primary" disabled={busy} onClick={confirm}>
              {PLAN_CONFIRM.confirm}
            </KitButton>
          </>
        }
      >
        <p className="text-body-sm text-foreground">{summary}</p>
        <p className="text-body-sm text-muted">{PLAN_CONFIRM.detail}</p>
      </Dialog>
    );
  }
  return (
    <Dialog
      title="The new memory map"
      step={summary}
      close={cancel}
      footer={
        <>
          <span className="flex-1" />
          <KitButton onClick={cancel}>Cancel</KitButton>
          <KitButton kind="primary" disabled={busy || !changed} onClick={() => setConfirming(true)}>
            Confirm
          </KitButton>
        </>
      }
    >
      {plan.files.map((file) => (
        <div key={file.path} className="flex flex-col gap-1.5">
          <p className={`font-code text-meta font-medium ${file.changed ? 'text-foreground' : 'text-faint'}`}>{file.path}</p>
          {file.changed && (
            <div className="overflow-hidden rounded-md border border-panel-edge bg-field py-1.5">
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
