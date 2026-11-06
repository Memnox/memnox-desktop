import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { LIBRARY_RULES, markToolkit, READY_RULE_CATEGORIES, RULE_MARKS, STARTER_SET } from '../src/core/domain/ready-rule-library';

/**
 * The library is written twice, once in Swift for the Mac and once here, so this reads the Mac's own file and checks
 * every rule field for field, the way the protocol vectors keep both apps on one wire. A rule changed on one side
 * only fails here rather than as two desktops offering different rules.
 */

const swiftFile = fileURLToPath(new URL('../../../macos/Sources/MemnoxVoiceCore/Domain/Studio/ReadyRuleLibrary.swift', import.meta.url));
const swift = readFileSync(swiftFile, 'utf8');

type Token = { kind: 'string' | 'ident' | 'punct'; text: string };
type Value = string | Value[] | { call: string; args: { label?: string; value: Value }[] } | { case: string };

/** Swift's tokens as far as the library uses them: strings, names, and the punctuation of literals and calls. */
function tokenize(source: string): Token[] {
  const tokens: Token[] = [];
  let at = 0;
  while (at < source.length) {
    const character = source[at]!;
    if (/\s/.test(character)) {
      at += 1;
    } else if (source.startsWith('//', at)) {
      at = source.indexOf('\n', at) < 0 ? source.length : source.indexOf('\n', at);
    } else if (character === '"') {
      let text = '';
      at += 1;
      while (source[at] !== '"') {
        if (source[at] === '\\') {
          const next = source[at + 1];
          // An interpolation is kept as written, so a map can fill it in.
          if (next === '(') {
            const close = source.indexOf(')', at);
            text += source.slice(at, close + 1);
            at = close + 1;
            continue;
          }
          text += next === 'n' ? '\n' : next === 't' ? '\t' : (next ?? '');
          at += 2;
          continue;
        }
        text += source[at];
        at += 1;
      }
      at += 1;
      tokens.push({ kind: 'string', text });
    } else if (/[A-Za-z_$]/.test(character)) {
      const match = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(source.slice(at))!;
      tokens.push({ kind: 'ident', text: match[0] });
      at += match[0].length;
    } else {
      tokens.push({ kind: 'punct', text: character });
      at += 1;
    }
  }
  return tokens;
}

/** Evaluates the `static let` declarations of `ReadyRuleLibrary` on demand, each once. */
function library(source: string): (name: string) => Value {
  const body = source.slice(source.indexOf('public enum ReadyRuleLibrary'));
  const tokens = tokenize(body);
  const starts = new Map<string, number>();
  for (let index = 0; index + 1 < tokens.length; index += 1) {
    if (tokens[index]?.text === 'let' && tokens[index + 1]?.kind === 'ident') {
      let at = index + 2;
      while (tokens[at]?.text !== '=') at += 1;
      starts.set(tokens[index + 1]!.text, at + 1);
    }
  }
  const memo = new Map<string, Value>();
  const lookup = (name: string): Value => {
    const known = memo.get(name);
    if (known !== undefined) return known;
    const start = starts.get(name);
    if (start === undefined) throw new Error(`no declaration ${name}`);
    const value = parser(tokens, start, lookup).expression();
    memo.set(name, value);
    return value;
  };
  return lookup;
}

function parser(tokens: Token[], start: number, lookup: (name: string) => Value) {
  let at = start;
  const peek = () => tokens[at];
  const take = (text?: string) => {
    const token = tokens[at];
    if (token === undefined || (text !== undefined && token.text !== text)) throw new Error(`expected ${text ?? 'a token'} at ${at}, found ${token?.text}`);
    at += 1;
    return token;
  };
  const list = (close: string): { label?: string; value: Value }[] => {
    const items: { label?: string; value: Value }[] = [];
    while (peek()?.text !== close) {
      const labelled = peek()?.kind === 'ident' && tokens[at + 1]?.text === ':';
      const label = labelled ? take().text : undefined;
      if (labelled) take(':');
      items.push({ ...(label === undefined ? {} : { label }), value: expression() });
      if (peek()?.text === ',') take(',');
    }
    take(close);
    return items;
  };
  const term = (): Value => {
    const token = take();
    if (token.kind === 'string') return token.text;
    if (token.text === '[') return list(']').map((item) => item.value);
    if (token.text === '.') return { case: take().text };
    if (token.kind !== 'ident') throw new Error(`unexpected ${token.text}`);
    if (peek()?.text === '(') {
      take('(');
      return { call: token.text, args: list(')') };
    }
    const value = lookup(token.text);
    // `name.map { "!\($0).*" }`, the one transform the library writes.
    if (peek()?.text === '.' && tokens[at + 1]?.text === 'map') {
      take('.');
      take('map');
      take('{');
      const template = take().text;
      take('}');
      return (value as string[]).map((each) => template.replace('\\($0)', each));
    }
    return value;
  };
  const expression = (): Value => {
    let value = term();
    while (peek()?.text === '+') {
      take('+');
      value = [...(value as Value[]), ...(term() as Value[])];
    }
    return value;
  };
  return { expression };
}

/** A Swift call or case read as the shape the TypeScript library writes. */
function plain(value: Value): unknown {
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) return value.map(plain);
  if ('case' in value) return value.case;
  const labelled = Object.fromEntries(value.args.filter((arg) => arg.label !== undefined).map((arg) => [arg.label, plain(arg.value)]));
  switch (value.call) {
    case 'LibraryRule': {
      const [id, category, title] = value.args.map((arg) => plain(arg.value));
      return { id, category, title, ...labelled };
    }
    case 'RuleArgument': {
      const [name, values] = value.args.map((arg) => plain(arg.value));
      return { name, values };
    }
    default:
      return labelled;
  }
}

/** The `case` names and the titles of one Swift enum, in its order. */
function enumBlock(name: string): string {
  const start = swift.indexOf(`public enum ${name}`);
  return swift.slice(start, swift.indexOf('\n}\n', start));
}

describe('the ready-made library matches the Mac', () => {
  const lookup = library(swift);

  it('carries the same rules, field for field, in the same order', () => {
    const mac = plain(lookup('rules')) as { id: string }[];
    expect(mac.length).toBe(38);
    expect(LIBRARY_RULES.map((rule) => rule.id)).toEqual(mac.map((rule) => rule.id));
    expect(JSON.parse(JSON.stringify(LIBRARY_RULES))).toEqual(mac);
  });

  it('starts from the same starter set', () => {
    expect(STARTER_SET).toEqual(plain(lookup('starterSet')));
  });

  it('names the same categories with the same titles', () => {
    const block = enumBlock('ReadyRuleCategory');
    const ids = /case ([a-z, ]+)\n/.exec(block)?.[1]?.split(',').map((each) => each.trim());
    const titles = [...block.matchAll(/case \.(\w+): "([^"]+)"/g)].map((match) => ({ id: match[1], title: match[2] }));
    expect(READY_RULE_CATEGORIES.map((category) => category.id)).toEqual(ids);
    expect(READY_RULE_CATEGORIES).toEqual(titles);
  });

  it('names the same marks and draws the same logos', () => {
    const block = enumBlock('RuleMark');
    const marks = [...block.matchAll(/^ {4}case ([a-z, ]+)$/gm)].flatMap((match) => match[1]!.split(',').map((each) => each.trim()));
    expect([...RULE_MARKS]).toEqual(marks);
    const toolkits: Record<string, string | undefined> = {};
    for (const match of block.matchAll(/case ((?:\.\w+,?\s*)+): (rawValue|nil|"[^"]+")/g)) {
      for (const mark of match[1]!.split(',').map((each) => each.trim().slice(1))) {
        toolkits[mark] = match[2] === 'rawValue' ? mark : match[2] === 'nil' ? undefined : match[2]!.slice(1, -1);
      }
    }
    expect(Object.keys(toolkits).sort()).toEqual([...RULE_MARKS].sort());
    for (const mark of RULE_MARKS) expect(markToolkit(mark), mark).toBe(toolkits[mark]);
  });
});
