import type { CSSProperties, ReactNode } from 'react';
import { chipLabel, chipTooltip, listeningBadge, MENU_PANEL, MENU_WORDS, MENU_SETTLE, menuRows, stripNote, type MenuAction, type MenuRow, type ToolChip } from '../../core/domain/menu-panel';
import { demoOn } from '../adapters/demo';
import { AgentMark, LogoMark, Pressable, SFSymbol, type SFSymbolName, ToolMark } from '../kit';

/** What the panel draws, gathered by its window from the island and the daemon. */
export interface TrayPanelState {
  readonly muted: boolean;
  readonly wakesByName: boolean;
  readonly talkKeys: readonly string[];
  readonly chips: readonly ToolChip[];
  readonly reading: boolean;
  readonly failed: string | undefined;
}

/** Each section rises 6 into place a beat after the one before, every time the panel opens. */
function settle(order: number, opened: number): CSSProperties {
  return { animation: `settle-in ${MENU_SETTLE.durationMs}ms cubic-bezier(0.2, 0.8, 0.2, 1) ${order * MENU_SETTLE.stepMs}ms both`, ['--opened' as string]: opened };
}

/**
 * The tray's own panel, the web twin of the Mac's menu bar `MenuView`: 300 wide, 12 padding, radius 22
 * glass with a dark or light wash; the header with the listening badge, the strip of connected agents
 * and apps, then the rows. `opened` changes each time the panel opens, so the sections settle again.
 */
export function TrayPanel({ state, opened, onAction, online = true }: { state: TrayPanelState; opened: number; onAction: (action: MenuAction) => void; online?: boolean }) {
  const badge = listeningBadge(state.wakesByName, state.talkKeys);
  const note = stripNote(state.reading, state.failed, state.chips);
  return (
    <div
      key={opened}
      className="mx-tray-panel flex flex-col gap-2.5 rounded-tray-panel bg-(--mx-menu-wash) p-3 font-sans text-ink shadow-tray-panel backdrop-blur-tray-panel backdrop-saturate-180"
      style={{ width: MENU_PANEL.width, animation: `fade-in ${MENU_PANEL.fadeMs}ms ease-out both` }}
    >
      <header className="flex items-center gap-tray-icon-gap px-1 pt-1">
        <LogoMark size={24} className="text-ink" />
        <span className="font-display text-tray-title font-semibold leading-none text-ink">{MENU_WORDS.title}</span>
        <span className="flex-1" />
        <span className="flex min-w-0 items-center gap-1.5 rounded-full bg-[var(--mx-ink-07)] px-tray-badge-x py-tray-badge-y" title={badge.tooltip} role="status" aria-label={badge.tooltip}>
          <span className={`size-1.5 rounded-full ${badge.lit ? 'bg-green' : 'bg-[var(--mx-ink-30)]'}`} />
          <span className="truncate text-caption font-medium text-[var(--mx-ink-60)]">{badge.text}</span>
        </span>
      </header>

      <section className="flex flex-col gap-1.5" style={settle(0, opened)}>
        <div className="flex items-center px-1">
          <span role="heading" aria-level={2} className="px-1 text-micro font-semibold uppercase tracking-tray-heading text-[var(--mx-ink-60)]">
            {MENU_WORDS.connected}
          </span>
          <span className="flex-1" />
          <Pressable className="cursor-pointer text-micro font-semibold text-primary" onClick={() => onAction('tools')}>
            {MENU_WORDS.manage}
          </Pressable>
        </div>
        <MenuCard className="h-tray-strip">
          {note !== undefined ? (
            <div className="flex h-full items-center px-2.5">
              <p className="m-0 line-clamp-2 text-micro leading-tray-note text-[var(--mx-ink-60)]">{note}</p>
            </div>
          ) : (
            <div className="flex h-full items-center overflow-x-auto px-1 [scrollbar-width:none]">
              {state.chips.map((chip) => (
                <Chip key={chip.id} chip={chip} online={online} onPress={() => onAction('tools')} />
              ))}
            </div>
          )}
        </MenuCard>
      </section>

      <section style={settle(1, opened)}>
        <MenuCard className="flex flex-col gap-0.5 p-1">
          {menuRows(state.muted, state.talkKeys, demoOn).map((row) => (
            <div key={row.action} className="contents">
              {row.dividerAbove === true && <hr className="my-0.5 ml-tray-divider-indent mr-0 h-px border-0 bg-[var(--mx-ink-faint-05)]" />}
              <Row row={row} onPress={() => onAction(row.action)} />
            </div>
          ))}
        </MenuCard>
      </section>
    </div>
  );
}

/** A menu card: radius 10, white 7.5% on dark or 38% on light, with the 0.7 rim. */
function MenuCard({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div className={`rounded-tray-card bg-[var(--mx-menu-card)] shadow-tray-rim ${className ?? ''}`}>
      {children}
    </div>
  );
}

/** One agent or app: a 26 mark with its status dot in its corner, and its name 10 medium 4 under it, 58 wide. */
function Chip({ chip, online, onPress }: { chip: ToolChip; online: boolean; onPress: () => void }) {
  return (
    <Pressable className="flex w-tray-chip shrink-0 cursor-pointer flex-col items-center gap-1 transition-[scale] duration-[220ms] active:scale-[0.97]" onClick={onPress} title={chipTooltip(chip)} aria-label={chipLabel(chip)}>
      <span className="relative">
        {chip.kind === 'agent' ? <AgentMark agent={chip.key} name={chip.name} size={26} /> : <ToolMark toolkit={chip.key} size={26} online={online} />}
        <span className={`absolute right-0 bottom-0 size-1.5 rounded-full ${chip.ready ? 'bg-success' : 'bg-warm'} shadow-tray-dot`} />
      </span>
      <span className="w-full truncate text-center text-micro font-medium text-ink">{chip.name}</span>
    </Pressable>
  );
}

/** A keycap at the end of a row: 11 medium on a rounded key at least 18 square. */
function Keycap({ label }: { label: string }) {
  return <span className="grid h-tray-keycap min-w-tray-keycap place-items-center rounded-key border border-control-edge bg-keycap px-1.5 text-caption font-medium text-foreground">{label}</span>;
}

/** `MenuRow`: 32 tall, 10 by 11, its symbol 13 in an 18 column, ink 7% under the pointer at radius 11. */
function Row({ row, onPress }: { row: MenuRow; onPress: () => void }) {
  const quiet = row.quiet === true;
  return (
    <Pressable
      className="flex h-8 w-full cursor-pointer items-center gap-tray-icon-gap rounded-tray-row px-2.5 text-left transition-[background-color,scale] duration-[120ms] ease-out hover:bg-[var(--mx-ink-07)] active:scale-[0.97]"
      onClick={onPress}
      title={row.tooltip}
    >
      <span className={`grid w-tray-icon-column shrink-0 place-items-center ${quiet ? 'text-[var(--mx-ink-40)]' : 'text-[var(--mx-ink-60)]'}`}>
        <SFSymbol name={row.symbol as SFSymbolName} size={13} weight="medium" />
      </span>
      <span className={`flex-1 truncate text-body font-medium ${quiet ? 'text-ink-secondary' : 'text-[var(--mx-ink-90)]'}`}>{row.title}</span>
      {row.keys !== undefined && (
        <span className="flex items-center gap-0.5">
          {row.keys.map((key) => (
            <Keycap key={key} label={key} />
          ))}
        </span>
      )}
    </Pressable>
  );
}
