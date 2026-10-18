import type { HomeNotCovered, HomeReady, HomeToday, HomeWorking } from '@memnox/core/wire';

/**
 * The home's blocks in plain words, ported from the Mac's `HomeLines`: built only from the daemon's counts
 * and names, so the window never says more than the record does and never puts a score where a count belongs.
 */
export const HomeLines = {
  /** "41 actions, 6 asked you, 5 allowed, 1 refused", or a quiet line before anything ran today. */
  today(today: HomeToday): string {
    if (today.actions + today.asked + today.allowed + today.refused === 0) return 'Nothing has run today.';
    return [counted(today.actions, 'action', 'actions'), `${today.asked} asked you`, `${today.allowed} allowed`, `${today.refused} refused`].join(', ');
  },

  waiting(count: number): string {
    if (count === 0) return 'Nothing waits on you.';
    return count === 1 ? '1 call waits on you.' : `${count} calls wait on you.`;
  },

  /** The question on the ready card, naming the agent only when every yes came from one. */
  ready(ready: HomeReady): string {
    const agent = ready.agentName === undefined ? '' : `, for ${ready.agentName}`;
    return `You have said yes to ${ready.action} ${times(ready.approvals)}${agent}. Let it run on its own?`;
  },

  /** One line per count that is not zero, or one line saying everything is covered. */
  notCovered(notCovered: HomeNotCovered): string[] {
    const lines: string[] = [];
    if (notCovered.unprotected > 0) {
      lines.push(notCovered.unprotected === 1 ? '1 agent here runs outside Memnox.' : `${notCovered.unprotected} agents here run outside Memnox.`);
    }
    if (notCovered.dormant > 0) {
      lines.push(
        notCovered.dormant === 1
          ? '1 agent has been quiet for a month and still holds its reach.'
          : `${notCovered.dormant} agents have been quiet for a month and still hold their reach.`,
      );
    }
    return lines.length === 0 ? ['Every agent here is under Memnox.'] : lines;
  },

  /** A working session's line under its agent's name: its task and where, whichever of them it has. */
  working(working: HomeWorking): string {
    if (working.task !== undefined && working.repository !== undefined) return `${working.task} in ${working.repository}`;
    if (working.task !== undefined) return working.task;
    if (working.repository !== undefined) return `Working in ${working.repository}`;
    return 'Working';
  },
};

function times(count: number): string {
  if (count === 1) return 'once';
  return count === 2 ? 'twice' : `${count} times`;
}

function counted(count: number, one: string, many: string): string {
  return `${count} ${count === 1 ? one : many}`;
}
