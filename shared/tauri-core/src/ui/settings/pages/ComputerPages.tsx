import { Check, Copy, Fingerprint, MousePointerClick, RotateCw, Smartphone, SquareTerminal } from 'lucide-react';
import { Fragment, useEffect } from 'react';
import { groupedDigits } from '../../../core/domain/account-whole';
import { ISLAND_STAYS_DARK, LOOK_NAMES, LOOKS, type Look } from '../../../core/domain/appearance';
import { LAN_PAIRS_WITHOUT_ACCOUNT } from '../../../core/domain/local-network-lines';
import { deviceCaption, drives, PairingLines } from '../../../core/domain/pairing-lines';
import type { PermissionStep } from '../../../core/domain/permission-steps';
import { DONE, WAITING } from '../../../core/domain/step-state';
import { Digits, IconTile, MemnoxTile, QuietLine, SettingsCard, SettingsDivider, SettingsRow, Surface, SwitchRow, useCopied } from '../kit';
import { IslandScreenPicker } from '../IslandScreenPicker';
import { useObserved, usePreferences, type SettingsParts } from '../parts';
import { PermissionGuide, QrCode, SetupDivider, SetupStep } from '../steps';
import { ServerCard, TeamRow } from './RelayCards';
import { Button, Spinner, Pressable } from '../../kit';
import { ComputerLines } from '../../../core/domain/computer-lines';

/**
 * The Permissions page: what this computer lets Memnox hear, type and see, as the Mac's
 * `SetupPermissionsCard`, with each system's own answer, and starting when the person signs in.
 */
export function PermissionsPage({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  useObserved(steps);
  useEffect(() => void steps.refresh(), []);
  return (
    <Surface>
      {steps.permissions.map((step) => (
        <Fragment key={step.id}>
          <PermissionRow parts={parts} step={step} />
          <SetupDivider />
        </Fragment>
      ))}
      <StartAtSignInRow parts={parts} />
    </Surface>
  );
}

/** One permission: Allow until it is done, and the guide with the steps to take once it needs the person. */
export function PermissionRow({ parts, step }: { parts: SettingsParts; step: PermissionStep }) {
  const { host, steps, words } = parts;
  const pane = step.pane;
  const open = pane === undefined ? undefined : () => void host.openPrivacy(pane).then(() => steps.readPermissions());
  return (
    <SetupStep
      state={step.state}
      title={step.title}
      detail={step.detail}
      trailing={
        step.state.kind === 'waiting' ? (
          <Button kind="primary" onClick={() => void steps.readPermissions()}>
            {ComputerLines.allow}
          </Button>
        ) : undefined
      }
      extra={
        step.state.kind === 'needs' && step.guide.length > 0 ? (
          <PermissionGuide steps={step.guide} pane={pane === 'microphone' ? 'Microphone' : undefined} switchName={step.switchName} settingsApp={words.settingsApp} open={open}>
            <Button icon={RotateCw} onClick={() => void steps.readPermissions()}>
              {ComputerLines.checkAgain}
            </Button>
          </PermissionGuide>
        ) : undefined
      }
    />
  );
}

/** Starting at sign in, which the Mac leaves to its login items and Windows and Linux ask of the app. */
function StartAtSignInRow({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  const on = steps.startsAtSignIn === true;
  return (
    <SetupStep
      state={on ? DONE : WAITING}
      title={ComputerLines.startAtSignIn}
      detail={ComputerLines.startAtSignInDetail}
      trailing={
        on ? (
          <Button onClick={() => void steps.setStartsAtSignIn(false)}>{ComputerLines.turnOff}</Button>
        ) : (
          <Button kind="primary" onClick={() => void steps.setStartsAtSignIn(true)}>
            {ComputerLines.turnOn}
          </Button>
        )
      }
    />
  );
}

/** The Connection page: the Memnox service and the confirm key, each with Check again until it is done. */
export function ConnectionPage({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  useObserved(steps);
  useEffect(() => void steps.refresh(), []);
  return (
    <Surface>
      <ServiceRow parts={parts} />
      <SetupDivider />
      <KeyRow parts={parts} />
      {steps.editor.shown && (
        <>
          <SetupDivider />
          <EditorRow parts={parts} />
        </>
      )}
      <SetupDivider />
      <TeamRow parts={parts} />
    </Surface>
  );
}

/** The Memnox terminals extension the daemon puts into the editors here; the app only looks whether it landed. */
export function EditorRow({ parts }: { parts: SettingsParts }) {
  const editor = parts.steps.editor;
  return (
    <SetupStep
      state={editor.state}
      title={ComputerLines.editor}
      detail={editor.detail}
      tile={<IconTile icon={SquareTerminal} />}
      trailing={editor.state.kind === 'done' ? undefined : <Button onClick={() => void parts.steps.readPermissions()}>{ComputerLines.checkAgain}</Button>}
    />
  );
}

export function ServiceRow({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  const service = steps.service;
  const working = parts.setup.state.doing !== undefined;
  return (
    <SetupStep
      state={service.state}
      title={ComputerLines.service}
      detail={service.detail}
      tile={<MemnoxTile />}
      trailing={service.state.kind === 'done' ? undefined : working ? <Spinner /> : <Button onClick={() => void steps.checkService()}>{ComputerLines.checkAgain}</Button>}
    />
  );
}

export function KeyRow({ parts }: { parts: SettingsParts }) {
  const { steps, words } = parts;
  const state = steps.keyState;
  return (
    <SetupStep
      state={state}
      title={words.keyTitle}
      detail={words.keyDetail}
      tile={<IconTile icon={Fingerprint} />}
      trailing={state.kind === 'done' ? undefined : <Button onClick={() => void steps.checkKey()}>{ComputerLines.checkAgain}</Button>}
    />
  );
}

/** The Phones page: pair a phone with a QR and matching digits, then each phone paired with Revoke and driving. */
export function PhonesPage({ parts }: { parts: SettingsParts }) {
  const { pairing, network } = parts;
  useObserved(pairing, network);
  useEffect(() => {
    void pairing.loadDevices();
    // Only to say pairing needs no account while the local network is on; a runtime without it says nothing.
    void network.refresh();
  }, []);
  return (
    <>
      <Surface>
        <PairRow parts={parts} />
      </Surface>
      {network.status !== undefined && network.status.on && <p className="px-1 text-footnote text-muted">{LAN_PAIRS_WITHOUT_ACCOUNT}</p>}
      {pairing.devices.length > 0 && (
        <SettingsCard title={ComputerLines.pairedPhones}>
          {pairing.devices.map((device, index) => (
            <Fragment key={device.id}>
              {index > 0 && <SettingsDivider full />}
              <SettingsRow icon={Smartphone} title={device.name} caption={deviceCaption(device)}>
                <Button onClick={() => void pairing.revoke(device)}>Revoke</Button>
              </SettingsRow>
              <SwitchRow
                icon={MousePointerClick}
                title={ComputerLines.drive}
                caption={drives(device) ? ComputerLines.stopDriving : ComputerLines.keyTurnsOn(parts.words.keyTitle)}
                on={drives(device)}
                onChange={(on) => void pairing.letDrive(device, on)}
              />
            </Fragment>
          ))}
        </SettingsCard>
      )}
      <ServerCard parts={parts} />
    </>
  );
}

/** `SetupPhoneCard`: Pair, the QR, the digits to check, then paired. */
function PairRow({ parts }: { parts: SettingsParts }) {
  const { pairing, host } = parts;
  const [copied, copy] = useCopied(host.copy);
  const step = pairing.step;
  const state = step.kind === 'paired' ? DONE : step.kind === 'failed' ? { kind: 'needs' as const, why: step.why } : WAITING;
  const trailing =
    step.kind === 'idle' || step.kind === 'paired' ? (
      <Button onClick={() => void pairing.pair()}>Pair</Button>
    ) : step.kind === 'failed' ? (
      <Button onClick={() => void pairing.pair()}>{ComputerLines.tryAgain}</Button>
    ) : step.kind === 'showing' ? (
      <Button onClick={() => void pairing.decline()}>Cancel</Button>
    ) : undefined;
  let extra = null;
  switch (step.kind) {
    case 'opening':
      extra = <Spinner />;
      break;
    case 'showing':
      extra = (
        <div className="flex items-center gap-4">
          <QrCode text={step.qr} size={PAIRING_QR.side} quiet={PAIRING_QR.quiet} radius={PAIRING_QR.radius} />
          <div className="flex flex-col items-start gap-2">
            <QuietLine>{ComputerLines.scan}</QuietLine>
            <Button icon={copied ? Check : Copy} onClick={() => copy(step.qr)}>
              {copied ? ComputerLines.copied : ComputerLines.copyLink}
            </Button>
          </div>
        </div>
      );
      break;
    case 'checking':
    case 'approving':
      extra = (
        <div className="flex flex-col items-start gap-1.5">
          <span className="text-footnote font-semibold text-foreground">{step.phone.name}</span>
          <Digits code={groupedDigits(step.phone.code)} />
          <QuietLine>{ComputerLines.sameDigits}</QuietLine>
          <div className="flex items-center gap-2 pt-1">
            <Button kind="primary" disabled={step.kind === 'approving'} onClick={() => void pairing.approve()}>
              {ComputerLines.approve}
            </Button>
            <Button disabled={step.kind === 'approving'} onClick={() => void pairing.decline()}>
              {ComputerLines.decline}
            </Button>
            {step.kind === 'approving' && <Spinner />}
          </div>
        </div>
      );
      break;
    case 'paired':
      extra = <p className="text-caption font-semibold text-green">{PairingLines.paired(step.name)}</p>;
      break;
    default:
      extra = null;
  }
  return (
    <SetupStep
      state={state}
      title={ComputerLines.pairPhone}
      detail={ComputerLines.pairPhoneDetail}
      trailing={trailing}
      extra={extra ?? undefined}
    />
  );
}

/** The pairing code as the Mac draws it: 148 square, 10 of quiet zone and a 10 corner. */
const PAIRING_QR = { side: 148, quiet: 10, radius: 10 } as const;

/** The Appearance page: Light, Dark or System as three pictures, and why the island stays dark. */
export function AppearancePage({ parts }: { parts: SettingsParts }) {
  const { preferences, host } = parts;
  usePreferences();
  const chosen = preferences.look;
  const pick = (look: Look) => {
    preferences.look = look;
    host.applyLook(look);
  };
  return (
    <div className="flex flex-col gap-2">
      <div className="flex gap-4 rounded-xl border border-panel-edge bg-card p-5">
        {LOOKS.map((look) => (
          <Pressable key={look} className="flex cursor-pointer flex-col items-center gap-2 transition-transform duration-200 ease-press active:scale-[0.94]" onClick={() => pick(look)} aria-pressed={look === chosen}>
            <span
              className={`block rounded-xl ${look === chosen ? 'shadow-settings-look-picked' : 'shadow-settings-look'}`}
            >
              <LookThumbnail look={look} />
            </span>
            <span className={`text-body ${look === chosen ? 'font-semibold text-sky' : 'text-ink-primary'}`}>{LOOK_NAMES[look]}</span>
          </Pressable>
        ))}
      </div>
      <p className="px-1 text-caption text-ink-secondary">{ISLAND_STAYS_DARK}</p>
      <div className="rounded-xl border border-panel-edge bg-card p-5">
        <IslandScreenPicker />
      </div>
    </div>
  );
}

/** A 136 by 92 picture of a window in the look; System draws dark whole and light over the upper left. */
function LookThumbnail({ look }: { look: Look }) {
  const page = (dark: boolean) => (
    <svg width={136} height={92} viewBox="0 0 136 92" className="absolute inset-0" aria-hidden>
      <rect width={136} height={92} fill={dark ? '#0B0B0C' : '#FFFFFF'} />
      <rect x={10} y={10} width={116} height={72} rx={8} fill={dark ? '#1C1C1E' : '#F4F4F6'} />
      <rect x={20} y={24} width={116 * 0.55} height={3} rx={1.5} fill={dark ? '#636366' : '#8E8E93'} />
      <rect x={20} y={33} width={116 * 0.35} height={3} rx={1.5} fill={dark ? '#636366' : '#8E8E93'} />
      <circle cx={110} cy={66} r={6} fill="#3B82F7" />
    </svg>
  );
  return (
    <span className="relative block h-settings-look-height w-settings-look-width overflow-hidden rounded-xl">
      {look === 'light' && page(false)}
      {look === 'dark' && page(true)}
      {look === 'system' && (
        <>
          {page(true)}
          <span className="absolute inset-0" style={{ clipPath: 'polygon(0 0, 100% 0, 0 100%)' }}>
            {page(false)}
          </span>
        </>
      )}
    </span>
  );
}
