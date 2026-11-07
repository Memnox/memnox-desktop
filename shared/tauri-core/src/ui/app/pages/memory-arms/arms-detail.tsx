import { Fragment, type ReactNode } from "react";
import { X } from "lucide-react";

import type { Route } from "../../../../core/domain/destinations";
import { effectTone, EFFECT_WORDS, isEffect } from "../../../../core/domain/studio-lines";
import { systemName, type MemoryMapEdge, type MemoryMapNode } from "../../../../core/domain/memory-arms/arms-node";
import { faceInk, initialsFor, profileOf } from "../../../../core/domain/memory-arms/arms-faces";
import type { ArmsItem, ArmsModel } from "../../../../core/domain/memory-arms/arms-model";
import { AgentName } from "../../../kit/logos";
import { Pressable, StatusWord } from "../../../kit";
import { ArmsLines } from "../../../../core/domain/memory-brain-lines";
import { markUrl, QUIET_DOT } from "./arms-support";
import { kindWord } from "./arms-tooltip";

/** A skill as the card says it: what the Skills Hub keeps, the agents it is given to and the servers it calls. */
export type ArmsSkill = { name: string; description?: string; agents?: readonly string[]; servers?: readonly string[] };
/** A rule in force, in its own sentence where the runtime wrote one. */
export type ArmsRule = { name: string; effect?: string; sentence?: string; reason?: string };
export type ArmsApp = { slug: string; name: string };

/** The most names a list in the modal shows before it says how many more there are. */
const MOST_LISTED = 12;

/** Where the card's foot leads for a skill, a rule and an application. */
const SKILLS_ROUTE: Route = { destination: "workspaces", tab: "skills" };
const RULES_ROUTE: Route = { destination: "governance", tab: "policies" };
const CONNECTORS_ROUTE: Route = { destination: "mcp", tab: "apps" };

const LINK = "text-body-sm font-medium text-primary hover:underline";
const QUIET = "h-8 rounded-lg border border-panel-edge px-3 text-meta font-medium text-foreground transition-colors hover:bg-hover";

/**
 * The card for whatever was picked on the ARMS map, floating beside the mark
 * rather than over the page, so the brain stays live behind it: a header
 * naming it, what it says, the things it links to (each one opens in its
 * place), and where to act on it. A memory, a source or a rule the record
 * drew opens the memory map's own card inside it; somebody opens their profile.
 */
export function ArmsCard({
  item,
  model,
  links,
  nodes,
  edges,
  skills,
  rules,
  apps,
  go,
  nodeCard,
  onOpen,
  onSector,
  onClose,
}: {
  item: ArmsItem;
  model: ArmsModel;
  links: ReadonlyMap<string, string[]>;
  nodes: readonly MemoryMapNode[];
  edges: readonly MemoryMapEdge[];
  skills: readonly ArmsSkill[];
  rules: readonly ArmsRule[];
  apps: readonly ArmsApp[];
  /** Opens the page an item is acted on in. */
  go?: (route: Route) => void;
  /** The memory page's own details for one of its nodes. */
  nodeCard: (nodeId: string) => ReactNode;
  /** Opens another item in this modal's place. */
  onOpen: (item: ArmsItem) => void;
  onSector: (key: string) => void;
  onClose: () => void;
}) {
  const area = model.sectors.find((sector) => sector.key === item.sector);
  const byId = new Map(model.items.map((each) => [each.id, each]));
  const held = item.hub === true && item.core !== true ? model.items.filter((each) => each.parent === item.id) : [];
  const heldIds = new Set(held.map((each) => each.id));
  const linked = [...new Set(links.get(item.id) ?? [])]
    .map((id) => byId.get(id))
    .filter((each): each is ArmsItem => each !== undefined && !heldIds.has(each.id));
  const description = area === undefined || item.hub === true ? kindWord(item) : `${kindWord(item)} in ${area.label}`;
  const person = item.kind === "person" || item.kind === "group";

  const footer = (
    <>
      {item.hub === true && item.core !== true && area !== undefined && (
        <Pressable onClick={() => onSector(area.key)} className={QUIET}>
          {ArmsLines.showArea}
        </Pressable>
      )}
      {go !== undefined && <FooterLink item={item} go={go} />}
      <Pressable onClick={onClose} className={`${QUIET} ml-auto`}>
        {ArmsLines.close}
      </Pressable>
    </>
  );

  return (
    <div className="relative flex max-h-(--mx-app-arms-detail-most) flex-col overflow-hidden rounded-2xl border border-panel-edge bg-card shadow-xl">
      <header className="flex items-start justify-between gap-3 p-4 pb-3">
        <div className="flex min-w-0 items-start gap-2.5">
          <Mark item={item} ink={area?.ink} />
          <div className="min-w-0">
            <p className="text-meta font-medium text-muted">{description}</p>
            <h2 className="mt-0.5 break-words text-body font-semibold leading-snug text-foreground">{item.label}</h2>
          </div>
        </div>
        <Pressable aria-label={ArmsLines.close} onClick={onClose} className="shrink-0 rounded-lg p-1 text-muted hover:bg-hover hover:text-foreground">
          <X className="size-4" aria-hidden />
        </Pressable>
      </header>
      <div className="flex min-h-0 flex-col gap-4 overflow-y-auto px-4 pb-3">
        {person && item.nodeId !== undefined ? (
          <ProfileBody
            nodeId={item.nodeId}
            nodes={nodes}
            edges={edges}
            byNode={(id) => model.items.find((each) => each.nodeId === id)}
            onOpen={onOpen}
          />
        ) : (
          <Body item={item} model={model} skills={skills} rules={rules} apps={apps} nodeCard={nodeCard} />
        )}
        {held.length > 0 && <ItemList title={ArmsLines.holds(held.length)} items={held} onOpen={onOpen} />}
        {!person && linked.length > 0 && <ItemList title={ArmsLines.linked} items={linked} onOpen={onOpen} />}
      </div>
      <footer className="flex shrink-0 flex-wrap items-center gap-2 border-t border-panel-edge px-4 py-3">{footer}</footer>
    </div>
  );
}

function Mark({ item, ink }: { item: ArmsItem; ink: string | undefined }) {
  if (item.kind === "person" || item.kind === "group") {
    return (
      <span
        className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full text-meta font-semibold text-white"
        style={{ background: faceInk(item.label) }}
        aria-hidden
      >
        {initialsFor(item.label)}
      </span>
    );
  }
  if (item.logo !== undefined) {
    return <img src={markUrl(item.logo)} alt="" className="size-9 shrink-0 rounded-full border border-panel-edge bg-card object-contain p-1.5" aria-hidden />;
  }
  return <span className="mt-1 size-3 shrink-0 rounded-full" style={{ background: ink ?? QUIET_DOT }} aria-hidden />;
}

function FooterLink({ item, go }: { item: ArmsItem; go: (route: Route) => void }) {
  const place = (title: string, route: Route) => (
    <Pressable onClick={() => go(route)} className={LINK}>
      {title}
    </Pressable>
  );
  if (item.core === true || item.layer === "skill") return place(ArmsLines.openSkills, SKILLS_ROUTE);
  if (item.layer === "rule") return place(ArmsLines.openRules, RULES_ROUTE);
  if (item.layer === "app") return place(ArmsLines.openConnectors, CONNECTORS_ROUTE);
  return null;
}

/** The memory map's card without its own frame, since this card already names the thing and closes it. */
function Bare({ children }: { children: ReactNode }) {
  return <div className="[&>div]:rounded-none [&>div]:border-0 [&>div]:bg-transparent [&>div]:shadow-none [&>div>div]:px-0 [&>div>header]:hidden">{children}</div>;
}

function Body({
  item,
  model,
  skills,
  rules,
  apps,
  nodeCard,
}: {
  item: ArmsItem;
  model: ArmsModel;
  skills: readonly ArmsSkill[];
  rules: readonly ArmsRule[];
  apps: readonly ArmsApp[];
  nodeCard: (nodeId: string) => ReactNode;
}) {
  if (item.core === true) {
    return (
      <>
        <p className="text-body-sm leading-relaxed text-foreground">Every skill around it is kept once in the Skills Hub and written into each agent that is given it, once you sign.</p>
        <p className="text-meta text-muted">
          {skills.length === 0 ? "No skill is kept here yet." : `${skills.length} ${skills.length === 1 ? "skill" : "skills"} kept.`}
        </p>
        {item.nodeId !== undefined && <Bare>{nodeCard(item.nodeId)}</Bare>}
      </>
    );
  }
  if (item.nodeId !== undefined && item.layer === "memory") return <Bare>{nodeCard(item.nodeId)}</Bare>;
  if (item.hub === true) {
    const area = model.sectors.find((sector) => sector.key === item.sector);
    if (area === undefined) return null;
    return <p className="text-body-sm text-foreground">{`${area.count} ${area.count === 1 ? "thing" : "things"} on the map sit in ${area.label}.`}</p>;
  }
  if (item.layer === "skill") {
    const skill = skills.find((each) => `skill:${each.name}` === item.id);
    if (skill === undefined) return null;
    return (
      <>
        {skill.description !== undefined && skill.description !== "" && <p className="text-body-sm text-muted">{skill.description}</p>}
        {(skill.agents ?? []).length > 0 && (
          <p className="text-meta text-muted">
            {"Given to "}
            {(skill.agents ?? []).map((agent, index) => (
              <Fragment key={agent}>
                {index > 0 && ", "}
                <AgentName agent={agent} name={agent} size={12} />
              </Fragment>
            ))}
          </p>
        )}
        {(skill.servers ?? []).length > 0 && (
          <p className="flex flex-wrap gap-1.5">
            {(skill.servers ?? []).map((server) => (
              <StatusWord key={server} tone="quiet">
                {server}
              </StatusWord>
            ))}
          </p>
        )}
      </>
    );
  }
  if (item.layer === "rule") {
    const rule = rules.find((each) => `rule:${each.name}` === item.id) ?? { name: item.label };
    const effect = rule.effect !== undefined && isEffect(rule.effect) ? rule.effect : undefined;
    return (
      <>
        {effect !== undefined && (
          <p>
            <StatusWord tone={effectTone(effect)}>{`${EFFECT_WORDS[effect].title}: ${EFFECT_WORDS[effect].says}`}</StatusWord>
          </p>
        )}
        {rule.sentence !== undefined && <p className="text-body-sm text-foreground">{rule.sentence}</p>}
        {rule.reason !== undefined && <p className="text-body-sm text-muted">{rule.reason}</p>}
        {item.nodeId !== undefined && <Bare>{nodeCard(item.nodeId)}</Bare>}
      </>
    );
  }
  const app = apps.find((each) => `app:${each.slug}` === item.id);
  const fed = model.items.filter((each) => each.layer === "memory" && each.hub !== true && each.system === app?.slug).length;
  return (
    <>
      <p className="text-body-sm text-foreground">{fed === 0 ? "Nothing on the map came from it yet." : `${fed} ${fed === 1 ? "thing" : "things"} on the map came from it.`}</p>
      {item.lastUsed !== undefined && <p className="text-meta text-muted">Last delivered {new Date(item.lastUsed).toLocaleDateString()}.</p>}
    </>
  );
}

/** Somebody's profile: how to reach them where the directory says, what the record joins them to, and where it came from. */
function ProfileBody({
  nodeId,
  nodes,
  edges,
  byNode,
  onOpen,
}: {
  nodeId: string;
  nodes: readonly MemoryMapNode[];
  edges: readonly MemoryMapEdge[];
  byNode: (nodeId: string) => ArmsItem | undefined;
  onOpen: (item: ArmsItem) => void;
}) {
  const profile = profileOf(nodeId, nodes, edges);
  const node = nodes.find((each) => each.id === nodeId);
  return (
    <>
      {node?.detail !== undefined && <p className="text-meta text-muted">{node.detail}</p>}
      {profile.groups.length === 0 && <p className="text-body-sm text-muted">The record joins nothing to them yet.</p>}
      {profile.groups.map((group) => (
        <ItemList
          key={group.kind}
          title={`${group.label} ${group.nodes.length}`}
          items={group.nodes.map((each) => byNode(each.id)).filter((each): each is ArmsItem => each !== undefined)}
          onOpen={onOpen}
        />
      ))}
      {profile.sources.length > 0 && (
        <section className="flex flex-col gap-2">
          <h3 className="text-meta font-medium text-muted">Sources</h3>
          <ul className="flex flex-wrap gap-1.5">
            {profile.sources.map((system) => (
              <li key={system} className="flex items-center gap-1.5 rounded-lg border border-panel-edge px-2 py-1 text-meta text-foreground">
                {systemName(system)}
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  );
}

function ItemList({ title, items, onOpen }: { title: string; items: readonly ArmsItem[]; onOpen: (item: ArmsItem) => void }) {
  if (items.length === 0) return null;
  const more = items.length - MOST_LISTED;
  return (
    <section className="flex flex-col gap-2">
      <h3 className="text-meta font-medium text-muted">{title}</h3>
      <ul className="flex flex-col gap-1">
        {items.slice(0, MOST_LISTED).map((each) => (
          <li key={each.id}>
            <Pressable onClick={() => onOpen(each)} className="w-full truncate rounded-lg px-2 py-1 text-left text-body-sm text-foreground transition-colors hover:bg-hover">
              {each.label}
            </Pressable>
          </li>
        ))}
      </ul>
      {more > 0 && <p className="px-2 text-label text-muted">{ArmsLines.andMore(more)}</p>}
    </section>
  );
}
