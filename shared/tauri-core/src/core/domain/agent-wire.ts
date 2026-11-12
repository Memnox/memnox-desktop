import type { DaemonEvent, DaemonResponse, ProfileView } from '@memnox/core/wire';

// The runtime's wire names these shapes only inside the profile and work answers, so they are read off those answers
// here rather than copied, and a field renamed in the runtime still fails the typecheck.

/** How Memnox reaches an agent, read off what this machine sees in front of it. */
export type AgentConnection = ProfileView['connections'][number];
/** The seven capabilities, enforcement by seam, each computed by the daemon and never here. */
export type CapabilityLevels = ProfileView['levels'];
export type CapabilityLevel = CapabilityLevels['context'];
export type EnforcementSeam = keyof CapabilityLevels['enforcement'];
/** A job description with no agent behind it. */
export type ProfileTemplate = NonNullable<DaemonResponse['templates']>[number];
/** An agent carrying a piece of work a person pointed it at. */
export type AgentWork = NonNullable<DaemonResponse['agentWork']>[number];
export type WorkStatus = AgentWork['status'];
export type WorkHandoff = AgentWork['handoffs'][number];
export type WorkProgress = AgentWork['progress'][number];
export type Tracker = AgentWork['target']['source'];
/** What a work event carries. */
export type WorkChanged = NonNullable<DaemonEvent['workChanged']>;

/** The seams a level is shown for, in the order a strip reads them. */
export const ENFORCEMENT_SEAMS: readonly EnforcementSeam[] = ['shell', 'filesystem', 'git', 'network', 'browser', 'mcp'];

/** Every capability at none, which is what a profile with no agent behind it shows. */
export const NO_LEVELS: CapabilityLevels = {
  context: 'none',
  instructions: 'none',
  tools: 'none',
  activity: 'none',
  coordination: 'none',
  approval: 'none',
  enforcement: { shell: 'none', filesystem: 'none', git: 'none', network: 'none', browser: 'none', mcp: 'none' },
};
