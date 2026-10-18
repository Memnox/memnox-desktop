import { MousePointer2, Settings as Gear } from 'lucide-react';
import { useMemo, type ReactNode } from 'react';
import { qrModules, qrPath } from '../../core/domain/qr';
import type { StepState } from '../../core/domain/step-state';
import { KitButton, NeedsHint, StatusMark } from './kit';

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
        <div className="flex min-w-0 flex-1 flex-col gap-[3px]">
          <span className="text-body text-foreground">{title}</span>
          <span className="text-micro text-muted">{detail}</span>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {trailing}
          {tile !== undefined && state.kind === 'done' && <StatusMark state={state} />}
        </div>
      </div>
      {extra !== undefined && <div className={tile === undefined ? 'pl-8' : 'pl-[38px]'}>{extra}</div>}
      {showsHint && state.kind === 'needs' && (
        <div className={tile === undefined ? 'pl-8' : 'pl-[38px]'}>
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
            <span className="grid size-[18px] shrink-0 place-items-center rounded-full bg-ink-edge text-micro font-semibold text-ink">{index + 1}</span>
            <span className="select-text text-footnote text-ink-primary">{step}</span>
          </li>
        ))}
      </ol>
      {switchName !== undefined && pane !== undefined && <SwitchPicture pane={pane} switchName={switchName} />}
      <div className="flex flex-wrap gap-2">
        {open !== undefined && (
          <KitButton icon={Gear} onClick={open}>
            Open {settingsApp}
          </KitButton>
        )}
        {children}
      </div>
    </div>
  );
}

/** The picture of the pane: two greyed rows and the switch for Memnox, flipped off and on by a pointer. */
function SwitchPicture({ pane, switchName }: { pane: string; switchName: string }) {
  return (
    <div className="relative h-[116px] w-[300px] overflow-hidden rounded-[10px] border border-ink-edge bg-raised" aria-hidden>
      <div className="flex h-[26px] items-center px-3 text-caption font-semibold text-ink-primary">{pane}</div>
      {[84, 110].map((width) => (
        <div key={width} className="flex h-[30px] items-center gap-2 px-3">
          <span className="size-[18px] rounded-[5px] bg-ink-fill" />
          <span className="h-2 rounded-full bg-ink-fill" style={{ width }} />
          <span className="ml-auto h-[17px] w-[30px] rounded-full bg-primary opacity-35" />
        </div>
      ))}
      <div className="flex h-[30px] items-center gap-2 bg-primary/[0.08] px-3">
        <span className="size-[18px] rounded-[5px] bg-primary" />
        <span className="truncate text-footnote font-medium text-ink">{switchName}</span>
        <span className="relative ml-auto h-[17px] w-[30px] shrink-0 animate-[guide-switch_5.6s_infinite] rounded-full">
          <span className="absolute top-0.5 left-0.5 size-[13px] animate-[guide-knob_5.6s_infinite] rounded-full bg-white shadow-[0_1px_1px_rgba(0,0,0,.25)]" />
        </span>
      </div>
      <span className="absolute top-0 left-0 animate-[guide-pointer_5.6s_infinite] text-white [filter:drop-shadow(0_0_0.8px_rgba(0,0,0,.9))]">
        <MousePointer2 size={16} strokeWidth={2.5} fill="white" />
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
      <svg width={size} height={size} viewBox={`0 0 ${modules.length} ${modules.length}`} shapeRendering="crispEdges" role="img" aria-label="Pairing code">
        <path d={path} fill="#000" />
      </svg>
    </span>
  );
}
