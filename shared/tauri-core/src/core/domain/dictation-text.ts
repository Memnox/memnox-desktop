/**
 * What was said, written the way the person would have typed it, ported from the Mac's
 * `DictationText.swift`, `DictationFamily.swift` and `LiveDictation.swift`. Every rule here is about how
 * the words are written and never about what they mean, so nothing acts on a word.
 */

/** How dictated words are laid out: whole sentences, a chat message with no full stop, or a bare prompt. */
export type DictationStyle = 'written' | 'chat' | 'bare';

/** A replacement or a spelling of the person's own: `said` written as `written`; a spelling has no `said`. */
export interface DictationWord {
  readonly said?: string;
  readonly written: string;
}

/** The kind of place the words land, as Memnox Cloud's polish names it, which decides layout and never content. */
export type DictationFamily =
  | 'email'
  | 'work_chat'
  | 'personal_chat'
  | 'document'
  | 'project'
  | 'code_review'
  | 'prompt'
  | 'support'
  | 'social'
  | 'general';

/** Apps by the executable Windows and Linux name them, lowercased and without `.exe`. */
const APPS: Record<string, DictationFamily> = {
  outlook: 'email', olk: 'email', thunderbird: 'email', hxoutlook: 'email', evolution: 'email', geary: 'email', superhuman: 'email',
  slack: 'work_chat', teams: 'work_chat', 'ms-teams': 'work_chat', mattermost: 'work_chat', discord: 'work_chat', element: 'work_chat',
  whatsapp: 'personal_chat', telegram: 'personal_chat', 'telegram-desktop': 'personal_chat', signal: 'personal_chat', 'signal-desktop': 'personal_chat',
  winword: 'document', soffice: 'document', 'soffice.bin': 'document', libreoffice: 'document', notion: 'document', obsidian: 'document',
  notepad: 'document', gedit: 'document', 'gnome-text-editor': 'document', kate: 'document', onenote: 'document',
  linear: 'project', todoist: 'project',
  githubdesktop: 'code_review', 'github-desktop': 'code_review',
  code: 'prompt', 'code-insiders': 'prompt', cursor: 'prompt', windsurf: 'prompt', zed: 'prompt', 'sublime_text': 'prompt',
  windowsterminal: 'prompt', wt: 'prompt', powershell: 'prompt', pwsh: 'prompt', cmd: 'prompt', conhost: 'prompt',
  'gnome-terminal-server': 'prompt', konsole: 'prompt', alacritty: 'prompt', kitty: 'prompt', wezterm: 'prompt', 'wezterm-gui': 'prompt',
  ghostty: 'prompt', 'xfce4-terminal': 'prompt', tilix: 'prompt', xterm: 'prompt', warp: 'prompt', claude: 'prompt', chatgpt: 'prompt',
  codex: 'prompt', idea64: 'prompt', pycharm64: 'prompt', webstorm64: 'prompt', 'jetbrains-toolbox': 'prompt',
};

const BROWSERS = ['chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi', 'chromium', 'arc', 'zen', 'librewolf'];

/** What a page's title names, as browsers put it in the window title. */
const SITES: readonly [string, DictationFamily][] = [
  ['gmail', 'email'], ['outlook', 'email'], ['inbox', 'email'],
  ['slack', 'work_chat'], ['teams', 'work_chat'], ['discord', 'work_chat'],
  ['whatsapp', 'personal_chat'], ['messenger', 'personal_chat'], ['telegram', 'personal_chat'],
  ['google docs', 'document'], ['notion', 'document'], ['confluence', 'document'],
  ['linear', 'project'], ['jira', 'project'], ['asana', 'project'], ['trello', 'project'],
  ['pull request', 'code_review'], ['github', 'code_review'], ['gitlab', 'code_review'],
  ['claude', 'prompt'], ['chatgpt', 'prompt'], ['gemini', 'prompt'],
  ['zendesk', 'support'], ['intercom', 'support'], ['help scout', 'support'],
  ['linkedin', 'social'], [' / x', 'social'], ['twitter', 'social'], ['bluesky', 'social'],
];

/** The family for the app in front, and for a browser the page it shows; general where nothing says otherwise. */
export function dictationFamily(app: string | undefined, windowTitle?: string): DictationFamily {
  const name = (app ?? '').toLowerCase().replace(/\.exe$/, '');
  const known = APPS[name];
  if (known !== undefined) return known;
  const title = (windowTitle ?? '').toLowerCase();
  if (BROWSERS.some((browser) => name.startsWith(browser))) {
    const site = SITES.find(([key]) => title.includes(key));
    if (site !== undefined) return site[1];
  }
  return 'general';
}

/** How the cleanup ends a line of this kind: a chat message and a prompt go without a full stop. */
export function familyStyle(family: DictationFamily): DictationStyle {
  switch (family) {
    case 'work_chat':
    case 'personal_chat':
    case 'social':
      return 'chat';
    case 'prompt':
      return 'bare';
    case 'email':
    case 'document':
    case 'project':
    case 'code_review':
    case 'support':
    case 'general':
      return 'written';
  }
}

const LETTER = /\p{L}/u;
const LETTER_OR_NUMBER = /[\p{L}\p{N}]/u;
const UPPER = /\p{Lu}/u;

/**
 * What was said written as typed: hesitations gone, "scratch that" taking back the sentence before it,
 * "new line" and "new paragraph" kept as breaks, names spelled their way, items counted off laid out as
 * a list, and the sentences capitalised and closed.
 */
export function cleanedDictation(said: string, options: { dictionary?: readonly string[]; replacements?: readonly DictationWord[]; style?: DictationStyle } = {}): string {
  const { dictionary = [], replacements = [], style = 'written' } = options;
  let text = takingBack(said);
  text = withBreaks(text);
  text = withoutHesitations(text);
  text = replaced(text, replacements);
  text = spelledAsTheirs(text, dictionary);
  text = asList(text) ?? text;
  return tidied(text, style);
}

/**
 * What is typed while the person is still speaking: the same cleanup without what only the whole can
 * decide, and the word still being said held back until the next one starts. Once `final`, every word goes in.
 */
export function liveDictation(heard: string, final: boolean, options: { dictionary?: readonly string[]; replacements?: readonly DictationWord[] } = {}): string {
  const { dictionary = [], replacements = [] } = options;
  let text = takingBack(final ? heard : wordsSettled(heard));
  text = withBreaks(text);
  text = withoutHesitations(text);
  text = replaced(text, replacements);
  text = spelledAsTheirs(text, dictionary);
  return tidied(text, 'bare');
}

function wordsSettled(heard: string): string {
  const last = heard[heard.length - 1];
  if (last === undefined || !LETTER_OR_NUMBER.test(last)) return heard;
  const space = heard.search(/\s\S*$/);
  return space === -1 ? '' : heard.slice(0, space);
}

function escaped(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** The person's own replacements, each said phrase written their way wherever it stands whole. */
export function replaced(text: string, words: readonly DictationWord[]): string {
  let result = text;
  for (const word of words) {
    const said = word.said?.trim();
    if (said === undefined || said === '') continue;
    const pattern = new RegExp(`(?<![\\p{L}\\p{N}])${escaped(said)}(?![\\p{L}\\p{N}])`, 'giu');
    result = result.replace(pattern, () => word.written);
  }
  return result;
}

/**
 * Dictation fitted to where the cursor is: a space before it when it follows a word, and when it carries
 * on a sentence already begun, no capital at its start and no full stop where more of that sentence follows.
 */
export function fitted(text: string, before: string | undefined, after: string | undefined): string {
  if (text === '') return text;
  let result = text;
  const previous = before?.[before.length - 1];
  const carriesOn = before !== undefined && sentenceGoesOn(before);
  const first = result[0] ?? '';
  if (carriesOn && UPPER.test(first) && !keepsItsCapital(result)) result = first.toLowerCase() + result.slice(1);
  const next = after?.[0];
  if (next !== undefined && LETTER_OR_NUMBER.test(next)) {
    if (result.endsWith('.') && !result.endsWith('...')) result = result.slice(0, -1);
    result += ' ';
  }
  if (previous !== undefined && !/\s/.test(previous) && !'([{"\''.includes(previous)) result = ` ${result}`;
  return result;
}

function sentenceGoesOn(before: string): boolean {
  const last = before.trimEnd().slice(-1);
  return last !== '' && (LETTER_OR_NUMBER.test(last) || last === ',');
}

/** "I", a name and an acronym keep their capital wherever they stand. */
function keepsItsCapital(text: string): boolean {
  const word = /^\p{L}*/u.exec(text)?.[0] ?? '';
  if (word === 'I') return true;
  return UPPER.test(word.slice(1));
}

const TAKE_BACKS = ['scratch that', 'strike that', 'delete that'];
const SENTENCE_ENDS = new Set(['.', '?', '!', '\n']);

function trimmedOf(text: string, marks: RegExp): string {
  return text.replace(new RegExp(`^(?:${marks.source})+|(?:${marks.source})+$`, 'gu'), '');
}

function takingBack(text: string): string {
  let result = text;
  for (;;) {
    const lower = result.toLowerCase();
    const found = TAKE_BACKS.map((phrase) => ({ at: lower.indexOf(phrase), phrase })).filter((each) => each.at !== -1).sort((a, b) => a.at - b.at)[0];
    if (found === undefined) return result;
    const before = trimmedOf(result.slice(0, found.at), /[\s\p{P}]/u);
    const after = trimmedOf(result.slice(found.at + found.phrase.length), /[\s,.]/u);
    let end = -1;
    for (let index = before.length - 1; index >= 0; index -= 1) {
      if (SENTENCE_ENDS.has(before[index] ?? '')) {
        end = index;
        break;
      }
    }
    const kept = end === -1 ? '' : before.slice(0, end + 1);
    result = kept === '' ? after : `${kept} ${after}`;
  }
}

function withBreaks(text: string): string {
  return text.replace(/[,.]?\s*\bnew paragraph\b[,.]?\s*/gi, '\n\n').replace(/[,.]?\s*\bnew line\b[,.]?\s*/gi, '\n');
}

/** Sounds people make while they think, never words they meant to write. */
const HESITATIONS = ['um', 'umm', 'uh', 'uhh', 'uhm', 'erm', 'er', 'hmm', 'mm', 'ah'];

function withoutHesitations(text: string): string {
  // The comma the recognizer wrote around one goes with it, so no stray comma is left behind.
  return text.replace(new RegExp(`\\b(${HESITATIONS.join('|')})\\b,?\\s*`, 'gi'), '');
}

/** Shortest name worth respelling, so short words that happen to run together never turn into a name. */
const SHORTEST_NAME = 4;
/** A name heard as up to this many words, as "post gres" for Postgres. */
const MOST_WORDS_PER_NAME = 3;

function lettersOf(text: string): string {
  return [...text.toLowerCase()].filter((character) => LETTER_OR_NUMBER.test(character)).join('');
}

function spelledAsTheirs(text: string, dictionary: readonly string[]): string {
  const spelled = new Map<string, string>();
  for (const name of dictionary) {
    const key = lettersOf(name);
    if ([...key].length >= SHORTEST_NAME) spelled.set(key, name);
  }
  if (spelled.size === 0) return text;
  const words = text.split(' ');
  for (let index = 0; index < words.length; index += 1) {
    for (let size = Math.min(MOST_WORDS_PER_NAME, words.length - index); size >= 1; size -= 1) {
      const run = words.slice(index, index + size);
      const name = spelled.get(lettersOf(run.join('')));
      if (name === undefined) continue;
      // Punctuation the recognizer put after the last word stays after the name.
      const trailing = /[^\p{L}\p{N}]*$/u.exec(run[run.length - 1] ?? '')?.[0] ?? '';
      words.splice(index, size, name + trailing);
      break;
    }
  }
  return words.join(' ');
}

const COUNTING = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth'];
/** Fewer than this is a sentence with a "first" in it, not a list. */
const FEWEST_ITEMS = 3;

function capitalisedFirst(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/** Items counted off as "first ..., second ..., third ..." laid out one per line, with what came before as its lead. */
function asList(text: string): string | undefined {
  const pattern = /\b(first|second|third|fourth|fifth|sixth)(ly)?\b[,:]?\s*/gi;
  const marks: RegExpExecArray[] = [];
  for (const match of text.matchAll(pattern)) {
    if ((match[1] ?? '').toLowerCase() === COUNTING[marks.length]) marks.push(match as RegExpExecArray);
    if (marks.length === COUNTING.length) break;
  }
  const first = marks[0];
  if (marks.length < FEWEST_ITEMS || first === undefined) return undefined;
  const lead = trimmedOf(text.slice(0, first.index), /[\s,]/u);
  const items = marks.map((mark, position) => {
    const from = mark.index + mark[0].length;
    const end = marks[position + 1]?.index ?? text.length;
    const item = trimmedOf(text.slice(from, end), /[\s,.;]/u);
    // "and" joining the last item to the one before is part of how it was said, not of the item.
    return capitalisedFirst(item.replace(/\s+and$/, ''));
  });
  const heading = lead === '' ? '' : `${lead.endsWith(':') ? lead : `${trimmedOf(lead, /\p{P}/u)}:`}\n`;
  return heading + items.map((item) => `- ${item}`).join('\n');
}

function tidied(text: string, style: DictationStyle): string {
  let result = text
    .replace(/[ \t]+/g, ' ')
    .replace(/ +([,.?!:;])/g, '$1')
    .replace(/([,;:])\./g, '.')
    .replace(/ *\n */g, '\n')
    .trim();
  result = capitalisedSentences(result);
  const isList = result.includes('\n- ');
  const last = result[result.length - 1];
  if (style === 'written') {
    if (!isList && last !== undefined && LETTER_OR_NUMBER.test(last)) result += '.';
  } else if (result.endsWith('.') && !result.endsWith('...')) {
    result = result.slice(0, -1);
  }
  return result;
}

/** A sentence starts after a mark only once a space follows it, so "server.py" never capitalises what follows. */
function capitalisedSentences(text: string): string {
  let result = '';
  let startOfSentence = true;
  let previous: string | undefined;
  for (const character of text) {
    if (character === '\n' || (character === ' ' && previous !== undefined && SENTENCE_ENDS.has(previous))) startOfSentence = true;
    if (startOfSentence && LETTER.test(character)) {
      result += character.toUpperCase();
      startOfSentence = false;
    } else {
      if (startOfSentence && /\p{N}/u.test(character)) startOfSentence = false;
      result += character;
    }
    previous = character;
  }
  return result;
}

/** One change to the words already typed live: `removed` taken back from the end, then `added` typed. */
export interface LiveRevision {
  readonly kept: string;
  readonly removed: string;
  readonly added: string;
}

/** The characters a person sees, so an accent or an emoji is never split by a revision. */
function graphemes(text: string): string[] {
  return [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text)].map((each) => each.segment);
}

/** How many Backspaces take `text` back, one per character a person sees. */
export function backspacesFor(text: string): number {
  return graphemes(text).length;
}

/** The smallest change from what is typed to what should be there, by whole characters. */
export function liveRevision(typed: string, wanted: string): LiveRevision {
  const have = graphemes(typed);
  const want = graphemes(wanted);
  let shared = 0;
  while (shared < have.length && shared < want.length && have[shared] === want[shared]) shared += 1;
  return { kept: have.slice(0, shared).join(''), removed: have.slice(shared).join(''), added: want.slice(shared).join('') };
}

/** Enough hints to cover a message's names, few enough to leave room for the person's own words. */
export const CURSOR_HINT_LIMIT = 20;
const SHORTEST_HINT = 3;
const COMMON_OPENERS = new Set([
  'the', 'this', 'that', 'these', 'those', 'and', 'but', 'for', 'can', 'could', 'would', 'should', 'will', 'please',
  'thanks', 'thank', 'hello', 'dear', 'yes', 'not', 'what', 'when', 'where', 'why', 'how', 'who', 'which', 'there',
  'here', 'then', 'also', 'just', 'let', 'lets', "let's", 'you', 'your', 'our', 'its', "it's", 'they', 'we', 'she',
  'his', 'her', 'him', 'hey', 'best', 'regards', 'cheers', 'sure', 'okay', 'great', 'good', 'all', 'any', 'some',
]);

function isUnusual(word: string): boolean {
  if (!LETTER.test(word)) return false;
  if (/\p{N}/u.test(word)) return true;
  if (UPPER.test(word.slice(1))) return true;
  if (!UPPER.test(word.charAt(0))) return false;
  return !COMMON_OPENERS.has(word.toLowerCase());
}

/** Words around the cursor the recognizer would not know: names, acronyms and words with digits. */
export function cursorHints(before: string | undefined, after: string | undefined, most = CURSOR_HINT_LIMIT): string[] {
  const text = [before, after].filter((each): each is string => each !== undefined).join(' ');
  const seen = new Set<string>();
  const hints: string[] = [];
  for (const raw of text.split(/\s+/)) {
    const word = raw.replace(/^[^\p{L}\p{N}\-_.]+|[^\p{L}\p{N}\-_.]+$/gu, '').replace(/^\.+|\.+$/g, '');
    if ([...word].length < SHORTEST_HINT || !isUnusual(word) || seen.has(word.toLowerCase())) continue;
    seen.add(word.toLowerCase());
    hints.push(word);
    if (hints.length === most) break;
  }
  return hints;
}
