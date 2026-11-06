import { useEffect, useMemo, type ReactNode } from 'react';
import { CircleUser, RefreshCw } from 'lucide-react';
import type { MemoryItemView } from '@memnox/core/wire';
import type { Route } from '../../../core/domain/destinations';
import { attentionNodes } from '../../../core/domain/memory-arms/arms-legend';
import { areaOfSource, localArmsInput } from '../../../core/domain/memory-arms/arms-local';
import { brainGrowth, heldReads, workspaceFoot, WorkspaceFootLines, type MemoryHomeFilter } from '../../../core/domain/memory-brain-lines';
import type { MemoryStatusName } from '../../../core/domain/memory-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Button } from '../../kit';
import { ArmsView } from './memory-arms/arms-view';

/** Where Open Account leads, the account page under Settings. */
const ACCOUNT_ROUTE: Route = { destination: 'settings', tab: 'account' };

/**
 * Memory drawn as the brain, as the Mac and Memnox Cloud draw it, from this computer's own reads: every fact memory
 * holds with the documents it cites, the projects' instruction files, the workspace's graph where the runtime answers
 * it, and the skills, rules and servers beside them. Each read waits until the runtime says it answers the method.
 */
export function MemoryBrain({
  parts,
  go,
  nodeCard,
  shown,
  facts,
  home = 'everything',
  status,
  bar,
  foot,
}: {
  parts: SettingsParts;
  go?: (route: Route) => void;
  nodeCard: (nodeId: string, close: () => void) => ReactNode;
  /** The facts the page's project filter leaves on the brain; every fact when absent. */
  shown?: (items: readonly MemoryItemView[]) => readonly MemoryItemView[];
  /** The facts the page's status chip read, which the brain draws in place of every fact, as the Mac does. */
  facts?: readonly MemoryItemView[];
  /** Whose memory the brain draws, the page's "Whose memory" chips. */
  home?: MemoryHomeFilter;
  /** The status chip, which narrows the workspace's decisions too; absent while a search reads every status. */
  status?: MemoryStatusName;
  /** The page's filters, laid over the brain's top left as the Mac lays them. */
  bar?: ReactNode;
  /** The page's own lines under the heading's counts. */
  foot?: ReactNode;
}) {
  const { memory, skills, hub, studio, support } = parts;
  useObserved(memory, skills, hub, studio, support);
  const answers = (method: string) => support.supports(method) === true;
  useEffect(() => {
    void memory.refreshEverything();
    if (memory.sources === undefined) void memory.refreshSources();
  }, []);
  const layers = answers('memory-layers');
  const graph = answers('workspace-graph');
  const skillsHub = answers('skills-hub');
  const mcpHub = answers('mcp-hub');
  const rules = answers('rules');
  useEffect(() => {
    if (layers && memory.layers === undefined) void memory.refreshLayers();
  }, [layers]);
  useEffect(() => {
    if (graph) void memory.refreshWorkspaceGraph();
  }, [graph]);
  useEffect(() => {
    if (skillsHub && skills.hub === undefined) void skills.refresh();
  }, [skillsHub]);
  useEffect(() => {
    if (mcpHub && hub.hub === undefined) void hub.refresh();
  }, [mcpHub]);
  useEffect(() => {
    if (rules && studio.rules === undefined) void studio.refresh();
  }, [rules]);

  const skillList = skills.hub?.skills;
  const ruleList = studio.rules?.rules;
  const servers = hub.hub?.servers;
  const everything = facts ?? memory.everything;
  const held = useMemo(
    () =>
      heldReads({
        ...(everything === undefined ? {} : { items: shown === undefined ? everything : shown(everything) }),
        ...(memory.sources === undefined ? {} : { sources: memory.sources }),
        ...(memory.layers === undefined ? {} : { layers: memory.layers }),
        ...(memory.workspaceGraph === undefined ? {} : { workspace: memory.workspaceGraph }),
        ...(skillList === undefined ? {} : { skills: skillList.map((skill) => ({ name: skill.name, ...(skill.description === undefined ? {} : { description: skill.description }) })) }),
        ...(ruleList === undefined ? {} : { rules: ruleList.map((rule) => ({ name: rule.name, effect: rule.effect })) }),
        ...(servers === undefined ? {} : { servers: servers.map((server) => ({ name: server.name })) }),
      }, home, status),
    [everything, home, status, memory.sources, memory.layers, memory.workspaceGraph, skillList, ruleList, servers, shown],
  );
  const built = useMemo(() => localArmsInput(held), [held]);
  // SOURCES counts every source the brain draws, as the Mac draws each listed source as a node of its own.
  const sourceAreas = useMemo(() => (held.sources ?? []).map((source) => areaOfSource(source)), [held]);
  const attention = useMemo(() => attentionNodes(held), [held]);
  // The growth card reads every source's own counts, whichever memory the chips draw, as the Mac's does.
  const growth = useMemo(() => brainGrowth(memory.sources ?? [], built.map), [memory.sources, built]);
  const cardSkills = useMemo(
    () => (skillList ?? []).map((skill) => ({ name: skill.name, ...(skill.description === undefined ? {} : { description: skill.description }), agents: skill.agents, servers: skill.mcpServers })),
    [skillList],
  );
  const cardRules = useMemo(
    () => (ruleList ?? []).map((rule) => ({ name: rule.name, effect: rule.effect, sentence: rule.sentence, ...(rule.reason === undefined ? {} : { reason: rule.reason }) })),
    [ruleList],
  );
  // The brain stands at least `--mx-app-brain-height` tall, so a short window still shows the whole silhouette.
  return (
    <div className="relative h-(--mx-app-brain-height) w-full">
      <ArmsView
        map={built.map}
        input={built.input}
        skills={cardSkills}
        rules={cardRules}
        {...(go === undefined ? {} : { go })}
        nodeCard={nodeCard}
        sourceAreas={sourceAreas}
        growth={growth}
        attention={attention}
        bar={bar}
        foot={foot}
      />
    </div>
  );
}

/**
 * The workspace's lines under the heading's counts, the Mac's `workspaceFoot`: how a computer not in a workspace joins
 * one, where the picture came from, when it was pulled, what was kept back, and the way to read it again. Said only
 * while the chips draw the workspace too.
 */
export function WorkspaceFoot({ parts, home, go }: { parts: SettingsParts; home: MemoryHomeFilter; go?: (route: Route) => void }) {
  const { memory } = parts;
  useObserved(memory);
  const graph = memory.workspaceGraph;
  if (home === 'thisComputer' || graph === undefined) return null;
  const { lines, join } = workspaceFoot(graph);
  return (
    <>
      {lines.map((line) => (
        <p key={line} className="text-footnote text-muted">
          {line}
        </p>
      ))}
      {join && go !== undefined && (
        <Button icon={CircleUser} className="self-start" onClick={() => go(ACCOUNT_ROUTE)}>
          {WorkspaceFootLines.openAccount}
        </Button>
      )}
      {/* Reads the cloud again now, past the few seconds the runtime holds its last read. */}
      {!join && (
        <Button icon={RefreshCw} className="self-start" onClick={() => void memory.refreshWorkspaceGraph(true)}>
          {WorkspaceFootLines.refresh}
        </Button>
      )}
    </>
  );
}
