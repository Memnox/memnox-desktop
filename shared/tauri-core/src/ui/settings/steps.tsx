import { MousePointer2, Settings as Gear } from 'lucide-react';
import { useMemo, type ReactNode } from 'react';
import { qrModules, qrPath } from '../../core/domain/qr';
import type { StepState } from '../../core/domain/step-state';
import { NeedsHint, StatusMark } from './kit';
import { Button } from '../kit';
import { SettingsKitLines } from '../../core/domain/settings-kit-lines';

/**
 * `SetupStep` from `Setup.swift`: the mark at the left, the title 13 over its detail 10 muted, the control at
 * the end, then whatever extra the step holds and the needs hint. A step with a tile centres on it and moves
 * the mark to the end, shown only once done.
 */
export function SetupStep({
  state,
  title,
  detail,
  tile,
  trailing,
  extra,
  hint,
}: {
  state: StepState;
  title: string;
  detail: string;
  tile?: ReactNode;
  trailing?: ReactNode;
  extra?: ReactNode;
  hint?: boolean;
}) {
  const showsHint = hint !== false && state.kind === 'needs';
  return (
    <div className="flex flex-col gap-2.5 px-4 py-3">
      <div className={`flex gap-3 ${tile === undefined ? 'items-start' : 'items-center'}`}>
        {tile === undefined ? (
          <span className="mt-px">
            <StatusMark state={state} />
          </span>
        ) : (
          tile
        )}
        <div className="flex min-w-0 flex-1 flex-col gap-settings-step-line">
          <span className="text-body text-foreground">{title}</span>
          <span className="text-micro text-muted">{detail}</span>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {trailing}
          {tile !== undefined && state.kind === 'done' && <StatusMark state={state} />}
        </div>
      </div>
      {extra !== undefined && <div className={tile === undefined ? 'pl-8' : 'pl-settings-row-text'}>{extra}</div>}
      {showsHint && state.kind === 'needs' && (
        <div className={tile === undefined ? 'pl-8' : 'pl-settings-row-text'}>
          <NeedsHint why={state.why} />
        </div>
      )}
    </div>
  );
}

/** The divider between setup steps: ink 6%, indented 44 so it starts under the titles. */
export function SetupDivider() {
  return <div className="ml-11 h-px bg-ink-faint-fill" />;
}

/**
 * `PermissionGuide`: the steps to take in the system's settings, a picture of the switch to flip with a
 * pointer flipping it, then Open settings and the step's own buttons.
 */
export function PermissionGuide({
  steps,
  pane,
  switchName,
  settingsApp,
  open,
  children,
}: {
  steps: readonly string[];
  pane: string | undefined;
  switchName: string | undefined;
  settingsApp: string;
  open?: () => void;
  children?: ReactNode;
}) {
  return (
    <div className="flex w-full flex-col gap-3 rounded-xl border border-ink-edge bg-ink-faint-fill p-4">
      <ol className="flex flex-col gap-2">
        {steps.map((step, index) => (
          <li key={step} className="flex items-start gap-2">
            <span className="grid size-settings-guide-number shrink-0 place-items-center rounded-full bg-ink-edge text-micro font-semibold text-ink">{index + 1}</span>
            <span className="select-text text-footnote text-ink-primary">{step}</span>
          </li>
        ))}
      </ol>
      {switchName !== undefined && pane !== undefined && <SwitchPicture pane={pane} switchName={switchName} />}
      <div className="flex flex-wrap gap-2">
        {open !== undefined && (
          <Button icon={Gear} onClick={open}>
            Open {settingsApp}
          </Button>
        )}
        {children}
      </div>
    </div>
  );
}

/** `GuideLayout.barWidths`: the two other apps' name bars, of different lengths so they read as names. */
const GUIDE_BAR_WIDTHS = [84, 110] as const;
/** `GuideLayout.pointerSize`, the pointer drawn bold. */
const GUIDE_POINTER = 16;
const GUIDE_POINTER_STROKE = 2.5;

/** The picture of the pane: two greyed rows and the switch for Memnox, flipped off and on by a pointer. */
function SwitchPicture({ pane, switchName }: { pane: string; switchName: string }) {
  return (
    <div className="relative h-settings-guide-height w-settings-guide-width overflow-hidden rounded-settings-guide border border-ink-edge bg-raised" aria-hidden>
      <div className="flex h-settings-guide-header items-center px-3 text-caption font-semibold text-ink-primary">{pane}</div>
      {GUIDE_BAR_WIDTHS.map((width) => (
        <div key={width} className="flex h-settings-guide-row items-center gap-1.5 px-3">
          <span className="size-settings-guide-tile rounded-settings-guide-tile bg-ink-fill" />
          <span className="h-2 rounded-full bg-ink-fill" style={{ width }} />
          <span className="ml-auto h-settings-guide-switch-height w-settings-guide-switch-width rounded-full bg-primary opacity-35" />
        </div>
      ))}
      <div className="flex h-settings-guide-row items-center gap-1.5 bg-primary/[0.08] px-3">
        <span className="size-settings-guide-tile rounded-settings-guide-tile bg-primary" />
        <span className="truncate text-footnote font-medium text-ink">{switchName}</span>
        <span className="relative ml-auto h-settings-guide-switch-height w-settings-guide-switch-width shrink-0 animate-[guide-switch_5.6s_infinite] rounded-full">
          <span className="absolute top-0.5 left-0.5 size-settings-guide-knob animate-[guide-knob_5.6s_infinite] rounded-full bg-white" />
        </span>
      </div>
      <span className="absolute top-0 left-0 animate-[guide-pointer_5.6s_infinite] text-white drop-shadow-settings-pointer">
        <MousePointer2 size={GUIDE_POINTER} strokeWidth={GUIDE_POINTER_STROKE} fill="white" />
      </span>
    </div>
  );
}

/** A QR on a white rounded square with its quiet zone, drawn from the core's own encoder. */
export function QrCode({ text, size, quiet, radius }: { text: string; size: number; quiet: number; radius: number }) {
  const modules = useMemo(() => qrModules(text, 'M'), [text]);
  const path = useMemo(() => qrPath(modules), [modules]);
  return (
    <span className="inline-block shrink-0 bg-white" style={{ padding: quiet, borderRadius: radius }}>
      <svg width={size} height={size} viewBox={`0 0 ${modules.length} ${modules.length}`} shapeRendering="crispEdges" role="img" aria-label={SettingsKitLines.pairingCode}>
        <path d={path} fill="#000" />
      </svg>
    </span>
  );
}
