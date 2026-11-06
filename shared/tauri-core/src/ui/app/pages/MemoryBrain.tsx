import { useEffect, useMemo, type ReactNode } from 'react';
import type { MemoryItemView } from '@memnox/core/wire';
import type { Route } from '../../../core/domain/destinations';
import { localArmsInput } from '../../../core/domain/memory-arms/arms-local';
import { workspaceGraphLine } from '../../../core/domain/memory-layers-lines';
import { heldReads, type MemoryHomeFilter } from '../../../core/domain/memory-brain-lines';
import type { MemoryStatusName } from '../../../core/domain/memory-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { ArmsView } from './memory-arms/arms-view';

/** The brain stands this tall at least, so a short window still shows the whole silhouette. */
const LEAST_HEIGHT = 520;

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
  const built = useMemo(
    () =>
      localArmsInput(heldReads({
        ...(everything === undefined ? {} : { items: shown === undefined ? everything : shown(everything) }),
        ...(memory.sources === undefined ? {} : { sources: memory.sources }),
        ...(memory.layers === undefined ? {} : { layers: memory.layers }),
        ...(memory.workspaceGraph === undefined ? {} : { workspace: memory.workspaceGraph }),
        ...(skillList === undefined ? {} : { skills: skillList.map((skill) => ({ name: skill.name, ...(skill.description === undefined ? {} : { description: skill.description }) })) }),
        ...(ruleList === undefined ? {} : { rules: ruleList.map((rule) => ({ name: rule.name, effect: rule.effect })) }),
        ...(servers === undefined ? {} : { servers: servers.map((server) => ({ name: server.name })) }),
      }, home, status)),
    [everything, home, status, memory.sources, memory.layers, memory.workspaceGraph, skillList, ruleList, servers, shown],
  );
  const cardSkills = useMemo(
    () => (skillList ?? []).map((skill) => ({ name: skill.name, ...(skill.description === undefined ? {} : { description: skill.description }), agents: skill.agents, servers: skill.mcpServers })),
    [skillList],
  );
  const cardRules = useMemo(
    () => (ruleList ?? []).map((rule) => ({ name: rule.name, effect: rule.effect, sentence: rule.sentence, ...(rule.reason === undefined ? {} : { reason: rule.reason }) })),
    [ruleList],
  );
  const aside = memory.workspaceGraph === undefined ? undefined : workspaceGraphLine(memory.workspaceGraph);

  return (
    <div className="relative w-full" style={{ height: `max(${LEAST_HEIGHT}px, calc(100vh - 260px))` }}>
      <ArmsView map={built.map} input={built.input} skills={cardSkills} rules={cardRules} {...(go === undefined ? {} : { go })} nodeCard={nodeCard} {...(aside === undefined ? {} : { aside })} bar={bar} foot={foot} />
    </div>
  );
}
