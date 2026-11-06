import { Pressable } from './Button';

/** One tab: its id, its name, and a count beside the name where the page has one to give. */
export interface TabItem<T extends string = string> {
  readonly id: T;
  readonly title: string;
  /** Left out where there is nothing to count, as on the tabs of a sidebar row. */
  readonly count?: number;
}

/** Each tab 12 across and 10 down, 13 medium, muted until chosen, over a 2 blue rule when chosen. */
const TAB = 'mx-focus -mb-px flex shrink-0 cursor-pointer items-center gap-1.5 border-b-2 px-3 py-2.5 text-body-sm font-medium whitespace-nowrap';
const tabState = (on: boolean) => (on ? 'border-primary text-foreground' : 'border-transparent text-muted');

/** `InspectorTabs`: the tabs inside one item's details, scrolling sideways where they run past the width. */
export function Tabs<T extends string>({ tabs, chosen, choose, label }: { tabs: readonly TabItem<T>[]; chosen: T; choose: (id: T) => void; label?: string }) {
  return (
    <div role="tablist" aria-label={label} className="flex min-w-0 flex-1 overflow-x-auto border-b border-panel-edge [scrollbar-width:none]">
      {tabs.map((each) => (
        <Pressable key={each.id} role="tab" aria-selected={each.id === chosen} onClick={() => choose(each.id)} className={`${TAB} ${tabState(each.id === chosen)}`}>
          {each.title}
        </Pressable>
      ))}
    </div>
  );
}

/** `CountTabs`: a page's tabs, each with its count 6 after it in the code face, 11 medium faint. */
export function CountTabs<T extends string>({ tabs, chosen, choose, label }: { tabs: readonly TabItem<T>[]; chosen: T; choose: (id: T) => void; label: string }) {
  return (
    <div role="tablist" aria-label={label} className="flex flex-wrap border-b border-panel-edge">
      {tabs.map((tab) => (
        <Pressable key={tab.id} role="tab" aria-selected={tab.id === chosen} onClick={() => choose(tab.id)} className={`${TAB} ${tabState(tab.id === chosen)}`}>
          {tab.title}
          {tab.count !== undefined && <span className="font-code text-label font-medium tabular-nums text-faint">{tab.count}</span>}
        </Pressable>
      ))}
    </div>
  );
}
