import { Check, Copy, Fingerprint, MousePointerClick, RotateCw, Smartphone } from 'lucide-react';
import { Fragment, useEffect } from 'react';
import { groupedDigits } from '../../../core/domain/account-whole';
import { ISLAND_STAYS_DARK, LOOK_NAMES, LOOKS, type Look } from '../../../core/domain/appearance';
import { deviceCaption, drives, PairingLines } from '../../../core/domain/pairing-lines';
import type { PermissionStep } from '../../../core/domain/permission-steps';
import { DONE, WAITING } from '../../../core/domain/step-state';
import { Digits, IconTile, KitButton, MemnoxTile, QuietLine, SettingsCard, SettingsDivider, SettingsRow, Spinner, Surface, SwitchRow, useCopied } from '../kit';
import { useObserved, usePreferences, type SettingsParts } from '../parts';
import { PermissionGuide, QrCode, SetupDivider, SetupStep } from '../steps';

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
          <KitButton kind="primary" onClick={() => void steps.readPermissions()}>
            Allow
          </KitButton>
        ) : undefined
      }
      extra={
        step.state.kind === 'needs' && step.guide.length > 0 ? (
          <PermissionGuide steps={step.guide} pane={pane === 'microphone' ? 'Microphone' : undefined} switchName={step.switchName} settingsApp={words.settingsApp} open={open}>
            <KitButton icon={RotateCw} onClick={() => void steps.readPermissions()}>
              Check again
            </KitButton>
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
      title="Start when you sign in"
      detail="So a call that waits on you is never missed because Memnox was closed."
      trailing={
        on ? (
          <KitButton onClick={() => void steps.setStartsAtSignIn(false)}>Turn off</KitButton>
        ) : (
          <KitButton kind="primary" onClick={() => void steps.setStartsAtSignIn(true)}>
            Turn on
          </KitButton>
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
    </Surface>
  );
}

export function ServiceRow({ parts }: { parts: SettingsParts }) {
  const { steps } = parts;
  const service = steps.service;
  const working = parts.setup.state.doing !== undefined;
  return (
    <SetupStep
      state={service.state}
      title="Memnox service"
      detail={service.detail}
      tile={<MemnoxTile />}
      trailing={service.state.kind === 'done' ? undefined : working ? <Spinner /> : <KitButton onClick={() => void steps.checkService()}>Check again</KitButton>}
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
      trailing={state.kind === 'done' ? undefined : <KitButton onClick={() => void steps.checkKey()}>Check again</KitButton>}
    />
  );
}

/** The Phones page: pair a phone with a QR and matching digits, then each phone paired with Revoke and driving. */
export function PhonesPage({ parts }: { parts: SettingsParts }) {
  const { pairing } = parts;
  useObserved(pairing);
  useEffect(() => void pairing.loadDevices(), []);
  return (
    <>
      <Surface>
        <PairRow parts={parts} />
      </Surface>
      {pairing.devices.length > 0 && (
        <SettingsCard title="Paired phones">
          {pairing.devices.map((device, index) => (
            <Fragment key={device.id}>
              {index > 0 && <SettingsDivider full />}
              <SettingsRow icon={Smartphone} title={device.name} caption={deviceCaption(device)}>
                <KitButton onClick={() => void pairing.revoke(device)}>Revoke</KitButton>
              </SettingsRow>
              <SwitchRow
                icon={MousePointerClick}
                title="Let it drive this computer"
                caption={drives(device) ? 'Turn off to stop it' : `${parts.words.keyTitle} to turn on`}
                on={drives(device)}
                onChange={(on) => void pairing.letDrive(device, on)}
              />
            </Fragment>
          ))}
        </SettingsCard>
      )}
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
      <KitButton onClick={() => void pairing.pair()}>Pair</KitButton>
    ) : step.kind === 'failed' ? (
      <KitButton onClick={() => void pairing.pair()}>Try again</KitButton>
    ) : step.kind === 'showing' ? (
      <KitButton onClick={() => void pairing.decline()}>Cancel</KitButton>
    ) : undefined;
  let extra = null;
  switch (step.kind) {
    case 'opening':
      extra = <Spinner />;
      break;
    case 'showing':
      extra = (
        <div className="flex items-center gap-4">
          <QrCode text={step.qr} size={148} quiet={10} radius={10} />
          <div className="flex flex-col items-start gap-2">
            <QuietLine>Scan this with the Memnox app on your iPhone.</QuietLine>
            <KitButton icon={copied ? Check : Copy} onClick={() => copy(step.qr)}>
              {copied ? 'Copied' : 'Copy link'}
            </KitButton>
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
          <QuietLine>Approve if your iPhone shows the same digits.</QuietLine>
          <div className="flex items-center gap-2 pt-1">
            <KitButton kind="primary" disabled={step.kind === 'approving'} onClick={() => void pairing.approve()}>
              Approve
            </KitButton>
            <KitButton disabled={step.kind === 'approving'} onClick={() => void pairing.decline()}>
              Decline
            </KitButton>
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
      title="Pair a phone"
      detail="Optional. Answer your agents and talk to Memnox from your iPhone."
      trailing={trailing}
      extra={extra ?? undefined}
    />
  );
}

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
      <div className="flex gap-4 rounded-2xl bg-card p-4">
        {LOOKS.map((look) => (
          <button key={look} type="button" className="flex cursor-pointer flex-col items-center gap-2 transition-transform duration-200 ease-press active:scale-[0.94]" onClick={() => pick(look)} aria-pressed={look === chosen}>
            <span
              className="block rounded-xl"
              style={{ boxShadow: look === chosen ? '0 0 0 2px var(--color-primary)' : '0 0 0 1px var(--mx-ink-edge)' }}
            >
              <LookThumbnail look={look} />
            </span>
            <span className={`text-body ${look === chosen ? 'font-semibold text-sky' : 'text-ink-primary'}`}>{LOOK_NAMES[look]}</span>
          </button>
        ))}
      </div>
      <p className="px-1 text-caption text-ink-secondary">{ISLAND_STAYS_DARK}</p>
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
    <span className="relative block h-[92px] w-[136px] overflow-hidden rounded-xl">
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
