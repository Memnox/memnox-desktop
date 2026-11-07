import type { ProfileView } from '@memnox/core/wire';
import { ListChecks } from 'lucide-react';
import { useEffect, useState } from 'react';
import type { WorkOutcome } from '../../../core/application/agent-work';
import type { AgentWork, Tracker } from '../../../core/domain/agent-wire';
import {
  finishedWork,
  handoffLine,
  issueLine,
  latestLine,
  needsYou,
  openWork,
  orderedProfiles,
  targetProblem,
  trackerName,
  waitingHandoff,
  workLink,
  workStatusLine,
} from '../../../core/domain/agent-work-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Button, Card, EmptyState, ErrorLine, Field, Input, Note, Section, Select, StatusWord } from '../../kit';

const TRACKERS: readonly Tracker[] = ['linear', 'jira', 'github', 'asana'];

/**
 * Agent work under AI agents, as the Mac's `WorkDestination`: each piece joined to the issue where it lives, with its
 * link, where it stands and the latest word from its agent. Every press is an unsigned steer the daemon decides.
 */
export function WorkTab({ parts }: { parts: SettingsParts }) {
  const { work, profiles, host } = parts;
  useObserved(work, profiles);
  useEffect(() => {
    void work.refresh();
    void profiles.refresh();
  }, []);
  const [note, setNote] = useState<string | undefined>(undefined);
  const [starting, setStarting] = useState(false);
  const said = (outcome: WorkOutcome) => setNote(outcome.kind === 'done' ? outcome.note : outcome.why);
  const all = work.work;
  if (all === undefined) return work.unreadable ? <ErrorLine>The agent work could not be read.</ErrorLine> : null;
  const names = new Map((profiles.profiles ?? []).map((each) => [each.id, each.name]));
  const open = openWork(all);
  const finished = finishedWork(all);
  return (
    <div className="flex flex-col gap-6">
      {note !== undefined && <Note>{note}</Note>}
      <div className="flex items-start gap-3">
        <p className="min-w-0 flex-1 text-footnote text-muted">The issue stays in Linear, Jira, GitHub or Asana. Memnox keeps only which agent carries it and what it said.</p>
        {!starting && (
          <Button kind="primary" onClick={() => setStarting(true)}>
            Start work
          </Button>
        )}
      </div>
      {starting && <StartForm profiles={profiles.profiles ?? []} busy={work.busy !== undefined} cancel={() => setStarting(false)} start={(profile, target, extra) => void work.start(profile, target, extra).then((outcome) => { said(outcome); if (outcome.kind === 'done') setStarting(false); })} />}
      {open.length === 0 ? (
        <EmptyState icon={ListChecks} title="No agent is on any work" body="Start work to point one of your agents at an issue, such as LIN-123, or paste its link." />
      ) : (
        <Section title={`Open · ${open.length}`}>
          <div className="flex flex-col gap-3">
            {open.map((each) => (
              <WorkCard key={each.id} work={each} name={(id) => names.get(id)} busy={work.busy !== undefined} open={(url) => host.openPage(url)}
                answer={(handoff, word) => void work.answer(handoff, word).then(said)} close={() => void work.close(each.id).then(said)} stop={() => void work.stop(each.id).then(said)} />
            ))}
          </div>
        </Section>
      )}
      {finished.length > 0 && (
        <Section title={`Finished · ${finished.length}`}>
          <div className="flex flex-col gap-3">
            {finished.map((each) => (
              <WorkLine key={each.id} work={each} open={(url) => host.openPage(url)} />
            ))}
          </div>
        </Section>
      )}
    </div>
  );
}

/** The issue an agent carries, its state and its latest word, opening the issue in its tracker where it has a link. */
export function WorkLine({ work, open }: { work: AgentWork; open?: (url: string) => void }) {
  const link = workLink(work);
  return (
    <div className="flex flex-col gap-0.5">
      <div className="flex items-center gap-2 text-body-sm">
        {link !== undefined && open !== undefined ? (
          <Button kind="link" title={`Open it in ${trackerName(work.target.source)}`} onClick={() => open(link)}>
            {issueLine(work)}
          </Button>
        ) : (
          <span className="truncate text-foreground">{issueLine(work)}</span>
        )}
        <span className="flex-1" />
        <StatusWord tone={needsYou(work) ? 'attention' : 'quiet'}>{workStatusLine(work)}</StatusWord>
      </div>
      <span className="text-meta text-muted">{latestLine(work)}</span>
    </div>
  );
}

function WorkCard({ work, name, busy, open, answer, close, stop }: {
  work: AgentWork;
  name: (id: string) => string | undefined;
  busy: boolean;
  open: (url: string) => void;
  answer: (handoff: string, word: 'accept' | 'decline') => void;
  close: () => void;
  stop: () => void;
}) {
  const handoff = waitingHandoff(work);
  return (
    <Card label={issueLine(work)} className="flex flex-col gap-3">
      <WorkLine work={work} open={open} />
      <span className="text-footnote text-muted">{`${name(work.profileId) ?? work.profileId} · answers to ${work.responsiblePerson}`}</span>
      {handoff !== undefined && <p className="text-footnote text-foreground">{handoffLine(handoff, name)}</p>}
      <div className="flex items-center gap-2">
        {handoff !== undefined ? (
          <>
            <Button kind="primary" disabled={busy} onClick={() => answer(handoff.id, 'accept')}>Accept</Button>
            <Button disabled={busy} onClick={() => answer(handoff.id, 'decline')}>Decline</Button>
          </>
        ) : work.status === 'done_claimed' ? (
          <Button kind="primary" disabled={busy} onClick={close} title="Closes it as done, once you checked what the agent says it did">Confirm</Button>
        ) : (
          <Button disabled={busy} onClick={close}>Close as done</Button>
        )}
        {/* Set apart, so stopping an agent is never pressed by a slip. */}
        <span className="flex-1" />
        <Button disabled={busy} onClick={stop}>Stop</Button>
      </div>
    </Card>
  );
}

function StartForm({ profiles, busy, cancel, start }: {
  profiles: readonly ProfileView[];
  busy: boolean;
  cancel: () => void;
  start: (profile: string, target: string, extra: { tracker: Tracker; title: string; project: string }) => void;
}) {
  const offered = orderedProfiles(profiles).filter((each) => each.connections.length > 0);
  const [profile, setProfile] = useState(offered[0]?.id ?? '');
  const [target, setTarget] = useState('');
  const [tracker, setTracker] = useState<Tracker>('linear');
  const [title, setTitle] = useState('');
  const [project, setProject] = useState('');
  const [problem, setProblem] = useState<string | undefined>(undefined);
  return (
    <Card className="flex flex-col gap-3">
      {offered.length === 0 ? (
        <p className="text-footnote text-muted">No agent is connected yet. Give one of your agents a job first.</p>
      ) : (
        <Field label="Agent">
          <Select value={profile} label="Agent" wide options={offered.map((each) => ({ value: each.id, label: each.name }))} onChange={setProfile} />
        </Field>
      )}
      <Field label="Issue" {...(problem === undefined ? {} : { error: problem })}>
        <Input value={target} placeholder="LIN-123, PAY-42 or the issue's link" onValue={setTarget} />
      </Field>
      <Field label="Tracker, for a bare key">
        <Select value={tracker} label="Tracker" wide options={TRACKERS.map((each) => ({ value: each, label: trackerName(each) }))} onChange={setTracker} />
      </Field>
      <Field label="Title, optional">
        <Input value={title} placeholder="Shown beside the key, never fetched" onValue={setTitle} />
      </Field>
      <Field label="Repository, optional">
        <Input value={project} placeholder="The repository it is scoped to" onValue={setProject} />
      </Field>
      <div className="flex gap-2">
        <Button
          kind="primary"
          busy={busy}
          disabled={profile === ''}
          onClick={() => {
            const missing = targetProblem(target);
            setProblem(missing);
            if (missing === undefined) start(profile, target, { tracker, title, project });
          }}
        >
          Start
        </Button>
        <Button onClick={cancel}>Cancel</Button>
      </div>
    </Card>
  );
}
