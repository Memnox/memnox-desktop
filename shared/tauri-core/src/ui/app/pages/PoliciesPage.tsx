import { AppWindow, ArrowRight, Ban, Box, Check, CircleHelp, Cloud, Database, Download, FileText, GitBranch, GitPullRequest, Globe, HardDrive, KeyRound, Layers, MessageSquare, Package, Plus, Puzzle, Route, Search, Send, Settings, ShieldAlert, ShieldCheck, Sparkles, SquareTerminal, Undo2, Upload, UserCheck, UserCog, Workflow, Asterisk, type LucideIcon } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { RuleDraftInput, StudioOutcome } from '../../../core/application/studio';
import type { WidthClass } from '../../../core/domain/destinations';
import { canInstall, installWaitsLine, latestLine, publisherLine } from '../../../core/domain/index-lines';
import { agentLabel } from '../../../core/domain/mcp-hub-lines';
import { almostLine, autopilotLine, draftSentence, EFFECT_WORDS, effectTone, exportedCount, NOTHING_TO_EXPORT, packCopiedLine, packSavedLine, sourceWords, weekLine, type Effect } from '../../../core/domain/studio-lines';
import { ALL_CATEGORIES, settledCategory } from '../../../core/domain/catalog';
import { effectTabs, onTab, ruleCards, type EffectTab, type RuleCard } from '../../../core/domain/rule-catalog';
import { MARK_OVERLAP_SHARE, markTiles, type ActionGlyph, type RuleMark } from '../../../core/domain/ready-rule-library';
import { READY_EFFECTS, readyGroups, readyInForce, shownGroups, starterRules, type ReadyRule } from '../../../core/domain/ready-rules';
import { groupCountLine, ruleAsWritten } from '../../../core/domain/rule-words';
import { canChange, changeCountLine, changeLine, changesToml, currentEffect, flatRules, pickingSuggested, PROTECTION, PROTECTION_TABS, readyBadge, readyChanges, removals, type ProtectionTab, type ReadyChange } from '../../../core/domain/protection-lines';
import type { PolicyRuleView } from '@memnox/core/wire';
import { ToolMark } from '../../kit/logos';
import { RULES_FILE } from '../../../core/domain/rule-toml';
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

/** Each effect wears the console's glyph for it. */
const EFFECT_ICONS: Record<Effect, LucideIcon> = { allow: Check, ask: CircleHelp, deny: Ban };

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
  // A ready-made card's Details names its rule in force, which may sit on a card gathered under another name.
  const inspected = cards.find((card) => card.rule !== undefined && (card.id === chosen || card.rules.some((rule) => rule.name === chosen)));
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
            <EffectLegend />
            {scoped.length === 0 && <PointerCard title={PROTECTION.startTitle} note={PROTECTION.startNote} open={() => setTab('readyMade')} />}
            <Section title={PROTECTION.rulesInForce} trailing={<div className="flex flex-wrap items-center gap-2"><PackButtons parts={parts} said={said} /></div>}>
              <PageTabs label="Show rules that" tabs={effectTabs(cards).map((each) => (each.id === 'all' ? { ...each, title: PROTECTION.allTab } : each))} chosen={filter} choose={(id) => setFilter(id as EffectTab)} />
              {view.problems.length > 0 && (
                <div role="alert" className="flex flex-col gap-1 rounded-xl border border-panel-edge bg-card px-4 py-3">
                  {view.problems.map((problem) => (
                    <StatusWord key={problem.file} tone="bad">{`${problem.file}: ${problem.issues.join(' ')}`}</StatusWord>
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
        <Inspector title={inspected.title} width={width} close={() => choose(undefined)} item={inspected.id}>
          <RuleDetail
            card={inspected}
            remove={(name) => void studio.remove(name).then((outcome) => (said(outcome), outcome.kind === 'done' && inspected.rules.length === 1 && choose(undefined)))}
            busy={(name) => studio.busy === name}
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
          <CardGrid>
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
/** The Mac's corner of a square, 8 on a side of 36, scaled to the side drawn. */
const MARK_RADIUS = (MARK_SIDE * 8) / 36;

/**
 * What a rule is about, as the Mac's `RuleMarks` stacks it: up to four squares, each tucked under the one before it and
 * ringed in the card's colour, a product's own logo on white or a glyph for a kind of act.
 */
function RuleMarks({ rule }: { rule: ReadyRule }) {
  const tiles = markTiles(rule.marks, rule.actions);
  return (
    <span className="flex shrink-0 items-center" aria-hidden>
      {tiles.map((tile, at) => {
        const Icon = tile.kind === 'mark' ? MARK_ICONS[tile.mark] : tile.kind === 'action' ? ACTION_ICONS[tile.glyph] : undefined;
        return (
          <span
            key={tile.kind === 'logo' ? tile.toolkit : tile.kind === 'mark' ? tile.mark : tile.glyph}
            className={`grid shrink-0 place-items-center border border-border text-muted ${tile.kind === 'logo' ? 'bg-white' : 'bg-background'}`}
            style={{ width: MARK_SIDE, height: MARK_SIDE, borderRadius: MARK_RADIUS, marginLeft: at === 0 ? 0 : -MARK_SIDE * MARK_OVERLAP_SHARE, boxShadow: '0 0 0 2px var(--color-card)', zIndex: tiles.length - at }}
          >
            {tile.kind === 'logo' ? <ToolMark toolkit={tile.toolkit} size={Math.round(MARK_SIDE * LOGO_SHARE)} /> : Icon !== undefined && <Icon size={Math.round(MARK_SIDE * GLYPH_SHARE)} />}
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
        <RuleMarks rule={rule} />
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
  const { studio, words } = parts;
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
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 px-4 py-[8vh]" role="presentation" onMouseDown={close}>
      <div role="dialog" aria-modal="true" aria-label={PROTECTION.review} className="flex w-full max-w-[560px] flex-col rounded-xl border border-panel-edge bg-card shadow-[0_24px_60px_rgb(0_0_0/0.18)]" onMouseDown={(event) => event.stopPropagation()}>
        <header className="flex flex-col gap-1 border-b border-panel-edge px-5 py-3.5">
          <span className="text-lg font-semibold">{PROTECTION.review}</span>
          <span className="text-footnote text-muted">{PROTECTION.reviewDescription(words.keyTitle)}</span>
        </header>
        <div className="flex flex-col gap-4 px-5 py-5">
          <p className="text-meta text-muted">{`${changeCountLine(changes.length)}. ${PROTECTION.previewed}`}</p>
          <Panel>
            {changes.map((change) => (
              <Row key={change.rule.id} title={change.rule.title} caption={changeLine(change)} trailing={<StatusWord tone={effectTone(change.to)}>{EFFECT_WORDS[change.to].title}</StatusWord>} />
            ))}
          </Panel>
          {taken.length > 0 && <p className="text-meta text-muted">{PROTECTION.retaken}</p>}
          <details>
            <summary className="mx-focus cursor-pointer text-footnote text-muted">{RULES_FILE}</summary>
            <pre className="mt-2 max-h-64 overflow-auto rounded-lg bg-hover p-3 font-mono text-micro">{toml ?? ''}</pre>
          </details>
          {problem !== undefined && <p role="alert" className="text-footnote text-destructive">{problem}</p>}
        </div>
        <footer className="flex items-center justify-end gap-2 border-t border-panel-edge px-5 py-3.5">
          <KitButton onClick={close}>Cancel</KitButton>
          <KitButton kind="primary" disabled={sending || changes.length === 0 || studio.busy !== undefined} onClick={() => void save()}>
            {sending ? PROTECTION.saving : PROTECTION.save}
          </KitButton>
        </footer>
      </div>
    </div>
  );
}

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

/** The three effects said once over the rules, so every word below is already explained. */
function EffectLegend() {
  return (
    <ul className="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-2">
      {(Object.keys(EFFECT_WORDS) as Effect[]).map((effect) => {
        const Icon = EFFECT_ICONS[effect];
        return (
          <li key={effect} className="flex items-start gap-2.5 rounded-xl border border-panel-edge bg-card px-4 py-3">
            <Icon size={16} className="mt-0.5 shrink-0 text-muted" aria-hidden />
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
            caption={card.line}
            chosen={card.id === chosen}
            onClick={() => pick(card.id)}
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

/** A card's rules in plain words first, then each one as written, with where it came from and how it is removed. */
function RuleDetail({ card, remove, busy }: { card: RuleCard; remove: (name: string) => void; busy: (name: string) => boolean }) {
  const count = groupCountLine(card.rules.length);
  return (
    <div className="flex flex-col gap-5">
      <p className="text-headline font-semibold text-foreground">{card.title}</p>
      <span className="flex flex-wrap items-center gap-2">
        {card.rule !== undefined && <ScopeChip scope={ruleScope(card.rule)} />}
        <StatusWord tone={effectTone(card.effect)}>{EFFECT_WORDS[card.effect].says}</StatusWord>
        {count !== undefined && <span className="text-footnote text-muted">{count}</span>}
      </span>
      <p className="text-body text-foreground">{card.line}</p>
      {card.rules.map((rule) => (
        <details key={rule.name} className="flex flex-col gap-3 border-t border-panel-edge pt-3" open={card.rules.length === 1}>
          <summary className="mx-focus cursor-pointer text-footnote text-muted">{card.rules.length === 1 ? 'The rule as written' : rule.name}</summary>
          <div className="flex flex-col gap-3 pt-2">
            <p className="text-footnote text-foreground">{rule.sentence}</p>
            <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1.5 text-footnote">
              {ruleAsWritten(rule).map((each) => (
                <div key={each.field} className="contents">
                  <dt className="text-muted">{each.field}</dt>
                  <dd className="font-mono break-all text-foreground">{each.values}</dd>
                </div>
              ))}
              <dt className="text-muted">From</dt>
              <dd className="text-foreground">{sourceWords(rule)}</dd>
              {rule.until !== undefined && (
                <>
                  <dt className="text-muted">Until</dt>
                  <dd className="text-foreground">{new Date(rule.until).toLocaleString()}</dd>
                </>
              )}
            </dl>
            {rule.editable ? (
              <div>
                <KitButton disabled={busy(rule.name)} onClick={() => remove(rule.name)}>
                  {rule.effect === 'allow' ? 'Remove' : 'Propose removing it'}
                </KitButton>
                {rule.effect !== 'allow' && <p className="pt-2 text-footnote text-muted">Removing a rule that asks or refuses lets agents do more, so it waits for your signature.</p>}
              </div>
            ) : (
              <p className="text-footnote text-muted">This rule is not one set on this computer, so it is changed where it came from.</p>
            )}
          </div>
        </details>
      ))}
    </div>
  );
}

/** When, then, and scope, read back as a sentence before it is proposed; the TOML is there for those who want it. */
function RuleBuilder({ parts, start, close, said }: { parts: SettingsParts; start: Partial<RuleDraftInput>; close: () => void; said: (outcome: StudioOutcome) => void }) {
  const { studio, hub } = parts;
  const [effect, setEffect] = useState<Effect>((start.effect as Effect | undefined) ?? 'ask');
  const [action, setAction] = useState(start.action ?? '');
  const [agent, setAgent] = useState('');
  const [target, setTarget] = useState('');
  const [branch, setBranch] = useState('');
  const [folder, setFolder] = useState('');
  const [reason, setReason] = useState('');
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => first.current?.focus(), []);
  const agents = hub.hub?.agents.map((each) => each.agent) ?? [];
  const known = [...new Set((studio.rules?.rules ?? []).flatMap((rule) => rule.match.actions))].sort();
  const list = (value: string) => (value.trim() === '' ? undefined : [value.trim()]);
  const draft: RuleDraftInput = {
    effect,
    action: action.trim(),
    reason: reason.trim() === '' ? `you chose to ${effect} this` : reason.trim(),
    ...(list(agent) === undefined ? {} : { agents: list(agent) }),
    ...(list(target) === undefined ? {} : { targets: list(target) }),
    ...(list(branch) === undefined ? {} : { branches: list(branch) }),
    ...(list(folder) === undefined ? {} : { workingDirectories: list(folder) }),
  } as RuleDraftInput;
  const field = 'h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 text-body text-foreground outline-none placeholder:text-faint focus:border-primary';
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 px-4 py-[8vh]" role="presentation" onMouseDown={close}>
      <div role="dialog" aria-modal="true" aria-label={PROTECTION.propose} className="flex w-full max-w-[560px] flex-col rounded-xl border border-panel-edge bg-card shadow-[0_24px_60px_rgb(0_0_0/0.18)]" onMouseDown={(event) => event.stopPropagation()}>
        <header className="border-b border-panel-edge px-5 py-3.5 text-lg font-semibold">{PROTECTION.propose}</header>
        <div className="flex flex-col gap-4 px-5 py-5">
          <fieldset className="flex flex-col gap-2">
            <legend className="pb-1.5 text-footnote font-semibold text-muted">When</legend>
            <select className={field} value={agent} onChange={(event) => setAgent(event.target.value)} aria-label="Which agent">
              <option value="">Any agent</option>
              {agents.map((each) => (
                <option key={each} value={each}>
                  {agentLabel(each)}
                </option>
              ))}
            </select>
            <input ref={first} list="known-actions" className={`${field} font-mono`} placeholder="git.push" value={action} onChange={(event) => setAction(event.target.value)} aria-label="The action" />
            <datalist id="known-actions">{known.map((each) => <option key={each} value={each} />)}</datalist>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <input className={field} placeholder="On, optional" value={target} onChange={(event) => setTarget(event.target.value)} aria-label="Target" />
              <input className={field} placeholder="Branch, optional" value={branch} onChange={(event) => setBranch(event.target.value)} aria-label="Branch" />
              <input className={field} placeholder="Folder, optional" value={folder} onChange={(event) => setFolder(event.target.value)} aria-label="Folder" />
            </div>
          </fieldset>
          <fieldset className="flex flex-col gap-2">
            <legend className="pb-1.5 text-footnote font-semibold text-muted">Then</legend>
            <div role="radiogroup" className="grid grid-cols-3 gap-2">
              {(Object.keys(EFFECT_WORDS) as Effect[]).map((each) => (
                <button key={each} type="button" role="radio" aria-checked={effect === each} onClick={() => setEffect(each)} className={`mx-focus cursor-pointer rounded-xl border px-3 py-2.5 text-left ${effect === each ? 'border-primary bg-hover' : 'border-panel-edge hover:bg-hover'}`}>
                  <StatusWord tone={effectTone(each)}>{EFFECT_WORDS[each].title}</StatusWord>
                  <span className="block pt-1 text-micro text-muted">{EFFECT_WORDS[each].says}</span>
                </button>
              ))}
            </div>
            <input className={field} placeholder="Why, in your words" value={reason} onChange={(event) => setReason(event.target.value)} aria-label="Why" />
          </fieldset>
          <p className="rounded-lg bg-hover px-3.5 py-3 text-body text-foreground">{draftSentence(draft, agentLabel)}</p>
          <details>
            <summary className="mx-focus cursor-pointer text-footnote text-muted">Show the rule as written</summary>
            <pre className="mt-2 max-h-48 overflow-auto rounded-lg bg-hover p-3 font-mono text-micro">{JSON.stringify(draft, null, 2)}</pre>
          </details>
        </div>
        <footer className="flex items-center gap-2 border-t border-panel-edge px-5 py-3.5">
          <span className="flex-1 text-footnote text-muted">{`It goes in force when you sign it with ${parts.words.keyTitle}.`}</span>
          <KitButton onClick={close}>Cancel</KitButton>
          <KitButton kind="primary" disabled={action.trim() === '' || studio.busy !== undefined} onClick={() => void studio.propose(draft).then((outcome) => (said(outcome), outcome.kind !== 'failed' && close()))}>
            Propose
          </KitButton>
        </footer>
      </div>
    </div>
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
      <KitButton icon={Download} onClick={() => void exportPack()}>
        Export
      </KitButton>
      <KitButton icon={Upload} onClick={() => void importPack()}>
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
