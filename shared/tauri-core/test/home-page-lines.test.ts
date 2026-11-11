import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { heldSigningLine, HomePageLines, HomeStartLines, TODAY_TABLE, TodayPageLines } from '../src/core/domain/home-page-lines';

/**
 * Home and Today say what the Mac says. The Mac keeps these words inline in `Text(...)`, so the test reads its sources
 * and finds each one there as a Swift string, with "computer" read back as "Mac" and the key as Touch ID.
 */
const mac = (path: string) => readFileSync(fileURLToPath(new URL(`../../../macos/Sources/${path}`, import.meta.url)), 'utf8');
const app = 'MemnoxVoice/Presentation/App';
const swift = [
  mac(`${app}/HomeDestination.swift`),
  mac(`${app}/TodayDestination.swift`),
  mac(`${app}/HomeStart.swift`),
  mac('MemnoxVoice/Presentation/Components/ConsoleModal.swift'),
  // Home's line is the contract's, kept once as Home's subtitle in the Mac's destinations.
  mac('MemnoxVoiceCore/Domain/Window/Destinations.swift'),
].join('\n');
const onMac = (text: string) => text.replace(/this computer/g, 'this Mac');
const said = (text: string) => swift.includes(`"${onMac(text)}"`);
const page = readFileSync(fileURLToPath(new URL('../src/ui/app/pages/TodayPage.tsx', import.meta.url)), 'utf8');
const styles = readFileSync(fileURLToPath(new URL('../src/ui/styles.css', import.meta.url)), 'utf8');

describe('Home and Today use the Mac words', () => {
  it('puts the same words on Home', () => {
    for (const text of Object.values(HomePageLines)) expect(said(text), text).toBe(true);
  });

  it('puts the same words on the getting started block', () => {
    const { stepsDone, step, ...plain } = HomeStartLines;
    for (const text of Object.values(plain)) expect(said(text), text).toBe(true);
    expect(stepsDone(3, 8)).toBe('3 of 8 steps done');
    expect(step('Add rules', false)).toBe('Add rules, not yet');
  });

  it('heads the table with the same columns in the same order', () => {
    const columns = TodayPageLines.columns.map((title) => `WorkColumn(title: "${title}"`);
    let at = 0;
    for (const column of columns) {
      at = swift.indexOf(column, at);
      expect(at, column).toBeGreaterThan(-1);
    }
  });

  it('puts the same words on the table and its panel', () => {
    const { columns, showAll, press, ...plain } = TodayPageLines;
    for (const text of Object.values(plain)) expect(said(text), text).toBe(true);
    expect(columns.length).toBe(5);
    expect(showAll(9)).toBe('Show all 9');
    expect(press('A')).toBe('Press A');
  });

  it('says how a yes is signed as the Mac does', () => {
    const signing = mac('MemnoxVoiceCore/Domain/Held/HeldConfirmation.swift');
    for (const line of [heldSigningLine(false, undefined, 'Touch ID'), heldSigningLine(true, undefined, 'Touch ID'), heldSigningLine(true, 'digest', 'Touch ID')]) {
      expect(signing.includes(`"${line}"`), line).toBe(true);
    }
    expect(heldSigningLine(true, undefined, 'Windows Hello')).toBe('A yes is signed with Windows Hello');
  });

  it('cuts the table at the Mac widths', () => {
    const table = mac(`${app}/WorkTable.swift`);
    const width = (name: string) => Number(new RegExp(`static let ${name}: CGFloat = (\\d+)`).exec(table)?.[1]);
    expect(TODAY_TABLE).toEqual({ number: width('numberWidth'), from: width('fromWidth'), when: width('whenWidth'), state: width('stateWidth'), logo: width('logo'), head: width('headHeight') });
    // The page reads the widths from styles.css tokens, so the tokens carry the table's widths.
    expect(page).toContain('grid-cols-(--mx-app-work-columns)');
    expect(page).toContain('h-app-work-head');
    expect(styles).toContain(`--mx-app-work-columns: ${TODAY_TABLE.number}px minmax(0, 1fr) ${TODAY_TABLE.from}px ${TODAY_TABLE.when}px ${TODAY_TABLE.state}px;`);
    expect(styles).toContain(`--spacing-app-work-head: ${TODAY_TABLE.head}px;`);
    expect(page).toContain(`size={${TODAY_TABLE.logo}}`);
  });

  it('keeps every column at every width, as the Mac table does', () => {
    // The Mac's WorkTable never folds, so no column hides and no row changes its grid on a narrow window.
    expect(page).not.toMatch(/max-narrow:/);
    expect(page).not.toMatch(/\bnarrow:/);
    expect(page.match(/\$\{TABLE_COLUMNS\}/g)).toHaveLength(2);
  });
});
