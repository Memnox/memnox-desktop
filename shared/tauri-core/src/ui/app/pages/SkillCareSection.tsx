import type { SkillCalibration, SkillView } from '@memnox/core/wire';
import { useEffect, useState } from 'react';
import type { SkillOutcome } from '../../../core/application/skills';
import { calibrateHint, careCounts, lineDiff, noteLine, suggestionTitle, type DiffMark } from '../../../core/domain/skill-care-lines';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Section } from '../widgets';

const MARK: Record<DiffMark, { sign: string; className: string }> = {
  same: { sign: ' ', className: 'text-muted' },
  added: { sign: '+', className: 'text-success bg-[color-mix(in_oklab,var(--mx-success)_10%,transparent)]' },
  removed: { sign: '-', className: 'text-destructive bg-[color-mix(in_oklab,var(--mx-destructive)_10%,transparent)]' },
};

/**
 * How a skill fared in the chats lately, its fix backlog with a field to add to it, Calibrate, and the suggested fix
 * as a diff with Accept, as the Mac's `SkillCareSection` draws them. Accept sends the new version through skill-put,
 * so one reaching further waits on the island and nothing here grants anything.
 */
export function SkillCareSection({ parts, skill, said }: { parts: SettingsParts; skill: SkillView; said: (outcome: SkillOutcome) => void }) {
  const { skillCare: care, skills } = parts;
  useObserved(care);
  const [typed, setTyped] = useState('');
  useEffect(() => {
    void care.refresh();
  }, [skill.name]);
  // An older runtime does not count skills, so the section stays out rather than saying zero.
  if (!care.answered) return null;
  const stats = care.stats(skill.name);
  const hint = calibrateHint(stats);
  const calibration = care.calibration?.name === skill.name ? care.calibration : undefined;
  const note = () => {
    if (noteLine(typed) === undefined) return;
    const words = typed;
    setTyped('');
    void care.note(skill.name, words).then(said);
  };
  return (
    <Section title="Use and fixes">
      <div className="flex flex-col gap-3">
        <p className="text-body-sm text-foreground">{careCounts(stats)}</p>
        {stats !== undefined && stats.recentFailures.length > 0 && <Listed title="Recent failures" lines={stats.recentFailures} />}
        {stats !== undefined && stats.notes.length > 0 && <Listed title="Fix backlog" lines={stats.notes} />}
        <form
          className="flex items-center gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            note();
          }}
        >
          <input
            value={typed}
            onChange={(event) => setTyped(event.target.value)}
            placeholder="Note a fix, such as read the staged diff first"
            aria-label="Note a fix"
            className="mx-field h-9 min-w-0 flex-1 rounded-md border border-field-edge bg-field px-3 text-body-sm text-foreground placeholder:text-faint"
          />
          <KitButton type="submit" disabled={noteLine(typed) === undefined || care.busy !== undefined}>
            Note
          </KitButton>
        </form>
        <div className="flex flex-wrap items-center gap-2">
          <KitButton disabled={care.busy !== undefined} onClick={() => void care.calibrate(skill.name).then(said)}>
            Calibrate
          </KitButton>
          {hint !== undefined && <span className="text-meta text-faint">{hint}</span>}
        </div>
        {calibration !== undefined && (
          <Suggestion
            calibration={calibration}
            current={skill.version}
            busy={care.busy !== undefined}
            accept={() =>
              void care
                .accept(calibration, skill.scope, skill.project)
                .then(async (outcome) => {
                  await skills.refresh();
                  return outcome;
                })
                .then(said)
            }
            dismiss={() => care.dismissSuggestion()}
          />
        )}
      </div>
    </Section>
  );
}

function Suggestion({ calibration, current, busy, accept, dismiss }: { calibration: SkillCalibration; current: string; busy: boolean; accept: () => void; dismiss: () => void }) {
  return (
    <div className="flex flex-col gap-2.5">
      <p className="text-body-sm font-semibold text-foreground">{suggestionTitle(calibration, current)}</p>
      <pre className="max-h-[320px] overflow-auto rounded-xl border border-panel-edge bg-card py-2 font-code text-meta">
        {lineDiff(calibration.before, calibration.after).map((line) => (
          <div key={line.index} className={`flex gap-3 px-3 whitespace-pre-wrap ${MARK[line.mark].className}`}>
            <span aria-hidden className="select-none">
              {MARK[line.mark].sign}
            </span>
            <span className="sr-only">{line.mark === 'same' ? '' : line.mark}</span>
            <span>{line.text}</span>
          </div>
        ))}
      </pre>
      <div className="flex gap-2">
        <KitButton kind="primary" disabled={busy} onClick={accept}>
          Accept
        </KitButton>
        <KitButton onClick={dismiss}>Dismiss</KitButton>
      </div>
    </div>
  );
}

function Listed({ title, lines }: { title: string; lines: readonly string[] }) {
  return (
    <div className="flex flex-col gap-1">
      <p className="text-meta font-medium text-muted">{title}</p>
      {lines.map((line, index) => (
        <p key={index} className="text-meta text-foreground">
          {line}
        </p>
      ))}
    </div>
  );
}
