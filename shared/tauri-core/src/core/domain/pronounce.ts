/**
 * A sentence as a voice should read it, ported from the Mac's `Pronounce.swift`: the abbreviations, file
 * names, flags and folder names an agent's world is full of, written the way a person says them, so Kokoro
 * reads "npm" as N P M and "Speech.swift" as Speech dot swift. Only what is spoken passes through here;
 * the caption and the card keep the words as written.
 */
export function pronounced(text: string): string {
  let spoken = emailAddresses(websites(text));
  spoken = fileNames(spoken);
  for (const [pattern, template] of MACHINE_WORDS) spoken = spoken.replace(pattern, template);
  spoken = spoken.replace(FLAG, 'dash dash $1');
  for (const [written, said] of PHRASES) spoken = spoken.replace(new RegExp(`(?<![\\w-])${escaped(written)}(?![\\w])`, 'g'), said);
  // "memnox-runtime" is two words said together, and a hyphen read aloud is a stumble.
  spoken = spoken.replace(JOINING_HYPHEN, ' ');
  spoken = abbreviations(spoken);
  for (const [symbol, said] of SYMBOLS) spoken = spoken.split(symbol).join(said);
  return spoken
    .split(/\s+/)
    .filter((word) => word !== '')
    .join(' ');
}

/** A command line flag such as `--force`, but not a dash inside a word. */
const FLAG = /(?<![\w-])--([a-z][\w-]*)/g;
/** A hyphen between two letters, as in "memnox-runtime". */
const JOINING_HYPHEN = /(?<=[A-Za-z])-(?=[A-Za-z])/g;
/** A web address, capturing its host without "www.", and leaving any punctuation that ends the sentence. */
const WEBSITE = /https?:\/\/(?:www\.)?([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)(?:[/?#][^\s]*[^\s.,;:!?)])?/g;
/** An email address, capturing the name and the host, never the full stop that ends the sentence. */
const EMAIL_ADDRESS = /([A-Za-z0-9._%+-]+)@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)/g;
/** A file name with an ending of up to five letters, capturing the name and the ending past any folders. */
const FILE_NAME = /(?:[\w.~-]+\/)*([\w-]+(?:\.[\w-]+)*)\.([A-Za-z]{1,5})\b/g;

/** Names that read wrong however they are spelled out, matched as whole words. */
const PHRASES: readonly (readonly [string, string])[] = [
  ['Codex CLI', 'Codex'],
  ['iTerm2', 'eye term'],
  ['iTerm', 'eye term'],
  ['Xcode', 'X code'],
  ['SwiftUI', 'Swift U I'],
  ['Vercel', 'ver sell'],
  ['vitest', 'vee test'],
  ['zsh', 'Z shell'],
  ['stdout', 'standard out'],
  ['stderr', 'standard error'],
  ['sudo', 'sue doo'],
  ['w/', 'with'],
  ['macOS', 'mac O S'],
  ['iOS', 'i O S'],
  ['VS Code', 'V S Code'],
  ['JSON', 'Jason'],
  ['YAML', 'yammel'],
  ['TOML', 'tommel'],
  ['SQL', 'sequel'],
  ['SQLite', 'sequel light'],
  ['GitHub', 'Git Hub'],
  ['OAuth', 'O auth'],
  ['README', 'read me'],
  ['TODO', 'to do'],
  ['OK', 'okay'],
  ['e.g.', 'for example'],
  ['i.e.', 'that is'],
  ['vs.', 'versus'],
  ['etc.', 'and so on'],
];

/** Short words a model reads as one word when a person spells them, lower case included. */
const SPELLED = new Set([
  'npm', 'cli', 'api', 'ui', 'ux', 'mcp', 'ssh', 'url', 'pr', 'id', 'ci', 'cd',
  'aws', 'gcp', 'gpu', 'cpu', 'tts', 'llm', 'sdk', 'dm', 'pid', 'tty', 'html', 'css',
  'http', 'https', 'dns', 'jwt', 'pdf', 'png', 'svg', 'csv', 'os', 'ai', 'ip', 'vm',
  'pnpm', 'npx', 'otlp', 'sha', 'ssd', 'tsx',
]);

/** Upper case words a person says as a word rather than letter by letter. */
const WORDS_IN_CAPITALS = new Set(['NASA', 'I', 'A', 'OK', 'JSON', 'YAML', 'TOML', 'SQL', 'GIF', 'RAM', 'ROM', 'LAN', 'WAN', 'ASAP']);

/** File endings as they are said. */
const ENDINGS: Readonly<Record<string, string>> = {
  ts: 'T S', tsx: 'T S X', js: 'J S', jsx: 'J S X', py: 'pie', md: 'markdown',
  rs: 'R S', go: 'go', rb: 'ruby', sh: 'S H', yml: 'yammel', yaml: 'yammel',
  json: 'Jason', toml: 'tommel', swift: 'swift', css: 'C S S', html: 'H T M L',
  png: 'P N G', svg: 'S V G', plist: 'P list', lock: 'lock', txt: 'text',
};

/** Symbols as they are said, spaced where a symbol alone would be ambiguous. */
const SYMBOLS: readonly (readonly [string, string])[] = [
  [' & ', ' and '], ['%', ' percent'], [' + ', ' plus '], [' = ', ' equals '],
  [' -> ', ' to '], [' => ', ' to '], ['~/', 'home '], ['@', ' at '],
];

/** What machines print and people never say as written, each turned into the words a person would use. */
const MACHINE_WORDS: readonly (readonly [RegExp, string])[] = [
  // "feat/voice-answers" is the voice answers feature branch, and read as written it is a stumble.
  [/\bfeat\//g, 'feature '],
  [/\b(fix|chore|docs|refactor|perf|test|style|release|hotfix)\//g, '$1 '],
  // A commit hash is never said; that it was a commit is the part worth hearing.
  [/\b(?=[0-9a-f]*[0-9])(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b/g, 'commit'],
  [/\bv?(\d+)\.(\d+)\.(\d+)\b/g, '$1 point $2 point $3'],
  [/(\d)\s?ms\b/g, '$1 milliseconds'],
  [/(\d)\s?KB\b/g, '$1 kilobytes'],
  [/(\d)\s?MB\b/g, '$1 megabytes'],
  [/(\d)\s?GB\b/g, '$1 gigabytes'],
  [/(\d)x\b/g, '$1 times'],
  [/#(\d+)/g, 'number $1'],
];

/** A run of capitals this long reads as an abbreviation, so it is spelled out letter by letter. */
const SPELLED_CAPITALS = { least: 2, most: 5 } as const;
/** "PRs" or "IDs": at least two capitals and the plural "s". */
const SHORTEST_PLURAL = 3;

/** A web address as the site it is on, since nobody reads a whole link out: "github dot com". */
function websites(text: string): string {
  return text.replace(WEBSITE, (_whole, host: string) => host.split('.').join(' dot '));
}

/** `Speech.swift` as Speech dot swift, and a path down to its last part, which is how a file is named aloud. */
function fileNames(text: string): string {
  return text.replace(FILE_NAME, (whole, name: string, ending: string) => {
    const said = ENDINGS[ending.toLowerCase()];
    return said === undefined ? whole : `${name.split('.').join(' dot ')} dot ${said}`;
  });
}

/** "UI", "MCP" and "npm" said letter by letter, leaving words a person says whole. */
function abbreviations(text: string): string {
  return text
    .split(' ')
    .map((token) => {
      const core = token.replace(/^[\p{P}]+|[\p{P}]+$/gu, '');
      if (core === '') return token;
      const letters = [...core];
      const capitals = letters.length >= SPELLED_CAPITALS.least && letters.length <= SPELLED_CAPITALS.most && letters.every((letter) => /\p{Lu}/u.test(letter));
      const plural = letters.length >= SHORTEST_PLURAL && letters.slice(0, -1).every((letter) => /\p{Lu}/u.test(letter)) && core.endsWith('s');
      const spell = SPELLED.has(core.toLowerCase()) || (capitals && !WORDS_IN_CAPITALS.has(core));
      if (!spell && !plural) return token;
      const spelled = (plural ? letters.slice(0, -1) : letters).map((letter) => letter.toUpperCase()).join(' ');
      return token.replace(core, plural ? `${spelled}'s` : spelled);
    })
    .join(' ');
}

function escaped(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
}

/** An address read whole, "moise at memnox dot com", since a voice that stops at the dot drops the "com". */
function emailAddresses(text: string): string {
  return text.replace(
    EMAIL_ADDRESS,
    (_whole, name: string, host: string) => `${name.split('.').join(' dot ')} at ${host.split('.').join(' dot ')}`,
  );
}
