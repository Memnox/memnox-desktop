import { useState, type ReactNode } from 'react';
import { invoke } from '@tauri-apps/api/core';
import type { WorkDraft } from '@memnox/core/wire';
import { typedAddresses, type HeldOutcome, type ProposalCards } from '../../core';
import { avatarLetter, shownPeople, toolkitName, toolLook, workFootnote, workLayout, workTitle } from '../../core/domain/tool-brand';
import { ANSWERING_ROW, Input, IslandCard, PRESSABLE, Pressable, SFSymbol, Textarea, ToolMark } from '../kit';
import { SYSTEM_MONO } from './MarkdownText';
import { TAURI_COMMAND } from '../adapters/tauri-commands';
import { HeldLines, WorkCardLines } from '../../core/domain/island-lines';

/** What the work card says while the key is up; Windows Hello and polkit both read as a fingerprint here. */
const KEY_NAME = 'your fingerprint';

/** The 1 px white 7% line between the header and the content, and inside a comment box. */
function Rule() {
  return <hr className="m-0 h-px w-full shrink-0 border-0 bg-white/[0.07]" />;
}

/**
 * `IslandWorkCard`: something about to go out in the person's name, laid out the way its own tool lays
 * it out: a Slack message under their name, a GitHub or Linear comment box, a mail with its subject, or
 * any other action with its title. It names the account, shows every argument, and keeps the words in a
 * box ready to change; Send signs exactly what goes, and closing it goes unsigned.
 */
export function WorkCard({
  subject,
  work,
  cards,
  onAnswered,
  className,
}: {
  subject: string;
  work: WorkDraft;
  cards: ProposalCards;
  onAnswered: (outcome: HeldOutcome, sent: boolean) => void;
  className?: string;
}) {
  const drafted = work.body ?? '';
  const [words, setWords] = useState(drafted);
  const [sending, setSending] = useState(false);
  const [said, setSaid] = useState<string>();
  const look = toolLook(work.toolkit);
  const tool = toolkitName(work.toolkit);
  const empty = work.body !== undefined && words.trim() === '';
  const changed = work.body !== undefined && words !== drafted;
  const proposedTo = work.to ?? [];
  const [toText, setToText] = useState(proposedTo.join(', '));
  const readdressable = work.toEditable === true;
  const addresses = typedAddresses(toText);
  const badAddress = readdressable && addresses === undefined;
  const readdressed = readdressable && addresses !== undefined && addresses.join(',') !== proposedTo.join(',');
  const footnote = workFootnote({ sending, empty, changed, badAddress, readdressed }, KEY_NAME);
  const shown = work.account?.handle ?? work.account?.name;

  async function answer(send: boolean) {
    setSending(send);
    // Words go with the Send only when the person changed them, or with new addresses since v3 signs both.
    const editedTo = send && readdressed && addresses !== undefined ? addresses.join(',') : undefined;
    const withWords = send && (changed || (editedTo !== undefined && work.body !== undefined));
    const outcome = await cards.answerDraft(subject, send, withWords ? words : undefined, editedTo);
    setSaid(told(outcome));
    setSending(false);
    onAnswered(outcome, send);
  }

  const editor = (
    <Editor
      words={words}
      onChange={setWords}
      // Escape leaves the box and keeps the words, rather than closing the draft.
      onEscape={(box) => box.blur()}
    />
  );

  return (
    <IslandCard
      className={`flex flex-col gap-2.5 p-3.5 ${className ?? ''}`}
      // Control and Enter sends from the box, as Command Return does on the Mac.
      onKeyDown={(event) => {
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey) && !empty && !badAddress && !sending) void answer(true);
      }}
      aria-label={`${workTitle(work.kind, work.toolkit)}, waiting for you to send it`}
    >
      <div className="flex items-center gap-2">
        <ToolMark toolkit={work.toolkit} size={22} />
        <span className="truncate text-callout font-semibold text-white">{workTitle(work.kind, work.toolkit)}</span>
        <span className="flex-1" />
        <Pressable
          className={`${PRESSABLE} grid size-6 shrink-0 place-items-center rounded-full bg-white/10 text-white/[0.92]`}
          // Not while the key is up, so a stray click cannot turn a send into a decline halfway.
          disabled={sending}
          onClick={() => void answer(false)}
          title={WorkCardLines.close}
          aria-label={WorkCardLines.close}
        >
          <SFSymbol name="xmark" size={12} weight="bold" />
        </Pressable>
      </div>
      <div className="flex min-w-0 items-center gap-1.5 whitespace-nowrap text-caption font-medium">
        <span className="text-footnote font-medium text-white/[0.92]">{shown === undefined ? WorkCardLines.asYou : WorkCardLines.as(shown)}</span>
        {work.account?.check === 'matched' ? (
          <span className="grid text-green" aria-label="your account">
            <SFSymbol name="checkmark.seal.fill" size={11} />
          </span>
        ) : (
          <span className="flex min-w-0 items-center gap-1 truncate text-amber">
            <SFSymbol name="exclamationmark.triangle.fill" size={11} /> not tied to you, check the name
          </span>
        )}
      </div>
      <Rule />
      <div className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto [scrollbar-width:none]">
        <Layout
          work={work}
          who={shown}
          colour={look.colour}
          editor={editor}
          to={readdressable ? <AddressField typed={toText} name={work.toName} bad={badAddress} onChange={setToText} /> : undefined}
        />
        {work.fields.length > 0 && <AlsoSends fields={work.fields} />}
      </div>
      <div className={`flex items-center gap-2 ${sending ? ANSWERING_ROW : ''}`}>
        <span key={said ?? footnote} className="line-clamp-2 animate-[fade-in_200ms_ease-out] text-caption text-white/[0.62]">
          {said ?? footnote}
        </span>
        <span className="flex-1" />
        <Pressable
          className={`${PRESSABLE} inline-flex shrink-0 items-center gap-1.5 rounded-full px-4 py-2 text-callout font-semibold text-white ring-1 ring-white/14 ring-inset`}
          style={{ backgroundColor: look.colour }}
          disabled={empty || badAddress || sending}
          onClick={() => void answer(true)}
          title={empty ? WorkCardLines.writeSomething : badAddress ? WorkCardLines.checkAddress : WorkCardLines.send}
          aria-label={`${look.send} on ${tool}, with your fingerprint`}
        >
          <SFSymbol name="touchid" size={14} />
          {look.send}
        </Pressable>
      </div>
    </IslandCard>
  );
}

/** What a card says after a failed press, in the person's words; the island shakes beside it. */
function told(outcome: HeldOutcome): string | undefined {
  switch (outcome.kind) {
    case 'answered':
    case 'answered-elsewhere':
      return undefined;
    case 'cancelled':
      return HeldLines.cancelled;
    case 'failed':
      return HeldLines.failed(outcome.why);
  }
}

/** Each tool's own layout of the draft. */
function Layout({
  work,
  who,
  colour,
  editor,
  to,
}: {
  work: WorkDraft;
  who: string | undefined;
  colour: string;
  editor: ReactNode;
  to: ReactNode | undefined;
}) {
  switch (workLayout(work.kind)) {
    case 'message':
      // Slack: where it goes, then the message as it will sit in the channel, under their name.
      return (
        <div className="flex flex-col gap-2">
          {work.to !== undefined && work.to.length > 0 && <Chips label="To" people={work.to} />}
          <div className="flex items-start gap-2.5">
            <Avatar who={who} colour={colour} />
            <div className="flex min-w-0 flex-1 flex-col gap-1">
              <div className="flex items-baseline gap-1.5">
                <span className="text-body font-bold text-white">{who ?? WorkCardLines.you}</span>
                <span className="text-caption text-white/[0.62]">now</span>
              </div>
              {work.body !== undefined && editor}
            </div>
          </div>
        </div>
      );
    case 'comment':
      // GitHub and Linear: where it lands, then a comment box headed by who wrote it.
      return (
        <div className="flex flex-col gap-2">
          {work.where !== undefined && <Where place={work.where} />}
          <div className="overflow-hidden rounded-lg border border-white/[0.14]">
            <div className="flex h-card-work-row items-center gap-1.5 bg-white/[0.05] px-2.5 text-footnote text-white">
              <Avatar who={who} colour={colour} size={19.2} />
              <span className="font-bold">{who ?? WorkCardLines.you}</span>
              <span className="text-white/[0.62]">commenting</span>
            </div>
            <Rule />
            {work.body !== undefined && <div className="p-2.5">{editor}</div>}
          </div>
        </div>
      );
    case 'email':
      // Gmail: recipients, subject, then the words; the real address in a field the person can correct.
      return (
        <div className="flex flex-col gap-2">
          {to ?? (work.to !== undefined && work.to.length > 0 && <Chips label="To" people={work.to} />)}
          {work.subject !== undefined && <p className="m-0 text-callout font-semibold text-white">{work.subject}</p>}
          <Rule />
          {work.body !== undefined && editor}
        </div>
      );
    case 'generic':
      // Anything else: a title where there is one, then the words, with every argument listed below.
      return (
        <div className="flex flex-col gap-2">
          {work.where !== undefined && <Where place={work.where} />}
          {work.subject !== undefined && <p className="m-0 text-callout font-semibold text-white">{work.subject}</p>}
          {work.body !== undefined && editor}
        </div>
      );
  }
}

/** The avatar at its own size: a 32 square at radius 6 holding a 14 letter, scaled together at any other. */
const AVATAR = { side: 32, radius: 6, letter: 14 } as const;

/** The first letter of the shown name, 14 bold white on a 32 square of the tool's colour at radius 6. */
function Avatar({ who, colour, size = AVATAR.side }: { who: string | undefined; colour: string; size?: number }) {
  return (
    <span className="grid shrink-0 place-items-center font-bold text-white" style={{ width: size, height: size, borderRadius: AVATAR.radius * (size / AVATAR.side), backgroundColor: colour, fontSize: AVATAR.letter * (size / AVATAR.side) }} aria-hidden>
      {avatarLetter(who)}
    </span>
  );
}

/** Where it lands, after a turn down arrow, in the mono face. */
function Where({ place }: { place: string }) {
  return (
    <p className={`m-0 flex min-w-0 items-center gap-1.5 ${SYSTEM_MONO} text-footnote font-medium text-white/[0.92]`}>
      <SFSymbol name="arrow.turn.down.right" size={12} />
      <span className="truncate">{place}</span>
    </p>
  );
}

/** "To" and up to three people as chips, the rest counted and named on hover. */
function Chips({ label, people }: { label: string; people: readonly string[] }) {
  const { shown, more } = shownPeople(people);
  return (
    <div className="flex min-w-0 items-center gap-2">
      <span className="text-body text-white/[0.62]">{label}</span>
      {shown.map((person) => (
        <span key={person} className="truncate rounded-full bg-white/10 px-2.5 py-1 text-body font-medium text-white">
          {person}
        </span>
      ))}
      {more > 0 && (
        <span className="whitespace-nowrap text-body text-white/[0.62]" title={people.join(', ')}>
          and {more} more
        </span>
      )}
    </div>
  );
}

/** The address itself, never only a name, since a misheard address read as the right person until it had gone out. */
function AddressField({ typed, name, bad, onChange }: { typed: string; name: string | undefined; bad: boolean; onChange: (typed: string) => void }) {
  return (
    <div className={`flex min-w-0 items-center gap-2 rounded-lg bg-white/10 px-2.5 py-1 ${bad ? 'ring-1 ring-amber' : ''}`}>
      <span className="text-body text-white/[0.62]">{WorkCardLines.to}</span>
      <Input
        look="bare"
        className={`flex-1 ${SYSTEM_MONO} text-footnote font-medium text-white select-text`}
        value={typed}
        placeholder={WorkCardLines.addressExample}
        spellCheck={false}
        onValue={onChange}
        onKeyDown={(event) => {
          if (event.key === 'Escape') {
            event.stopPropagation();
            event.currentTarget.blur();
          }
        }}
        onPointerDown={() => void invoke(TAURI_COMMAND.islandKeyboard, { on: true }).catch(() => undefined)}
        onBlur={() => void invoke(TAURI_COMMAND.islandKeyboard, { on: false }).catch(() => undefined)}
        title={WorkCardLines.changeAddress}
        aria-label={WorkCardLines.address}
        aria-invalid={bad}
      />
      {name !== undefined && <span className="truncate text-caption font-medium text-white/[0.62]">{name}</span>}
    </div>
  );
}

/** Every argument the layout did not show, so nothing is sent that the person did not see. */
function AlsoSends({ fields }: { fields: WorkDraft['fields'] }) {
  return (
    <div className="flex flex-col gap-1">
      <p className="m-0 text-caption font-semibold text-white/[0.62]">{WorkCardLines.alsoSends}</p>
      <dl className={`m-0 grid grid-cols-(--mx-card-work-fields) gap-x-2 gap-y-0.5 ${SYSTEM_MONO} text-caption`}>
        {fields.map((field) => (
          <div key={field.name} className="contents">
            <dt className="truncate text-white/[0.62]">{field.name}</dt>
            <dd className="m-0 text-white/[0.92] [overflow-wrap:anywhere]">{field.value}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

/**
 * The words in a box from the start, so the person changes them where they read them and just sends:
 * 14 regular white on white 10%, radius 8, 72 to 180 tall. A click hands the island the keyboard, since
 * until then typing stays in the app the person is in.
 */
function Editor({ words, onChange, onEscape }: { words: string; onChange: (words: string) => void; onEscape: (box: HTMLTextAreaElement) => void }) {
  return (
    // The fill is on the frame, since the bare field draws none of its own.
    <div className="w-full shrink-0 rounded-lg bg-white/10">
    <Textarea
      look="bare"
      className="block max-h-card-editor-most min-h-card-editor-least w-full resize-none rounded-lg p-1.5 font-sans text-callout leading-card-body text-white select-text"
      value={words}
      onValue={onChange}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          event.stopPropagation();
          onEscape(event.currentTarget);
        }
      }}
      onPointerDown={() => void invoke(TAURI_COMMAND.islandKeyboard, { on: true }).catch(() => undefined)}
      onBlur={() => void invoke(TAURI_COMMAND.islandKeyboard, { on: false }).catch(() => undefined)}
      title={WorkCardLines.changeWords}
      aria-label={WorkCardLines.words}
    />
    </div>
  );
}
