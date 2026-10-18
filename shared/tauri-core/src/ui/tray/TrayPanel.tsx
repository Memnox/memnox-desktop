import type { CSSProperties, ReactNode } from 'react';
import { chipTooltip, listeningBadge, MENU_PANEL, MENU_SETTLE, menuRows, stripNote, type MenuAction, type MenuRow, type ToolChip } from '../../core/domain/menu-panel';
import { AgentMark, LogoMark, SFSymbol, ToolMark, type SFSymbolName } from '../kit';

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
      className="flex flex-col gap-2.5 rounded-[22px] p-3 font-sans text-ink"
      style={{
        width: MENU_PANEL.width,
        background: 'var(--mx-menu-wash)',
        backdropFilter: 'blur(30px) saturate(1.8)',
        boxShadow: 'inset 0 0 0 0.7px var(--mx-ink-edge-11), 0 12px 40px rgb(0 0 0 / 0.28)',
        animation: `fade-in ${MENU_PANEL.fadeMs}ms ease-out both`,
      }}
    >
      <header className="flex items-center gap-[11px] px-1 pt-1">
        <LogoMark size={24} className="text-ink" />
        <span className="font-display text-[21px] font-semibold leading-none text-ink">Memnox</span>
        <span className="flex-1" />
        <span className="flex min-w-0 items-center gap-1.5 rounded-full bg-[var(--mx-ink-07)] px-[9px] py-[5px]" title={badge.tooltip}>
          <span className={`size-1.5 rounded-full ${badge.lit ? 'bg-[#30d158]' : 'bg-[var(--mx-ink-30)]'}`} />
          <span className="truncate text-caption font-medium text-[var(--mx-ink-60)]">{badge.text}</span>
        </span>
      </header>

      <section className="flex flex-col gap-1.5" style={settle(0, opened)}>
        <div className="flex items-center px-1">
          <span className="p-1 text-micro font-semibold uppercase tracking-[0.5px] text-[var(--mx-ink-60)]">Connected</span>
          <span className="flex-1" />
          <button type="button" className="cursor-pointer p-1 text-micro font-semibold text-primary" onClick={() => onAction('tools')}>
            Manage
          </button>
        </div>
        <MenuCard className="h-[52px]">
          {note !== undefined ? (
            <p className="m-0 line-clamp-2 p-2.5 text-micro leading-[13px] text-[var(--mx-ink-60)]">{note}</p>
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
          {menuRows(state.muted, state.talkKeys).map((row) => (
            <div key={row.action} className="contents">
              {row.dividerAbove === true && <hr className="my-0.5 ml-[41px] mr-0 h-px border-0 bg-[var(--mx-ink-faint-05)]" />}
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
    <div className={`rounded-[10px] bg-[var(--mx-menu-card)] ${className ?? ''}`} style={{ boxShadow: 'inset 0 0 0 0.7px var(--mx-ink-edge-11)' }}>
      {children}
    </div>
  );
}

/** One agent or app: a 26 mark with its status dot, and its name 10 medium under it, 58 wide. */
function Chip({ chip, online, onPress }: { chip: ToolChip; online: boolean; onPress: () => void }) {
  return (
    <button type="button" className="flex w-[58px] shrink-0 cursor-pointer flex-col items-center gap-1 p-1 transition-[scale] duration-[220ms] active:scale-[0.97]" onClick={onPress} title={chipTooltip(chip)}>
      <span className="relative">
        {chip.kind === 'agent' ? <AgentMark agent={chip.key} name={chip.name} size={26} /> : <ToolMark toolkit={chip.key} size={26} online={online} />}
        <span className={`absolute -bottom-px -right-px size-1.5 rounded-full ${chip.ready ? 'bg-success' : 'bg-warm'}`} style={{ boxShadow: '0 0 0 0.5px rgb(0 0 0 / 0.4)' }} />
      </span>
      <span className="w-full truncate text-center text-micro font-medium text-ink">{chip.name}</span>
    </button>
  );
}

/** A keycap at the end of a row: 11 medium on a rounded key at least 18 square. */
function Keycap({ label }: { label: string }) {
  return <span className="grid h-[18px] min-w-[18px] place-items-center rounded-key bg-keycap px-1.5 text-caption font-medium text-foreground shadow-[inset_0_0_0_1px_var(--mx-control-edge)]">{label}</span>;
}

/** `MenuRow`: 32 tall, 10 by 11, its symbol 13 in an 18 column, ink 7% under the pointer at radius 11. */
function Row({ row, onPress }: { row: MenuRow; onPress: () => void }) {
  const quiet = row.quiet === true;
  return (
    <button
      type="button"
      className="flex h-8 w-full cursor-pointer items-center gap-[11px] rounded-[11px] px-2.5 text-left transition-[background-color,scale] duration-[120ms] ease-out hover:bg-[var(--mx-ink-07)] active:scale-[0.97]"
      onClick={onPress}
      title={row.tooltip}
    >
      <span className={`grid w-[18px] shrink-0 place-items-center ${quiet ? 'text-[var(--mx-ink-40)]' : 'text-[var(--mx-ink-60)]'}`}>
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
    </button>
  );
}
