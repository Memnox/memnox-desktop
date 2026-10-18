import type { CSSProperties } from 'react';
import { toolAsks, toolkitName, toolLook, toolPageHint } from '../../core/domain/tool-brand';
import { notchPress, SFSymbol, ToolMark } from '../kit';

/** How the talk key reads on Windows and Linux, where Option Space is Control Alt Space. */
export const TALK_KEY = 'Ctrl Alt Space';

/**
 * `NotchArrival`: each part rises 10 and grows from 0.92 on spring(0.38, 0.78), the grid waiting 0.08 s
 * for the island to open and each part 0.025 s after the one before it.
 */
export function arrival(order: number): CSSProperties {
  return { animation: `tile-in 400ms cubic-bezier(0.3, 1.3, 0.6, 1) ${80 + order * 25}ms both` };
}

/**
 * `IslandToolPage`: one connected app up close in the launcher, 512 by 230. On the left its mark lit by a
 * breathing halo of its own colour, its name and how it stands; on the right three things to ask about
 * it, each a tap that goes whole to ask as if it were said, and a line that anything else is a sentence away.
 */
export function ToolPage({ toolkit, connected, onAsk, online = true, talkKey = TALK_KEY }: { toolkit: string; connected: boolean; onAsk: (words: string) => void; online?: boolean; talkKey?: string }) {
  const name = toolkitName(toolkit);
  const tint = toolLook(toolkit).colour;
  return (
    <div className="flex size-full items-center gap-3.5">
      <div className="flex w-[132px] shrink-0 flex-col items-center gap-1.5">
        <div className="relative grid h-[62px] w-full place-items-center" style={arrival(0)}>
          <span className="pointer-events-none absolute left-1/2 top-1/2 size-[104px] -translate-x-1/2 -translate-y-1/2 animate-halo rounded-full blur-[22px]" style={{ backgroundColor: tint }} aria-hidden />
          <span className="relative rounded-[14px] shadow-[0_4px_16px_rgb(0_0_0/0.4)]">
            <ToolMark toolkit={toolkit} size={54} online={online} />
          </span>
        </div>
        <span className="max-w-full truncate text-headline font-semibold text-white">{name}</span>
        <span className="flex items-center gap-1">
          <span className={`size-1.5 rounded-full ${connected ? 'bg-green' : 'bg-amber'}`} aria-hidden />
          <span className="font-rounded text-caption font-medium text-white/60">{connected ? 'Connected' : 'Needs a sign in'}</span>
        </span>
      </div>
      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
        <span className="font-rounded text-micro font-semibold tracking-[0.6px] text-white/60" style={arrival(0)}>
          ASK MEMNOX
        </span>
        {toolAsks(toolkit).map((words, index) => (
          <button
            key={words}
            type="button"
            className={`${notchPress(true)} flex h-9 w-full items-center gap-1.5 rounded-[11px] bg-white/[0.045] px-2 text-left`}
            style={{ ...arrival(index + 1), boxShadow: 'inset 0 0 0 1px rgb(255 255 255 / 0.04)' }}
            onClick={() => onAsk(words)}
            title={`Ask “${words}”`}
            aria-label={`Ask Memnox: ${words}`}
          >
            <span className="min-w-0 flex-1 truncate text-footnote font-medium text-white">{words}</span>
            <span className="grid text-white/85">
              <SFSymbol name="arrow.up.right" size={11} weight="semibold" />
            </span>
          </button>
        ))}
        <span className="flex min-w-0 items-center gap-1 pt-1 text-micro font-medium" style={arrival(4)}>
          <span className="grid shrink-0 text-island-sky">
            <SFSymbol name="waveform" size={10} />
          </span>
          <span className="truncate text-white/60">{toolPageHint(toolkit, connected, talkKey)}</span>
        </span>
      </div>
    </div>
  );
}
