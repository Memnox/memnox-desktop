import { AppWindow, ArrowRight, ChevronRight, List, Box, Cloud, Database, Download, FileText, GitBranch, GitPullRequest, Globe, HardDrive, KeyRound, Layers, MessageSquare, Package, Plus, Puzzle, Route, Search, Send, Settings, ShieldAlert, ShieldCheck, Sparkles, SquareTerminal, Undo2, Upload, UserCheck, UserCog, Workflow, Asterisk, type LucideIcon } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { RuleDraftInput, StudioOutcome } from '../../../core/application/studio';
import type { WidthClass } from '../../../core/domain/destinations';
import { canInstall, installWaitsLine, latestLine, publisherLine } from '../../../core/domain/index-lines';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { almostLine, autopilotLine, draftSentence, EFFECT_WORDS, effectTone, exportedCount, NOTHING_TO_EXPORT, packCopiedLine, packSavedLine, isEffect, weekLine, type Effect } from '../../../core/domain/studio-lines';
import { RULE_BUILDER, RULE_DETAIL, RULE_DIALOG, RULE_EXAMPLES, ruleCaption, ruleDetailSentence, ruleFacts } from '../../../core/domain/rule-dialog-lines';
import { ALL_CATEGORIES, settledCategory } from '../../../core/domain/catalog';
import { onTab, ruleCards, type EffectTab, type RuleCard } from '../../../core/domain/rule-catalog';
import { MARK_OVERLAP_SHARE, markTiles, type ActionGlyph, type RuleMark } from '../../../core/domain/ready-rule-library';
import { READY_EFFECTS, readyGroups, readyInForce, shownGroups, starterRules, type ReadyRule } from '../../../core/domain/ready-rules';
import { groupCountLine, ruleAsWritten, ruleWords } from '../../../core/domain/rule-words';
import { canChange, changeCountLine, changeLine, changesToml, currentEffect, flatRules, inForceTabs, pickingSuggested, PROTECTION, PROTECTION_TABS, readyBadge, readyChanges, removals, type ProtectionTab, type ReadyChange } from '../../../core/domain/protection-lines';
import type { PolicyRuleView } from '@memnox/core/wire';
import { AgentLogos, ToolMark } from '../../kit/logos';
import { fieldWords, ruleDocument, ruleText, RULES_FILE, tableOfDraft, tableOfRule, type RuleAlternative, type RuleTable } from '../../../core/domain/rule-toml';
import { CodeBlock } from '../code-block';
import { ConsoleChip, DataClassChips, EFFECT_ICONS, RULE_CODE_FIELD, RULE_FIELD, RuleDialog, RuleEffectChoice, RuleField, RuleHint, RulePreview } from './rule-dialog-parts';
import { CatalogCard, CatalogLayout, CatalogSearch, CategoryRail, PageTabs } from '../catalog';
import { KitButton } from '../../settings/kit';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { EmptyState, Inspector, Panel, ReadFailed, Row, ScopeChip, Section, StatusWord, CardGrid } from '../widgets';
import { ruleScope } from '../../../core/domain/scope-lines';
import { usePicked } from '../inspector-host';
import { useShellChoices } from '../shell-choices';
import { inScope, NO_ORGANIZATION_ITEMS, ORGANIZATION_READ_ONLY } from '../../../core/domain/shell-lines';

/** The glyph for a kind of act, as the Mac's `RuleSymbols.mark` draws one where no product's logo fits. */
const MARK_ICONS: Record<RuleMark, LucideIcon> = {
  git: GitBranch,
  files: FileText,
  key: KeyRound,
  terraform: Layers,
  kubernetes: Box,
  cloud: Cloud,
  production: ShieldAlert,
  access: UserCog,
  message: MessageSquare,
  network: Globe,
  package: Box,
  rocket: Send,
  terminal: SquareTerminal,
  workflow: Workflow,
  storage: HardDrive,
  settings: Settings,
  signin: UserCheck,
  mcp: Puzzle,
  github: AppWindow,
  vercel: AppWindow,
  netlify: AppWindow,
  railway: AppWindow,
  fly: AppWindow,
  docker: AppWindow,
  postgresql: AppWindow,
  mongodb: AppWindow,
  stripe: AppWindow,
  heroku: AppWindow,
};


/**
 * Protection settings, laid out as the console's: Ready-made rules, All rules and Autonomy as tabs with counts,
 * the pages its one sidebar row lights. Picks on the ready-made cards gather in one bar as the console's choices
 * do, and nothing built here holds until the person signs it on the island.
 */
export function PoliciesPage({ parts, width }: { parts: SettingsParts; width: WidthClass }) {
  const { studio } = parts;
  useObserved(studio);
  useEffect(() => {
    void studio.refresh();
  }, []);
  useEffect(() => parts.host.onHomeStale?.(() => void studio.refresh()), []);
  // The console's sidebar row lands on the choices first, so this page opens on the ready-made rules.
  const [tab, setTab] = useState<ProtectionTab>('readyMade');
  const [filter, setFilter] = useState<EffectTab>('all');
  const [picked, setPicked] = useState<Record<string, Effect>>({});
  const [reviewing, setReviewing] = useState(false);
  const [chosen, choose] = usePicked();
  const [building, setBuilding] = useState<Partial<RuleDraftInput> | undefined>(undefined);
  const [note, setNote] = useState<string | undefined>(undefined);
  const said = (outcome: StudioOutcome) => setNote(noteOf(outcome, parts.words.keyTitle));
  const { scope, connected } = useShellChoices();

  const view = studio.rules;
  if (view === undefined) return studio.unreadable ? <ReadFailed what="the rules" retry={() => void studio.refresh()} /> : null;
  const scoped = inScope(view.rules, scope, (rule) => rule.source === 'workspace');
  const orgOnly = connected && scope === 'organization';
  const groups = readyGroups(studio.packs ?? []);
  const ready = flatRules(groups);
  const changes = readyChanges(picked, ready, view.rules);
  const cards = ruleCards(scoped, []);
  // The details are one rule's, by name, as the Mac's; the rules that read the same are those on its card.
  const inspected = view.rules.find((rule) => rule.name === chosen);
  const alike = inspected === undefined ? [] : (cards.find((card) => card.rules.includes(inspected))?.rules ?? [inspected]);
  const counts: Record<ProtectionTab, number> = { readyMade: ready.length, allRules: scoped.length, autonomy: studio.progress?.ready.length ?? 0 };
  return (
    <div className="flex min-h-0">
      <div className="flex min-w-0 flex-1 flex-col gap-6">
        <PageTabs label="Protection settings" tabs={PROTECTION_TABS.map((each) => ({ ...each, count: counts[each.id] }))} chosen={tab} choose={(id) => setTab(id as ProtectionTab)} />
        {note !== undefined && <p role="status" className="rounded-lg border border-panel-edge bg-card px-3.5 py-2.5 text-footnote">{note}</p>}
        {tab === 'readyMade' && <ReadyMadeRules parts={parts} groups={groups} inForce={view.rules} picked={picked} setPicked={setPicked} orgOnly={orgOnly} open={choose} />}
        {tab === 'allRules' && (
          <>
            <div className="flex flex-wrap items-center gap-3">
              <p className="min-w-0 flex-1 text-footnote text-muted">{PROTECTION.allIntro}</p>
              <KitButton kind="primary" icon={Plus} onClick={() => setBuilding({ effect: 'ask' })}>
                {PROTECTION.propose}
              </KitButton>
            </div>
            <PointerCard title={PROTECTION.simplerTitle} note={PROTECTION.simplerNote} open={() => setTab('readyMade')} />
            <EffectLegend stacked={width === 'narrow' || width === 'compact'} />
            {scoped.length === 0 && <PointerCard title={PROTECTION.startTitle} note={PROTECTION.startNote} open={() => setTab('readyMade')} />}
            <Section title={PROTECTION.rulesInForce} trailing={<div className="flex flex-wrap items-center gap-2"><PackButtons parts={parts} said={said} /></div>}>
              <PageTabs label="Show rules that" tabs={inForceTabs(scoped)} chosen={filter} choose={(id) => setFilter(id as EffectTab)} />
              {view.problems.length > 0 && (
                <div role="alert" className="flex flex-col gap-1 rounded-xl border border-panel-edge bg-card px-4 py-3">
                  {view.problems.map((problem) => (
                    <p key={problem.file} className="text-footnote font-medium text-destructive">{`${problem.file}: ${problem.issues.join(' ')}`}</p>
                  ))}
                </div>
              )}
              {orgOnly && <p className="text-footnote text-muted">{scoped.length === 0 ? NO_ORGANIZATION_ITEMS : ORGANIZATION_READ_ONLY}</p>}
              <RulesInForce cards={onTab(cards, filter)} filtered={filter !== 'all'} chosen={chosen} pick={choose} />
            </Section>
            {/* The community's rule packs are left off for now, since the marketplace holds no listing yet. */}
          </>
        )}
        {tab === 'autonomy' && <HandOver parts={parts} said={said} />}
        {tab === 'readyMade' && (changes.length > 0) && (
          <ChangesBar count={changes.length} busy={studio.busy !== undefined} undo={() => setPicked({})} review={() => setReviewing(true)} />
        )}
      </div>
      {inspected !== undefined && (
        <Inspector title={inspected.name} width={width} close={() => choose(undefined)} item={inspected.name}>
          <RuleDetail
            rule={inspected}
            alike={alike}
            open={choose}
            remove={(name) => void studio.remove(name).then((outcome) => (said(outcome), outcome.kind === 'done' && choose(undefined)))}
            busy={studio.busy === inspected.name}
          />
        </Inspector>
      )}
      {building !== undefined && <RuleBuilder parts={parts} start={building} close={() => setBuilding(undefined)} said={said} />}
      {reviewing && (
        <ReviewAndSave
          parts={parts}
          changes={changes}
          close={() => setReviewing(false)}
          saved={(outcome) => (said(outcome), setPicked({}), setReviewing(false))}
        />
      )}
    </div>
  );
}

/** The ready-made rules as the console's library lays them out: categories, a search with its count, and the cards. */
function ReadyMadeRules({ parts, groups, inForce, picked, setPicked, orgOnly, open }: { parts: SettingsParts; groups: ReturnType<typeof readyGroups>; inForce: readonly PolicyRuleView[]; picked: Record<string, Effect>; setPicked: (next: Record<string, Effect>) => void; orgOnly: boolean; open: (name: string) => void }) {
  const { studio, words } = parts;
  const busy = studio.busy !== undefined;
  // The packs the daemon ships join the library once read, as the Mac reads them when its library opens.
  useEffect(() => {
    void studio.readPacks();
  }, []);
  const [category, setCategory] = useState<string>(ALL_CATEGORIES);
  const [query, setQuery] = useState('');
  const categories = groups.map((group) => ({ id: group.id, title: group.title, count: group.rules.length }));
  const kind = settledCategory(category, categories);
  const group = kind === ALL_CATEGORIES ? undefined : kind;
  const total = flatRules(groups).length;
  const pool = flatRules(shownGroups(groups, group, ''));
  const shown = flatRules(shownGroups(groups, group, query));
  // Under All the button offers the starter set, and under one category every suggestion there.
  const left = (group === undefined ? starterRules() : pool).filter((rule) => readyInForce(rule, inForce) === undefined && picked[rule.id] === undefined);
  // A pick back to what holds drops it, so the bar only counts real changes.
  const pick = (rule: ReadyRule, effect: Effect) => {
    const next = { ...picked };
    if (currentEffect(rule, inForce) === effect || picked[rule.id] === effect) delete next[rule.id];
    else next[rule.id] = effect;
    setPicked(next);
  };
  return (
    <>
      <p className="text-footnote text-muted">{PROTECTION.readyIntro(words.keyTitle)}</p>
      <CatalogLayout rail={<CategoryRail categories={categories} total={total} chosen={kind} choose={setCategory} allTitle={PROTECTION.allRules} />}>
        <div className="flex items-center gap-3">
          <div className="min-w-0 flex-1">
            <CatalogSearch value={query} placeholder={PROTECTION.search} showing={shown.length} total={pool.length} onChange={setQuery} />
          </div>
          {!orgOnly && left.length > 0 && (
            <KitButton icon={Sparkles} disabled={busy} title={PROTECTION.starterHelp} onClick={() => setPicked(pickingSuggested(left, picked, inForce))}>
              {group === undefined ? PROTECTION.starter : PROTECTION.everySuggestion}
            </KitButton>
          )}
        </div>
        {shown.length === 0 ? (
          <EmptyState icon={Search} title={PROTECTION.noneMatchTitle} body={PROTECTION.noneMatchDetail} />
        ) : (
          <CardGrid min={240} gap={16}>
            {shown.map((rule) => {
              const live = readyInForce(rule, inForce);
              return (
                <ReadyCard
                  key={rule.id}
                  rule={rule}
                  inForce={inForce}
                  picked={picked[rule.id]}
                  disabled={orgOnly || busy || !canChange(rule, inForce)}
                  pick={(effect) => pick(rule, effect)}
                  {...(live === undefined ? {} : { open: () => open(live.name) })}
                />
              );
            })}
          </CardGrid>
        )}
      </CatalogLayout>
    </>
  );
}

/** The glyph a tool's action wears, the lucide stand in for the Mac's SF Symbol of the same name. */
const ACTION_ICONS: Record<ActionGlyph, LucideIcon> = {
  asterisk: Asterisk,
  branch: GitBranch,
  pull: GitPullRequest,
  doc: FileText,
  puzzle: Puzzle,
  globe: Globe,
  cloud: Cloud,
  box: Box,
  stack: Layers,
  send: Send,
  cylinder: Database,
  terminal: SquareTerminal,
};

/** The side of a ready card's squares, and the share of it the glyph and the logo take, as the Mac's card draws them. */
const MARK_SIDE = 28;
const GLYPH_SHARE = 0.42;
const LOGO_SHARE = 0.78;

/**
 * What a rule is about, as the Mac's `RuleMarks` stacks it: up to four squares, each tucked under the one before it and
 * ringed in the card's colour, a product's own logo on white or a glyph for a kind of act.
 */
function RuleMarks({ marks, actions, side = MARK_SIDE }: { marks: readonly RuleMark[]; actions: readonly string[]; side?: number }) {
  // The Mac's corner of a square, 8 on a side of 36, scaled to the side drawn.
  const radius = (side * 8) / 36;
  const tiles = markTiles(marks, actions);
  return (
    <span className="flex shrink-0 items-center" aria-hidden>
      {tiles.map((tile, at) => {
        const Icon = tile.kind === 'mark' ? MARK_ICONS[tile.mark] : tile.kind === 'action' ? ACTION_ICONS[tile.glyph] : undefined;
        return (
          <span
            key={tile.kind === 'logo' ? tile.toolkit : tile.kind === 'mark' ? tile.mark : tile.glyph}
            className={`grid shrink-0 place-items-center border border-border text-muted ${tile.kind === 'logo' ? 'bg-white' : 'bg-background'}`}
            style={{ width: side, height: side, borderRadius: radius, marginLeft: at === 0 ? 0 : -side * MARK_OVERLAP_SHARE, boxShadow: '0 0 0 2px var(--color-card)', zIndex: tiles.length - at }}
          >
            {tile.kind === 'logo' ? <ToolMark toolkit={tile.toolkit} size={Math.round(side * LOGO_SHARE)} /> : Icon !== undefined && <Icon size={Math.round(side * GLYPH_SHARE)} />}
          </span>
        );
      })}
    </span>
  );
}

/**
 * One ready-made rule laid out as the Mac's card: its stack of marks with its effect now and Changed beside it, its
 * name and one line, then Allow, Ask and Deny with Details. A card with a pick waiting is outlined in blue.
 */
function ReadyCard({ rule, inForce, picked, disabled, pick, open }: { rule: ReadyRule; inForce: readonly PolicyRuleView[]; picked: Effect | undefined; disabled: boolean; pick: (effect: Effect) => void; open?: () => void }) {
  const badge = readyBadge(rule, inForce);
  const value = picked ?? currentEffect(rule, inForce);
  return (
    <div className={`flex min-w-0 flex-col gap-3 rounded-xl border bg-card p-4 text-left ${picked === undefined ? 'border-panel-edge' : 'border-primary'}`} aria-label={`${rule.title}, ${badge.word}`}>
      <div className="flex items-start gap-2">
        <RuleMarks marks={rule.marks} actions={rule.actions} />
        <span className="flex-1" />
        <div className="flex flex-col items-end gap-0.5">
          <StatusWord tone={badge.tone}>{badge.word}</StatusWord>
          {/* Reserved on every card, so a marker arriving never moves the title. */}
          <span className={`text-label font-medium text-primary ${picked === undefined ? 'invisible' : ''}`} aria-hidden={picked === undefined}>
            {PROTECTION.changed}
          </span>
        </div>
      </div>
      <div className="flex flex-1 flex-col gap-1">
        <span className="text-body-sm font-medium text-foreground">{rule.title}</span>
        <p className="line-clamp-2 text-meta text-muted" title={`${rule.says}\n${rule.actions.join(', ')}`}>
          {rule.says}
        </p>
      </div>
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <EffectSegments label={rule.title} value={value} suggested={rule.effect} disabled={disabled} pick={pick} />
        </div>
        {open !== undefined && (
          <button type="button" onClick={open} className="mx-focus h-7 shrink-0 cursor-pointer text-meta text-primary" title={disabled ? 'This rule is changed where it came from' : 'Open the rule in force'}>
            {PROTECTION.details}
          </button>
        )}
      </div>
    </div>
  );
}

/** Allow, Ask and Deny as one control, with Suggested under its own segment as the console marks it. */
function EffectSegments({ label, value, suggested, disabled, pick }: { label: string; value: Effect | undefined; suggested: Effect; disabled: boolean; pick: (effect: Effect) => void }) {
  const effects = READY_EFFECTS;
  // The chosen segment wears the tone its effect wears everywhere else.
  const chosenClass: Record<Effect, string> = {
    allow: 'text-success bg-[color-mix(in_oklab,var(--mx-success)_12%,transparent)]',
    ask: 'text-warm bg-[color-mix(in_oklab,var(--mx-warm)_14%,transparent)]',
    deny: 'text-destructive bg-[color-mix(in_oklab,var(--mx-destructive)_12%,transparent)]',
  };
  return (
    <div className={disabled ? 'opacity-50' : ''}>
      <div role="radiogroup" aria-label={label} className="grid grid-cols-3 gap-1 rounded-lg border border-panel-edge p-0.5">
        {effects.map((effect) => (
          <button
            key={effect}
            type="button"
            role="radio"
            aria-checked={value === effect}
            disabled={disabled}
            onClick={() => pick(effect)}
            className={`mx-focus h-7 cursor-pointer rounded-md text-meta font-medium disabled:cursor-default ${value === effect ? chosenClass[effect] : 'text-muted hover:text-foreground'}`}
          >
            {EFFECT_WORDS[effect].title}
          </button>
        ))}
      </div>
      <div aria-hidden className="mt-1 grid min-h-4 grid-cols-3 gap-1">
        {effects.map((effect) => (
          <span key={effect} className="text-center text-label text-muted">
            {effect === suggested ? PROTECTION.suggested : ''}
          </span>
        ))}
      </div>
    </div>
  );
}

/** Pinned to the foot once a choice moved, so saving is one place however far down the cards somebody is. */
function ChangesBar({ count, busy, undo, review }: { count: number; busy: boolean; undo: () => void; review: () => void }) {
  return (
    <div className="sticky bottom-4 z-20">
      <div className="mx-auto flex max-w-3xl flex-wrap items-center gap-3 rounded-xl border border-panel-edge bg-card px-4 py-3 shadow-[0_12px_32px_rgb(0_0_0/0.12)]">
        <p className="min-w-0 flex-1 text-body-sm">
          <span className="font-medium text-foreground">{changeCountLine(count)}</span> <span className="text-muted">{PROTECTION.notSaved}</span>
        </p>
        <KitButton icon={Undo2} disabled={busy} onClick={undo}>
          {PROTECTION.undo}
        </KitButton>
        <KitButton kind="primary" disabled={busy} onClick={review}>
          {PROTECTION.review}
        </KitButton>
      </div>
    </div>
  );
}

/** Review and save, as the Mac's: each change from and to, and the rules as the runtime reads them. Saving takes out each changed rule first, then proposes every new table in one import, each still waiting for its own signature on the island. */
function ReviewAndSave({ parts, changes, close, saved }: { parts: SettingsParts; changes: readonly ReadyChange[]; close: () => void; saved: (outcome: StudioOutcome) => void }) {
  const { studio, words, host } = parts;
  const [sending, setSending] = useState(false);
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const taken = removals(changes);
  const toml = changesToml(changes);
  const save = async () => {
    setSending(true);
    for (const name of taken) {
      const removed = await studio.remove(name);
      if (removed.kind === 'failed') return (setProblem(removed.why), setSending(false));
    }
    if (toml === undefined) return setSending(false);
    const outcome = await studio.importPack(toml);
    setSending(false);
    if (outcome.kind === 'failed') return setProblem(outcome.why);
    saved(outcome);
  };
  return (
    <RuleDialog
      title={PROTECTION.review}
      description={PROTECTION.reviewDescription(words.keyTitle)}
      confirm={{ idle: PROTECTION.save, busy: PROTECTION.saving }}
      proposing={sending}
      canPropose={studio.busy === undefined && changes.length > 0}
      close={close}
      propose={() => void save()}
    >
      <p className="text-footnote text-muted">{`${changeCountLine(changes.length)}. ${PROTECTION.previewed}`}</p>
      <Panel>
        {changes.map((change) => (
          <div key={change.rule.id} className="flex items-center gap-3 px-4 py-3">
            <RuleMarks marks={change.rule.marks.slice(0, 1)} actions={change.rule.actions.slice(0, 1)} side={REVIEW_MARK_SIDE} />
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="text-body-sm font-medium text-foreground">{change.rule.title}</span>
              <span className="text-footnote text-muted">{changeLine(change)}</span>
            </span>
            <StatusWord tone={effectTone(change.to)}>{EFFECT_WORDS[change.to].title}</StatusWord>
          </div>
        ))}
      </Panel>
      {taken.length > 0 && <p className="text-footnote text-muted">{PROTECTION.retaken}</p>}
      <RulePreview code={toml ?? ''} copy={host.copy} />
      {problem !== undefined && <p role="alert" className="text-footnote text-destructive">{problem}</p>}
    </RuleDialog>
  );
}

/** The side of a review row's one mark, as the Mac's review sheet draws it. */
const REVIEW_MARK_SIDE = 28;

/** A card that is a press to the tab that answers the question better, as the console's pointer cards link. */
function PointerCard({ title, note, open }: { title: string; note: string; open: () => void }) {
  return (
    <button type="button" onClick={open} className="mx-focus flex cursor-pointer items-center justify-between gap-4 rounded-xl border border-panel-edge bg-card px-4 py-3 text-left hover:border-muted">
      <span className="min-w-0">
        <span className="block text-body-sm font-medium text-foreground">{title}</span>
        <span className="block text-meta text-muted">{note}</span>
      </span>
      <ArrowRight size={16} className="shrink-0 text-muted" aria-hidden />
    </button>
  );
}

/**
 * The three effects said once over the rules, so every word below is already explained: three across on a wide or
 * medium window, one under another on a narrow or compact one, as the Mac's legend stacks.
 */
function EffectLegend({ stacked }: { stacked: boolean }) {
  return (
    <ul className={stacked ? 'flex flex-col gap-1.5' : 'grid grid-cols-3 items-stretch gap-1.5'}>
      {(Object.keys(EFFECT_WORDS) as Effect[]).map((effect) => {
        const Icon = EFFECT_ICONS[effect];
        return (
          <li key={effect} className="flex items-start gap-2 rounded-xl border border-panel-edge bg-card px-4 py-3">
            <Icon size={14} className="mt-0.5 shrink-0 text-muted" aria-hidden />
            <span className="min-w-0">
              <span className="block text-body-sm font-medium text-foreground">{EFFECT_WORDS[effect].title}</span>
              <span className="block text-meta text-muted">{EFFECT_WORDS[effect].says}</span>
            </span>
          </li>
        );
      })}
    </ul>
  );
}

/** The rules in force as rows, rules that read the same gathered into one with how many say it. */
function RulesInForce({ cards, filtered, chosen, pick }: { cards: readonly RuleCard[]; filtered: boolean; chosen: string | undefined; pick: (id: string) => void }) {
  if (cards.length === 0) {
    return <EmptyState icon={ShieldCheck} title={filtered ? PROTECTION.noRuleHere : PROTECTION.noRules} body={filtered ? PROTECTION.noRuleHereBody : PROTECTION.noRulesBody} />;
  }
  return (
    <Panel>
      {cards.map((card) => {
        const count = groupCountLine(card.rules.length);
        return (
          <Row
            key={card.id}
            title={card.title}
            caption={ruleCaption(card.rule?.match.agents, card.line, agentLabel)}
            chosen={card.rules.some((rule) => rule.name === chosen)}
            onClick={() => pick(card.rules[0]?.name ?? card.id)}
            trailing={
              <>
                {count !== undefined && <span className="inline-flex items-center rounded-full bg-hover px-2 py-px text-label font-medium text-muted">{count}</span>}
                {card.rule !== undefined && <ScopeChip scope={ruleScope(card.rule)} />}
                <StatusWord tone={effectTone(card.effect)}>{EFFECT_WORDS[card.effect].title}</StatusWord>
              </>
            }
          />
        );
      })}
    </Panel>
  );
}

function noteOf(outcome: StudioOutcome, keyTitle: string): string {
  if (outcome.kind === 'proposed') return `Waiting for you on the island: confirm it with ${keyTitle} and it goes in force.`;
  if (outcome.kind === 'failed') return outcome.why;
  return outcome.note;
}

/** An effect as the panel's full width band, as the Mac's: its glyph 12 and its word in the effect's colour on its own tint. */
const BAND_TINT: Record<Effect, string> = {
  allow: 'text-success bg-[color-mix(in_oklab,var(--mx-success)_12%,transparent)]',
  ask: 'text-warm bg-[color-mix(in_oklab,var(--mx-warm)_14%,transparent)]',
  deny: 'text-destructive bg-[color-mix(in_oklab,var(--mx-destructive)_12%,transparent)]',
};

function EffectBand({ effect }: { effect: Effect }) {
  const Icon = EFFECT_ICONS[effect];
  return (
    <div className={`flex min-h-[30px] w-full items-center gap-1.5 rounded-md px-2 ${BAND_TINT[effect]}`}>
      <Icon size={12} strokeWidth={2.4} aria-hidden />
      <span className="text-body-sm font-medium">{EFFECT_WORDS[effect].title}</span>
    </div>
  );
}

/** Label and value as the Mac's FactList sets them: a grid, 16 across and 8 down, all in 12, the label muted. */
function FactList({ facts, agents = {} }: { facts: readonly [string, string][]; agents?: Readonly<Record<string, readonly string[]>> }) {
  return (
    <dl className="grid grid-cols-[auto_minmax(0,1fr)] items-baseline gap-x-4 gap-y-2 text-meta">
      {facts.map(([label, value]) => (
        <div key={label} className="contents">
          <dt className="text-muted">{label}</dt>
          <dd className="flex min-w-0 items-center gap-1.5 break-words text-foreground select-text">
            {agents[label] !== undefined && agents[label].length > 0 && <AgentLogos agents={agents[label].map((agent) => ({ agent, name: agentLabel(agent) }))} />}
            {value}
          </dd>
        </div>
      ))}
    </dl>
  );
}

/** How the details write a moment, the day and the time, as the Mac's abbreviated date with a short time. */
const moment = (iso: string): string => {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? iso : date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
};

/**
 * One rule whole, as the Mac's rule panel: its effect as a band, its plain title, why it exists, the rules that say
 * the same, the rule as written behind a disclosure, its other fields, and Remove where it is this computer's own.
 */
function RuleDetail({ rule, alike, open, remove, busy }: { rule: PolicyRuleView; alike: readonly PolicyRuleView[]; open: (name: string) => void; remove: (name: string) => void; busy: boolean }) {
  const words = ruleWords(rule);
  const effect = isEffect(rule.effect) ? rule.effect : undefined;
  const sentence = effect === undefined ? rule.sentence : ruleDetailSentence({ actions: rule.match.actions, effect, ...(rule.match.agents === undefined ? {} : { agents: rule.match.agents }), ...(rule.match.targets === undefined ? {} : { targets: rule.match.targets }) }, agentLabel);
  return (
    <div className="flex flex-col">
      <div className="flex flex-col gap-3 pb-4">
        {effect !== undefined && <EffectBand effect={effect} />}
        <h3 className="text-lg font-semibold text-foreground select-text">{words.title}</h3>
      </div>
      <div className="h-px bg-panel-edge" />
      <div className="flex flex-col gap-5 pt-4">
        <div className="flex flex-col gap-0.5">
          <span className="text-meta text-muted">{RULE_DETAIL.why}</span>
          <span className="text-body-sm text-foreground select-text">{ruleCaption(rule.match.agents, words.why, agentLabel)}</span>
        </div>
        {alike.length > 1 && (
          <div className="flex flex-col items-start gap-1">
            <span className="text-meta text-muted">{groupCountLine(alike.length)}</span>
            {alike.map((each) => (
              <button
                key={each.name}
                type="button"
                aria-pressed={each.name === rule.name}
                onClick={() => open(each.name)}
                className={`mx-focus cursor-pointer text-left text-body-sm ${each.name === rule.name ? 'font-medium text-foreground' : 'text-primary'}`}
              >
                {each.name}
              </button>
            ))}
          </div>
        )}
        <details key={rule.name} className="group">
          <summary className="mx-focus flex cursor-pointer list-none items-center gap-1.5 text-body-sm font-medium text-foreground select-none">
            <ChevronRight size={12} strokeWidth={2.4} className="text-muted transition-transform group-open:rotate-90" aria-hidden />
            {RULE_DETAIL.asWritten}
          </summary>
          <div className="flex flex-col gap-3 pt-2">
            <p className="text-body-sm leading-relaxed text-foreground select-text">{sentence}</p>
            <FactList facts={ruleAsWritten(rule).map((each) => [each.field, each.values])} agents={{ [RULE_DETAIL.agents]: rule.match.agents ?? [] }} />
            <CodeBlock code={ruleText(tableOfRule(rule))} label={RULES_FILE} />
          </div>
        </details>
        <FactList facts={ruleFacts(rule, moment)} />
        {rule.editable ? (
          <div className="flex flex-col items-start gap-2">
            <KitButton disabled={busy} onClick={() => remove(rule.name)}>
              {rule.effect === 'allow' ? RULE_DETAIL.remove : RULE_DETAIL.proposeRemoving}
            </KitButton>
            {rule.effect !== 'allow' && <p className="text-footnote text-muted">{RULE_DETAIL.removeNote}</p>}
          </div>
        ) : (
          <p className="text-footnote text-muted">{RULE_DETAIL.elsewhere}</p>
        )}
      </div>
    </div>
  );
}

/**
 * Proposing a rule is a decision, so it is a dialog laid out as the Mac's: the action, what happens when an agent
 * tries it, then what narrows it, read back as a sentence and shown as the TOML the runtime reads. A rule naming the
 * data it carries or a way round goes up as that TOML, since a draft alone cannot carry either.
 */
function RuleBuilder({ parts, start, close, said }: { parts: SettingsParts; start: Partial<RuleDraftInput>; close: () => void; said: (outcome: StudioOutcome) => void }) {
  const { studio, hub, words, host } = parts;
  const [effect, setEffect] = useState<Effect>((start.effect as Effect | undefined) ?? 'ask');
  const [action, setAction] = useState(start.action ?? '');
  const [agent, setAgent] = useState('');
  const [targets, setTargets] = useState('');
  const [carries, setCarries] = useState('');
  const [classes, setClasses] = useState('');
  const [branch, setBranch] = useState('');
  const [folder, setFolder] = useState('');
  const [insteadAction, setInsteadAction] = useState('');
  const [insteadNote, setInsteadNote] = useState('');
  const [reason, setReason] = useState('');
  // Why the runtime refused the last proposal, said in the dialog since the page behind it is covered.
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => first.current?.focus(), []);
  const agents = hub.hub?.agents.map((each) => each.agent) ?? [];
  const known = [...new Set((studio.rules?.rules ?? []).flatMap((rule) => rule.match.actions))].sort();
  const why = reason.trim();
  const optional = <K extends string>(key: K, values: string[] | undefined) => (values === undefined ? {} : ({ [key]: values } as Record<K, string[]>));
  const draft = {
    effect,
    action: action.trim(),
    reason: why === '' ? `you chose to ${effect} this` : why,
    ...optional('branches', fieldWords(branch)),
    ...optional('targets', fieldWords(targets)),
    ...optional('agents', agent === '' ? undefined : [agent]),
    ...optional('workingDirectories', fieldWords(folder)),
    ...optional('classes', fieldWords(classes)),
  } as RuleDraftInput;
  const way = { action: insteadAction.trim(), note: insteadNote.trim() };
  const alternative: RuleAlternative | undefined = effect === 'deny' && way.action !== '' && way.note !== '' ? way : undefined;
  // One half of the way round named without the other, which the runtime would refuse.
  const halfAnAlternative = effect === 'deny' && (way.action === '') !== (way.note === '');
  const table: RuleTable = { ...tableOfDraft(draft, fieldWords(carries)), ...(alternative === undefined ? {} : { alternative }) };
  const asFile = fieldWords(carries) !== undefined || alternative !== undefined;
  const sending = studio.busy === 'propose' || studio.busy === 'pack';
  const canPropose = draft.action !== '' && !halfAnAlternative && studio.busy === undefined;
  const sentence = draftSentence(draft, agentLabel);
  const propose = () =>
    void (asFile ? studio.importPack(ruleDocument([ruleText(table)])) : studio.propose(draft)).then((outcome) => {
      said(outcome);
      if (outcome.kind === 'failed') return setProblem(outcome.why);
      close();
    });
  const code = (placeholder: string, value: string, set: (next: string) => void, label: string) => (
    <input className={RULE_CODE_FIELD} placeholder={placeholder} value={value} onChange={(event) => set(event.target.value)} aria-label={label} />
  );
  return (
    <RuleDialog title={RULE_BUILDER.title} description={RULE_DIALOG.proposeDescription(words.keyTitle)} proposing={sending} canPropose={canPropose} close={close} propose={propose}>
      <RuleField label={RULE_BUILDER.action}>
        <div className="flex items-center gap-1.5">
          <input ref={first} className={RULE_CODE_FIELD} placeholder={RULE_BUILDER.actionPlaceholder} value={action} onChange={(event) => setAction(event.target.value)} aria-label={RULE_BUILDER.action} />
          {known.length > 0 && (
            <label className="relative grid size-9 shrink-0 cursor-pointer place-items-center rounded-lg text-muted hover:bg-hover hover:text-foreground" title={RULE_BUILDER.knownHelp}>
              <List size={14} aria-hidden />
              <select className="absolute inset-0 cursor-pointer opacity-0" value="" onChange={(event) => event.target.value !== '' && setAction(event.target.value)} aria-label={RULE_BUILDER.knownActions}>
                <option value="" />
                {known.map((each) => (
                  <option key={each} value={each}>
                    {each}
                  </option>
                ))}
              </select>
            </label>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-1.5 pt-1">
          <span className="flex h-8 items-center text-meta text-muted">{RULE_BUILDER.tryOne}</span>
          {RULE_EXAMPLES.map((example) => (
            <ConsoleChip key={example.action} title={example.title} chosen={action.trim() === example.action} choose={() => setAction(example.action)} />
          ))}
        </div>
      </RuleField>
      <RuleEffectChoice chosen={effect} choose={setEffect} />
      <RuleField label={RULE_BUILDER.agent} optional>
        <select className={RULE_FIELD} value={agent} onChange={(event) => setAgent(event.target.value)} aria-label={RULE_BUILDER.agent}>
          <option value="">{RULE_BUILDER.anyAgent}</option>
          {agents.map((each) => (
            <option key={each} value={each}>
              {agentLabel(each)}
            </option>
          ))}
        </select>
      </RuleField>
      <RuleField label={RULE_BUILDER.targets} optional hint={RULE_BUILDER.targetsHint}>
        {code(RULE_BUILDER.targetsPlaceholder, targets, setTargets, RULE_BUILDER.targets)}
      </RuleField>
      <RuleField label={RULE_BUILDER.carries} optional>
        {code(RULE_BUILDER.carriesPlaceholder, carries, setCarries, RULE_BUILDER.carries)}
        <RuleHint text={RULE_BUILDER.carriesHint} />
        <DataClassChips text={carries} setText={setCarries} />
      </RuleField>
      <RuleField label={RULE_BUILDER.classes} optional hint={RULE_BUILDER.classesHint}>
        {code(RULE_BUILDER.classesPlaceholder, classes, setClasses, RULE_BUILDER.classes)}
      </RuleField>
      <div className="grid grid-cols-2 items-start gap-2">
        <RuleField label={RULE_BUILDER.branch} optional>
          {code(RULE_BUILDER.branchPlaceholder, branch, setBranch, RULE_BUILDER.branch)}
        </RuleField>
        <RuleField label={RULE_BUILDER.folder} optional>
          {code(RULE_BUILDER.folderPlaceholder, folder, setFolder, RULE_BUILDER.folder)}
        </RuleField>
      </div>
      {effect === 'deny' && (
        <RuleField label={RULE_BUILDER.instead} optional hint={RULE_BUILDER.insteadHint}>
          {code(RULE_BUILDER.insteadAction, insteadAction, setInsteadAction, RULE_BUILDER.insteadActionLabel)}
          <input className={RULE_FIELD} placeholder={RULE_BUILDER.insteadNote} value={insteadNote} onChange={(event) => setInsteadNote(event.target.value)} aria-label={RULE_BUILDER.insteadNoteLabel} />
        </RuleField>
      )}
      <RuleField label={RULE_BUILDER.why} optional>
        <input className={RULE_FIELD} placeholder={RULE_BUILDER.whyPlaceholder} value={reason} onChange={(event) => setReason(event.target.value)} aria-label="Why" />
      </RuleField>
      <p className="rounded-xl bg-hover p-3 text-body-sm font-medium text-foreground" aria-label={RULE_BUILDER.readBack(sentence)}>
        {sentence}
      </p>
      <RulePreview code={ruleText(table)} copy={host.copy} />
      {problem !== undefined && <p role="alert" className="text-footnote text-destructive">{problem}</p>}
    </RuleDialog>
  );
}

/** Autonomy as the console's hand over page: what could run without asking, how close the rest is, and what the autopilot already answers. */
function HandOver({ parts, said }: { parts: SettingsParts; said: (outcome: StudioOutcome) => void }) {
  const { studio, home, words } = parts;
  const progress = studio.progress;
  const any = progress !== undefined && (progress.ready.length > 0 || progress.almost.length > 0 || progress.grants.length > 0);
  return (
    <>
      <p className="text-footnote text-muted">{PROTECTION.autonomyIntro}</p>
      {progress !== undefined && (
        <div className="flex flex-col gap-1 rounded-xl border border-panel-edge bg-card px-4 py-3.5">
          <span className="text-body font-semibold text-foreground">{progress.ladder.says}</span>
          {progress.ladder.needs !== undefined && <span className="text-footnote text-muted">{progress.ladder.needs}</span>}
          <span className="text-footnote text-muted">{`${weekLine(progress)} ${autopilotLine(progress.thisWeek.answeredByAutopilot)}`}</span>
          <ol className="flex flex-wrap gap-1.5 pt-2" aria-label="Autonomy ladder">
            {progress.ladder.rungs.map((rung) => (
              <li key={rung} className={`rounded-full border px-2.5 py-0.5 text-micro ${rung === progress.ladder.level ? 'border-primary font-semibold text-foreground' : 'border-panel-edge text-muted'}`}>
                {rung}
              </li>
            ))}
          </ol>
        </div>
      )}
      <Section title={PROTECTION.readyToHandOver}>
        {!any || progress === undefined ? (
          <EmptyState icon={Route} title={PROTECTION.nothingReady} body={PROTECTION.nothingReadyBody} />
        ) : (
          <Panel>
            {progress.ready.map((ready) => (
              <Row
                key={ready.action}
                title={`${ready.action}, said yes ${ready.approvals} times`}
                caption={ready.because}
                trailing={
                  <KitButton kind="primary" disabled={home.handingOver} onClick={() => void home.handOver(ready, words.keyTitle)}>
                    {home.handingOver ? PROTECTION.proposing : PROTECTION.stopAsking}
                  </KitButton>
                }
              />
            ))}
            {progress.almost.map((almost) => (
              <Row key={almost.action} title={almostLine(almost)} caption={PROTECTION.almostCaption} />
            ))}
            {progress.grants.map((grant) => (
              <Row
                key={grant.id}
                title={grant.says}
                caption={`The autopilot answers this until ${new Date(grant.until).toLocaleDateString()}`}
                trailing={
                  <KitButton disabled={studio.busy === grant.id} onClick={() => void studio.revoke(grant.id).then(said)}>
                    {PROTECTION.takeBack}
                  </KitButton>
                }
              />
            ))}
          </Panel>
        )}
      </Section>
    </>
  );
}

/** Rule packs from the community index, beside import and export; installing proposes each rule, signed on its own. */
function IndexPacks({ parts, said }: { parts: SettingsParts; said: (note: string) => void }) {
  const { index, words } = parts;
  useObserved(index);
  useEffect(() => {
    void index.readPacks();
  }, []);
  const packs = index.packs;
  if (packs === undefined || packs.length === 0) return null;
  return (
    <Section title="Rule packs from the community index">
      <CardGrid>
        {packs.map((pack) => (
          <CatalogCard
            key={pack.id}
            icon={<Package size={15} aria-hidden />}
            title={pack.name}
            line={`${pack.description} · ${publisherLine(pack.publisher)}`}
            badges={canInstall(pack) ? <StatusWord tone="quiet">{latestLine(pack)}</StatusWord> : <StatusWord tone="bad">Marked unsafe</StatusWord>}
            {...(canInstall(pack)
              ? {
                  action: (
                    <KitButton icon={Download} disabled={index.busy === pack.name} onClick={() => void index.install(pack.name, pack.latest?.version).then((outcome) => said(outcome.kind === 'failed' ? outcome.why : outcome.note))}>
                      Install
                    </KitButton>
                  ),
                }
              : {})}
          />
        ))}
      </CardGrid>
      <p className="text-footnote text-muted">{installWaitsLine('rule_pack', words.keyTitle)}</p>
    </Section>
  );
}

/** A pack is a TOML file: saved and opened through the system's own dialogs, and imported one rule proposal at a time. */
function PackButtons({ parts, said }: { parts: SettingsParts; said: (outcome: StudioOutcome) => void }) {
  const { studio, host } = parts;
  const picker = useRef<HTMLInputElement>(null);
  const exportPack = async () => {
    const toml = await studio.exportToml();
    if (toml === undefined || exportedCount(toml) === 0) return said({ kind: 'done', note: NOTHING_TO_EXPORT });
    // A preview has no save dialog, so there the pack is copied instead.
    if (host.saveRulePack === undefined) {
      await host.copy(toml);
      return said({ kind: 'done', note: packCopiedLine(exportedCount(toml)) });
    }
    const saved = await host.saveRulePack(toml).catch((why: unknown) => String(why));
    if (typeof saved === 'string') return said({ kind: 'failed', why: saved });
    if (saved) said({ kind: 'done', note: packSavedLine(exportedCount(toml)) });
  };
  const importPack = async () => {
    if (host.pickRulePack === undefined) return picker.current?.click();
    const toml = await host.pickRulePack().catch((why: unknown) => new Error(String(why)));
    if (toml instanceof Error) return said({ kind: 'failed', why: toml.message });
    if (toml !== undefined) said(await studio.importPack(toml));
  };
  return (
    <>
      <KitButton icon={Download} title="Save the rules set on this computer as a TOML file" onClick={() => void exportPack()}>
        Export
      </KitButton>
      <KitButton icon={Upload} disabled={studio.busy === 'pack'} title="Propose every rule in a TOML file, each signed on its own" onClick={() => void importPack()}>
        Import
      </KitButton>
      <input
        ref={picker}
        type="file"
        accept=".toml,text/plain"
        className="hidden"
        onChange={(event) => {
          const file = event.target.files?.[0];
          if (file !== undefined) void file.text().then((toml) => studio.importPack(toml)).then(said);
          event.target.value = '';
        }}
      />
    </>
  );
}
