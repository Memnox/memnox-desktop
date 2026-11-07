import {
  AppWindow,
  Bot,
  Brain,
  FolderGit2,
  History,
  Inbox,
  Laptop,
  Mic,
  Monitor,
  Plug,
  ScrollText,
  Sparkles,
  UserRound,
  type LucideIcon,
} from 'lucide-react';
import { useRef, type KeyboardEvent, type ReactNode } from 'react';
import { tabOf, type Route, type TabGroup, type TabGroupId } from '../../core/domain/destinations';
import { Pressable } from '../kit';

/** A group heading's glyph, callout sized as the Mac's `SubNav` draws it. */
const GROUP_GLYPH = 14;

const GROUP_ICONS: Record<TabGroupId, LucideIcon> = {
  agents: Bot,
  computer: Monitor,
  projects: FolderGit2,
  knowledge: Brain,
  skills: Sparkles,
  hub: Plug,
  apps: AppWindow,
  review: Inbox,
  rules: ScrollText,
  record: History,
  account: UserRound,
  devices: Laptop,
  voice: Mic,
  app: AppWindow,
};

/**
 * A destination laid out as the console lays out its settings: the tree of tabs on the left under mono
 * headings, and one pane on the right under its own header. Below the container's breakpoint the tree
 * stacks above the pane, its groups flowing side by side, as the console's does under `lg`.
 */
export function SubNavFrame({
  title,
  groups,
  route,
  choose,
  children,
}: {
  title: string;
  groups: readonly TabGroup[];
  route: Route;
  choose: (tab: string) => void;
  children: ReactNode;
}) {
  const shown = tabOf(route);
  return (
    <div className="@container">
      <div className="grid grid-cols-[minmax(0,1fr)] gap-8 @3xl:grid-cols-(--mx-shell-sub-nav-columns)">
        <SubNav title={title} groups={groups} chosen={route.tab} choose={choose} />
        <div className="flex min-w-0 flex-col">
          {shown !== undefined && (
            <header className="mb-6">
              <p className="text-meta text-muted">{shown.group}</p>
              <h2 className="mt-1 text-2xl font-semibold tracking-[-0.02em] text-foreground">{shown.tab.title}</h2>
              <p className="mt-1.5 max-w-2xl text-body-sm leading-relaxed text-muted">{shown.tab.summary}</p>
            </header>
          )}
          <div className="flex min-w-0 flex-col gap-5">{children}</div>
        </div>
      </div>
    </div>
  );
}

/** The tree itself. Up and Down walk its rows, Home and End jump to either end, and Enter opens one. */
function SubNav({ title, groups, chosen, choose }: { title: string; groups: readonly TabGroup[]; chosen: string | undefined; choose: (tab: string) => void }) {
  const tree = useRef<HTMLElement>(null);
  const walk = (event: KeyboardEvent<HTMLElement>) => {
    const rows = [...(tree.current?.querySelectorAll<HTMLButtonElement>('button[data-tab]') ?? [])];
    const at = rows.findIndex((row) => row === document.activeElement);
    if (at < 0) return;
    const next = { ArrowDown: at + 1, ArrowUp: at - 1, Home: 0, End: rows.length - 1 }[event.key];
    if (next === undefined) return;
    event.preventDefault();
    rows[Math.min(Math.max(next, 0), rows.length - 1)]?.focus();
  };
  return (
    <nav ref={tree} aria-label={title} onKeyDown={walk} className="flex min-w-0 flex-col gap-6">
      <h2 className="text-2xl font-semibold tracking-[-0.02em] text-foreground">{title}</h2>
      <div className="grid grid-cols-(--mx-app-nav-groups) gap-6 @3xl:flex @3xl:flex-col">
        {groups.map((group) => {
          const Icon = GROUP_ICONS[group.id];
          return (
            <div key={group.id} className="flex flex-col gap-1">
              <p className="mb-1 flex items-center gap-2 px-3 text-label font-medium tracking-[0.18em] text-muted uppercase">
                <Icon size={GROUP_GLYPH} className="shrink-0" aria-hidden />
                {group.title}
              </p>
              {group.tabs.map((tab) => {
                const on = tab.id === chosen;
                return (
                  <Pressable
                    key={tab.id}
                    data-tab={tab.id}
                    aria-current={on ? 'page' : undefined}
                    title={tab.summary}
                    onClick={() => choose(tab.id)}
                    className={`mx-focus min-h-9 cursor-pointer rounded-lg px-3 py-2 text-left text-body-sm transition-colors ${
                      on ? 'bg-active font-medium text-foreground' : 'text-muted hover:bg-hover hover:text-foreground'
                    }`}
                  >
                    {tab.title}
                  </Pressable>
                );
              })}
            </div>
          );
        })}
      </div>
    </nav>
  );
}
