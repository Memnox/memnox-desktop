import { useState } from 'react';
import type { WorkOutcome } from '../../../core/application/agent-work';
import type { AgentWork } from '../../../core/domain/agent-wire';
import {
  handoffLine,
  issueLine,
  latestLine,
  needsYou,
  openWork,
  trackerName,
  waitingHandoff,
  workLink,
  workStatusLine,
} from '../../../core/domain/agent-work-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Button, Card, Note, Section, StatusWord } from '../../kit';

/** The local work waiting on the person, a handoff to answer or a done claim to check, for Needs your attention. */
export function WorkNeedingYou({ parts }: { parts: SettingsParts }) {
  const { work, profiles, host } = parts;
  useObserved(work, profiles);
  const [note, setNote] = useState<string | undefined>(undefined);
  const waiting = openWork(work.work ?? []).filter(needsYou);
  if (waiting.length === 0) return null;
  const said = (outcome: WorkOutcome) => setNote(outcome.kind === 'done' ? outcome.note : outcome.why);
  const names = new Map((profiles.profiles ?? []).map((each) => [each.id, each.name]));
  return (
    <Section title={`Agent work · ${waiting.length}`}>
      {note !== undefined && <Note>{note}</Note>}
      <div className="flex flex-col gap-3">
        {waiting.map((each) => (
          <WorkCard key={each.id} work={each} name={(id) => names.get(id)} busy={work.busy !== undefined} open={(url) => host.openPage(url)}
            answer={(handoff, word) => void work.answer(handoff, word).then(said)} close={() => void work.close(each.id).then(said)} stop={() => void work.stop(each.id).then(said)} />
        ))}
      </div>
    </Section>
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

export function WorkCard({ work, name, busy, open, answer, close, stop }: {
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
