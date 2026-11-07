import { Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { groupedDigits } from '../../../core/domain/account-whole';
import { ServerPairingLines } from '../../../core/domain/server-pairing-lines';
import { WorkspaceLines } from '../../../core/domain/workspace-lines';
import { DONE, needs, WAITING, type StepState } from '../../../core/domain/step-state';
import { Digits, IconTile, QuietLine, Surface } from '../kit';
import { useObserved, type SettingsParts } from '../parts';
import { SetupStep } from '../steps';
import { Button, Input, Spinner } from '../../kit';
import { RelayLines } from '../../../core/domain/relay-lines';

/** What a pairing link looks like, shown in the field before one is pasted. */
const PAIR_LINK_EXAMPLE = 'memnox://pair?d=...';
/** The link field, wide enough to show that a whole link was pasted. */
const LINK_FIELD_WIDTH = 320;

/**
 * `SetupServerCard`: connecting to a server, the link pasted from memnox pair, the digits to type there, and each
 * server kept with whether the voice talks to it and a way to forget it. Under the phones, as on the Mac.
 */
export function ServerCard({ parts }: { parts: SettingsParts }) {
  const { servers } = parts;
  useObserved(servers);
  const [link, setLink] = useState('');
  useEffect(() => void servers.load(), []);
  const step = servers.step;
  const busy = step.kind === 'pairing' || step.kind === 'showing-code';
  const state: StepState = step.kind === 'failed' ? needs(step.why) : step.kind === 'connected' || servers.servers.length > 0 ? DONE : WAITING;
  const connect = () => {
    const pasted = link;
    void servers.connect(pasted).then(() => {
      if (servers.step.kind === 'connected') setLink('');
    });
  };
  return (
    <Surface>
      <SetupStep
        state={state}
        title={RelayLines.connectServer}
        detail={RelayLines.connectServerDetail}
        trailing={
          busy ? (
            <Spinner />
          ) : (
            <Button disabled={link.trim() === ''} onClick={connect}>
              {RelayLines.connect}
            </Button>
          )
        }
        extra={
          <div className="flex flex-col items-start gap-3">
            {step.kind === 'pairing' && <QuietLine>{ServerPairingLines.meeting}</QuietLine>}
            {step.kind === 'showing-code' && (
              <div className="flex flex-col items-start gap-1.5">
                <Digits code={groupedDigits(step.code)} />
                <QuietLine>{ServerPairingLines.typeCode}</QuietLine>
              </div>
            )}
            {!busy && <Input value={link} placeholder={PAIR_LINK_EXAMPLE} onValue={setLink} onSubmit={connect} width={LINK_FIELD_WIDTH} />}
            {step.kind === 'connected' && <p className="text-caption font-semibold text-green">{ServerPairingLines.connected(step.name)}</p>}
            {servers.servers.length > 0 && (
              <div className="flex w-full flex-col gap-2">
                <MachineRow parts={parts} name={ServerPairingLines.thisComputer} id={undefined} />
                {servers.servers.map((server) => (
                  <MachineRow key={server.machineId} parts={parts} name={server.machine} id={server.machineId} />
                ))}
              </div>
            )}
          </div>
        }
        hint={step.kind === 'failed'}
      />
    </Surface>
  );
}

/** One machine: its name, whether the voice talks to it, and Forget for a server. */
function MachineRow({ parts, name, id }: { parts: SettingsParts; name: string; id: string | undefined }) {
  const { servers } = parts;
  const talking = servers.talkingTo === id;
  return (
    <div className="flex w-full items-center gap-3">
      <span className="text-footnote font-semibold text-foreground">{name}</span>
      <span className="flex-1" />
      {talking ? <span className="text-caption text-green">{RelayLines.talking}</span> : <Button onClick={() => servers.talkTo(id)}>{RelayLines.talkTo}</Button>}
      {id !== undefined && <Button onClick={() => void servers.forget(id)}>{RelayLines.forget}</Button>}
    </div>
  );
}

/** The person's own sign in to their workspace, which brings the calls it routes to them onto the island. */
export function TeamRow({ parts }: { parts: SettingsParts }) {
  const { team } = parts;
  useObserved(team);
  useEffect(() => void team.load(), []);
  const step = team.step;
  const state: StepState = step.kind === 'signed-in' ? DONE : step.kind === 'failed' ? needs(step.why) : WAITING;
  const detail =
    step.kind === 'signed-in'
      ? RelayLines.signedInAs(step.name, parts.words.keyTitle)
      : RelayLines.answerCalls(parts.words.keyTitle);
  const trailing =
    step.kind === 'starting' ? (
      <Spinner />
    ) : step.kind === 'showing-code' ? (
      <Button onClick={() => team.cancel()}>{RelayLines.cancel}</Button>
    ) : step.kind === 'signed-in' ? (
      <Button onClick={() => void team.signOut()}>{RelayLines.signOut}</Button>
    ) : (
      <Button kind="primary" onClick={() => void team.start()}>
        {step.kind === 'failed' ? RelayLines.tryAgain : RelayLines.signIn}
      </Button>
    );
  return (
    <SetupStep
      state={state}
      title={RelayLines.teamCalls}
      detail={detail}
      tile={<IconTile icon={Users} />}
      trailing={trailing}
      extra={
        step.kind === 'showing-code' ? (
          <div className="flex flex-col items-start gap-1.5">
            <Digits code={step.code} />
            <QuietLine>{WorkspaceLines.enterCode(step.code)}</QuietLine>
          </div>
        ) : undefined
      }
    />
  );
}
