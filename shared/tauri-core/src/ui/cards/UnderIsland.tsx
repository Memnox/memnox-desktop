import { useSyncExternalStore } from 'react';
import type { ToolSignIn } from '@memnox/core/wire';
import type { IslandNotices, SignedInPill as SignedIn } from '../../core/application/island-notices';
import { driveLabel, phoneVoiceLabel } from '../../core/domain/driving';
import { signedInWords, signInLabel, signInLead } from '../../core/domain/tool-brand';
import { IslandButton, PRESSABLE, SFSymbol, ToolMark } from '../kit';

/**
 * What hangs 6 under the island in every mode, from the Mac's `IslandView`: a phone driving this
 * computer, the signed in pill, the sign in row, and a phone holding the voice, in that order.
 */
export function UnderIsland({
  notices,
  onSignIn,
  onNotMe,
  online = true,
}: {
  notices: IslandNotices;
  /** Opens a tool's sign in in the browser; its icon goes once tapped. */
  onSignIn: (tool: ToolSignIn) => void;
  /** Not me: a fresh sign in with the person's own account. */
  onNotMe: (pill: SignedIn) => void;
  /** Whether the Composio logos may be fetched. */
  online?: boolean;
}) {
  const state = useSyncExternalStore(
    (changed) => notices.observe(changed),
    () => notices.state,
  );
  return (
    <>
      {state.driving !== undefined && <PhonePill label={driveLabel(state.driving)} symbol="iphone.radiowaves.left.and.right" />}
      {state.signedIn !== undefined && <SignedInPill pill={state.signedIn} onNotMe={() => onNotMe(state.signedIn as SignedIn)} online={online} />}
      {state.signIns.length > 0 && <SignInRow tools={state.signIns} onSignIn={onSignIn} online={online} />}
      {state.phoneVoice !== undefined && <PhonePill label={phoneVoiceLabel(state.phoneVoice)} symbol="iphone" />}
    </>
  );
}

/**
 * `IslandPhonePill`: a black capsule with an amber 50% rim, 12 by 5, an amber phone 11 semibold and the
 * words 11 medium white, for as long as a phone drives this computer or holds its voice. It takes no click.
 */
export function PhonePill({ label, symbol }: { label: string; symbol: 'iphone' | 'iphone.radiowaves.left.and.right' }) {
  return (
    <div className="pointer-events-none inline-flex max-w-full animate-pill-in items-center gap-1 rounded-full bg-black px-3 py-[5px]" style={{ boxShadow: 'inset 0 0 0 1px rgb(255 159 10 / 0.5)' }} role="status">
      <span className="grid shrink-0 text-amber">
        <SFSymbol name={symbol} size={11} weight="semibold" />
      </span>
      <span className="truncate text-caption font-medium text-white">{label}</span>
    </div>
  );
}

/**
 * `IslandSignInRow`: "Sign in to use" and one tool mark per tool not signed in to, each a 30 hit area
 * around a 22 mark, one tap opening its sign in. A tool to sign in to again wears an amber badge.
 */
export function SignInRow({ tools, onSignIn, online = true }: { tools: readonly ToolSignIn[]; onSignIn: (tool: ToolSignIn) => void; online?: boolean }) {
  return (
    <div className="inline-flex animate-pill-in items-center gap-1 rounded-full bg-black px-2.5 py-[3px]" style={{ boxShadow: 'inset 0 0 0 1px rgb(255 255 255 / 0.14)' }}>
      <span className="pr-1 text-caption font-medium text-white/[0.62]">{signInLead(tools.map((tool) => tool.again === true))}</span>
      {tools.map((tool) => (
        <button
          key={tool.toolkit}
          type="button"
          className={`${PRESSABLE} relative grid size-[30px] place-items-center`}
          onClick={() => onSignIn(tool)}
          title={signInLabel(tool.toolkit, tool.again === true)}
          aria-label={signInLabel(tool.toolkit, tool.again === true)}
        >
          <ToolMark toolkit={tool.toolkit} size={22} online={online} />
          {tool.again === true && (
            <span className="absolute grid size-[11px] place-items-center rounded-full bg-amber text-black" style={{ right: 4 - 11 / 3, bottom: 4 - 11 / 3 }}>
              <SFSymbol name="arrow.triangle.2.circlepath" size={6.6} weight="bold" />
            </span>
          )}
        </button>
      ))}
    </div>
  );
}

/**
 * `IslandSignedInPill`: the tool, whose account the sign in reached, and a green seal where the
 * workspace knows it is theirs, or Not me where nothing ties it to them yet. 12 by 6, black, white 14% rim.
 */
export function SignedInPill({ pill, onNotMe, online = true }: { pill: SignedIn; onNotMe: () => void; online?: boolean }) {
  return (
    <div
      className="inline-flex max-w-full animate-pill-in items-center gap-1.5 rounded-full bg-black px-3 py-1.5"
      style={{ boxShadow: 'inset 0 0 0 1px rgb(255 255 255 / 0.14)' }}
      role="status"
      aria-label={pill.who === undefined ? `Signed in to ${pill.toolkit}` : `Signed in to ${pill.toolkit} as ${pill.who}`}
    >
      <ToolMark toolkit={pill.toolkit} size={18} online={online} />
      <span className="truncate text-caption font-semibold text-white">{signedInWords(pill.toolkit, pill.who)}</span>
      {pill.unverified ? (
        <IslandButton onClick={onNotMe} title="Sign in again with your own account">
          Not me
        </IslandButton>
      ) : (
        <span className="grid text-green" aria-label="your account">
          <SFSymbol name="checkmark.seal.fill" size={11} />
        </span>
      )}
    </div>
  );
}
