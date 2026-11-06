import { Smartphone, Wifi } from 'lucide-react';
import { useEffect, useState } from 'react';
import { LAN_BOUNDS, LAN_WHAT, lanPhonesLine, lanStatusLine, lanSwitchCaption, lanWaitsLine } from '../../../core/domain/local-network-lines';
import { SettingsCard, SettingsDivider, SettingsRow, SwitchRow } from '../kit';
import { useObserved, type SettingsParts } from '../parts';
import { ReadFailed } from '../../kit';
import { NetworkPageLines } from '../../../core/domain/network-page-lines';

/**
 * Whether paired phones reach this computer over the network it shares with them. The runtime decides:
 * turning it off is done at once, and turning it on is only proposed, holding once signed on the island.
 */
export function NetworkPage({ parts }: { parts: SettingsParts }) {
  const { network, words } = parts;
  useObserved(network);
  useEffect(() => void network.refresh(), []);
  const [note, setNote] = useState<{ text: string; alert: boolean } | undefined>(undefined);
  const lan = network.status;
  if (lan === undefined) return network.unreadable ? <ReadFailed what="the local network" retry={() => void network.refresh()} /> : null;

  const flip = async (on: boolean) => {
    const outcome = await network.set(on);
    if (outcome.kind === 'failed') return setNote({ text: outcome.why, alert: true });
    setNote(outcome.kind === 'proposed' ? { text: lanWaitsLine(words.keyTitle), alert: false } : undefined);
  };

  return (
    <SettingsCard title={NetworkPageLines.title}>
      <p className="text-footnote text-muted">{LAN_WHAT}</p>
      <p className="text-footnote text-muted">{LAN_BOUNDS}</p>
      <SwitchRow icon={Wifi} title={NetworkPageLines.reach} caption={lanSwitchCaption(lan.on, words.keyTitle)} on={lan.on} disabled={network.busy} onChange={(on) => void flip(on)} />
      {note !== undefined && (
        <p role={note.alert ? 'alert' : 'status'} className={`text-footnote ${note.alert ? 'text-destructive' : 'text-foreground'}`}>
          {note.text}
        </p>
      )}
      <SettingsDivider full />
      <SettingsRow icon={Wifi} title={NetworkPageLines.status} caption={lanStatusLine(lan)} />
      <SettingsRow icon={Smartphone} title={NetworkPageLines.phones} caption={lanPhonesLine(lan)} />
    </SettingsCard>
  );
}
