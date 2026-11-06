/**
 * TOML cut into coloured runs one line at a time, as the Mac's TomlTokens.swift cuts it, so a code block colours a
 * rule the way the console's does. Every character of a line lands in exactly one token, so joining them gives it back.
 */

export type TomlTokenKind = 'table' | 'key' | 'string' | 'punctuation' | 'comment' | 'plain';

export interface TomlToken {
  readonly text: string;
  readonly kind: TomlTokenKind;
}

const SEPARATORS = new Set(['[', ']', ',', '{', '}']);

/** Every line of the text, tokenized on its own. */
export function tomlLines(text: string): TomlToken[][] {
  return text.split('\n').map(tomlLine);
}

export function tomlLine(line: string): TomlToken[] {
  const indent = /^[ \t]*/.exec(line)?.[0] ?? '';
  const body = line.slice(indent.length);
  if (body === '') return line === '' ? [] : [{ text: line, kind: 'plain' }];
  if (body.startsWith('#')) return [{ text: line, kind: 'comment' }];
  if (body.startsWith('[')) return [{ text: line, kind: 'table' }];
  const equals = body.indexOf('=');
  if (equals < 0) return [{ text: line, kind: 'plain' }];
  const key = body.slice(0, equals);
  const name = key.trim();
  const gap = key.slice(name.length);
  const tokens: TomlToken[] = [
    { text: indent, kind: 'plain' },
    { text: name, kind: 'key' },
    { text: gap, kind: 'plain' },
    { text: '=', kind: 'punctuation' },
    ...tomlValue(body.slice(equals + 1)),
  ];
  return tokens.filter((token) => token.text !== '');
}

/** A value's strings, separators and the plain text between them. */
function tomlValue(text: string): TomlToken[] {
  const tokens: TomlToken[] = [];
  let plain = '';
  const flush = () => {
    if (plain !== '') tokens.push({ text: plain, kind: 'plain' });
    plain = '';
  };
  for (let at = 0; at < text.length; at += 1) {
    const character = text[at]!;
    if (character === '"') {
      flush();
      let string = '"';
      let escaped = false;
      for (at += 1; at < text.length; at += 1) {
        const next = text[at]!;
        string += next;
        if (next === '"' && !escaped) break;
        escaped = next === '\\' && !escaped;
      }
      tokens.push({ text: string, kind: 'string' });
    } else if (character === '#') {
      flush();
      tokens.push({ text: text.slice(at), kind: 'comment' });
      break;
    } else if (SEPARATORS.has(character)) {
      flush();
      tokens.push({ text: character, kind: 'punctuation' });
    } else {
      plain += character;
    }
  }
  flush();
  return tokens;
}
