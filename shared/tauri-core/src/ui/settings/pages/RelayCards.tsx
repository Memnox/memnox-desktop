import { Users } from 'lucide-react';
import { useEffect, useState } from 'react';
import { groupedDigits } from '../../../core/domain/account-whole';
import { ServerPairingLines } from '../../../core/domain/server-pairing-lines';
import { WorkspaceLines } from '../../../core/domain/workspace-lines';
import { DONE, needs, WAITING, type StepState } from '../../../core/domain/step-state';
import { Digits, IconTile, KitButton, KitField, QuietLine, Spinner, Surface } from '../kit';
import { useObserved, type SettingsParts } from '../parts';
import { SetupStep } from '../steps';

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
        title="Connect to a server"
        detail="Optional. Talk to Memnox on a Linux server through the relay. Run memnox pair there and paste the link it prints."
        trailing={
          busy ? (
            <Spinner />
          ) : (
            <KitButton disabled={link.trim() === ''} onClick={connect}>
              Connect
            </KitButton>
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
            {!busy && <KitField value={link} placeholder="memnox://pair?d=..." onChange={setLink} onSubmit={connect} width={320} />}
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
      {talking ? <span className="text-caption text-green">Talking to it</span> : <KitButton onClick={() => servers.talkTo(id)}>Talk to it</KitButton>}
      {id !== undefined && <KitButton onClick={() => void servers.forget(id)}>Forget</KitButton>}
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
      ? `Signed in as ${step.name}. Calls your workspace routes to you show on the island, and every yes asks for ${parts.words.keyTitle}.`
      : `Answer the calls your workspace routes to you from the island, each yes signed with ${parts.words.keyTitle}.`;
  const trailing =
    step.kind === 'starting' ? (
      <Spinner />
    ) : step.kind === 'showing-code' ? (
      <KitButton onClick={() => team.cancel()}>Cancel</KitButton>
    ) : step.kind === 'signed-in' ? (
      <KitButton onClick={() => void team.signOut()}>Sign out</KitButton>
    ) : (
      <KitButton kind="primary" onClick={() => void team.start()}>
        {step.kind === 'failed' ? 'Try again' : 'Sign in'}
      </KitButton>
    );
  return (
    <SetupStep
      state={state}
      title="Your team's calls"
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
