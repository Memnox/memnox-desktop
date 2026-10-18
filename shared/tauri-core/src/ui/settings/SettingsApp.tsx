import { ChevronDown, ChevronRight, CircleHelp, CirclePower, CircleUserRound, Contrast, Ear, House, Keyboard, LayoutGrid, ShieldCheck, Smartphone, Speech, type LucideIcon } from 'lucide-react';
import { useEffect, useReducer, useRef, useState, type ReactNode } from 'react';
import { matchingPages, PageHistory, pageInfo, pageNamed, SETTINGS_GROUPS, type SettingsPage } from '../../core/domain/settings-pages';
import { NavigationCapsule, PageTitle, SearchField } from './kit';
import { AccountPage } from './pages/AccountPage';
import { HelpPage } from './pages/HelpPage';
import { OverviewPage } from './pages/OverviewPage';
import { AppearancePage, ConnectionPage, PermissionsPage, PhonesPage } from './pages/ComputerPages';
import { ToolsPage } from './pages/ToolsPage';
import { DictationPage, ListeningPage, VoicePage } from './pages/VoicePages';
import { useLook, type SettingsParts } from './parts';

/** Each page's symbol, the lucide stand in for the Mac's SF Symbol. */
const ICONS: Record<SettingsPage, LucideIcon> = {
  overview: House,
  account: CircleUserRound,
  permissions: ShieldCheck,
  connection: CirclePower,
  phones: Smartphone,
  appearance: Contrast,
  tools: LayoutGrid,
  voice: Speech,
  listening: Ear,
  dictation: Keyboard,
  help: CircleHelp,
};

/**
 * The Settings window, as the Mac's `SettingsView` lays it out: a 243 wide sidebar on the window's own
 * ground with search and folding groups, then the page on a solid panel inset 8, under a header holding
 * Back and Forward and the page's title. Escape closes it; Ctrl [ and Ctrl ] go back and forward.
 */
export function SettingsApp({ parts, first }: { parts: SettingsParts; first?: SettingsPage }) {
  useLook(parts.preferences);
  const history = useRef(new PageHistory(first ?? 'overview')).current;
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  const [query, setQuery] = useState('');
  const [folded, setFolded] = useState<ReadonlySet<string>>(new Set());
  const page = history.current;

  const go = (next: SettingsPage) => {
    history.visit(next);
    redraw();
  };

  useEffect(() => parts.host.onShowPage((name) => {
    const named = pageNamed(name);
    if (named !== undefined) go(named);
  }), []);

  useEffect(() => {
    const keys = (event: KeyboardEvent) => {
      if (event.key === 'Escape') parts.host.close();
      const backKey = (event.ctrlKey && event.key === '[') || (event.altKey && event.key === 'ArrowLeft');
      const forwardKey = (event.ctrlKey && event.key === ']') || (event.altKey && event.key === 'ArrowRight');
      if (backKey) {
        history.back();
        redraw();
      }
      if (forwardKey) {
        history.forward();
        redraw();
      }
    };
    window.addEventListener('keydown', keys);
    return () => window.removeEventListener('keydown', keys);
  }, []);

  const info = pageInfo(page);
  return (
    <div className="flex h-full bg-surface text-foreground">
      <aside className="flex w-[243px] shrink-0 flex-col">
        <div className="px-[9px] pt-3 pb-[9px]">
          <SearchField value={query} placeholder="Search settings" onChange={setQuery} />
        </div>
        <nav className="flex-1 overflow-y-auto px-[9px] pb-[9px] [scrollbar-width:none]">
          {query.trim() !== ''
            ? matchingPages(query).map((each) => <SidebarRow key={each} page={each} chosen={each === page} go={go} />)
            : SETTINGS_GROUPS.map((group) => (
                <div key={group.title ?? 'top'}>
                  {group.title !== undefined && (
                    <GroupHeader
                      title={group.title}
                      open={!folded.has(group.title)}
                      toggle={() => {
                        const next = new Set(folded);
                        if (next.has(group.title ?? '')) next.delete(group.title ?? '');
                        else next.add(group.title ?? '');
                        setFolded(next);
                      }}
                    />
                  )}
                  {!folded.has(group.title ?? '') && group.pages.map((each) => <SidebarRow key={each} page={each} chosen={each === page} go={go} />)}
                </div>
              ))}
        </nav>
      </aside>
      <main className="my-2 mr-2 flex min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-panel-edge bg-background">
        <header className="flex h-11 shrink-0 items-center gap-[13px] pl-[19px]">
          <NavigationCapsule
            canBack={history.canGoBack}
            canForward={history.canGoForward}
            back={() => {
              history.back();
              redraw();
            }}
            forward={() => {
              history.forward();
              redraw();
            }}
          />
          <span className="truncate text-headline font-semibold text-foreground">{info.title}</span>
        </header>
        <div className="flex-1 overflow-y-auto [scrollbar-width:none]">
          <div key={page} className="mx-auto flex max-w-[760px] flex-col gap-5 px-[22px] pt-2 pb-[22px]">
            {page !== 'overview' && <PageTitle title={info.title} subtitle={info.subtitle} />}
            <PageBody page={page} parts={parts} go={go} />
          </div>
        </div>
      </main>
    </div>
  );
}

function PageBody({ page, parts, go }: { page: SettingsPage; parts: SettingsParts; go: (page: SettingsPage) => void }): ReactNode {
  switch (page) {
    case 'overview':
      return <OverviewPage parts={parts} go={go} />;
    case 'account':
      return <AccountPage parts={parts} />;
    case 'permissions':
      return <PermissionsPage parts={parts} />;
    case 'connection':
      return <ConnectionPage parts={parts} />;
    case 'phones':
      return <PhonesPage parts={parts} />;
    case 'appearance':
      return <AppearancePage parts={parts} />;
    case 'tools':
      return <ToolsPage parts={parts} />;
    case 'voice':
      return <VoicePage parts={parts} />;
    case 'listening':
      return <ListeningPage parts={parts} />;
    case 'dictation':
      return <DictationPage parts={parts} />;
    case 'help':
      return <HelpPage parts={parts} />;
  }
}

/** A sidebar row: 30 tall, the icon in an 18 column, 9 to the label; chosen is white on the blue. */
function SidebarRow({ page, chosen, go }: { page: SettingsPage; chosen: boolean; go: (page: SettingsPage) => void }) {
  const Icon = ICONS[page];
  const info = pageInfo(page);
  return (
    <button
      type="button"
      className={`flex h-[30px] w-full cursor-pointer items-center gap-[9px] rounded-lg px-2.5 text-left text-body transition-colors duration-200 ${chosen ? 'bg-primary font-medium text-white' : 'text-foreground hover:bg-hover'}`}
      onClick={() => go(page)}
      title={info.subtitle}
      aria-current={chosen ? 'page' : undefined}
    >
      <span className={`grid w-[18px] shrink-0 place-items-center ${chosen ? 'text-white' : 'text-primary'}`}>
        <Icon size={14} strokeWidth={1.9} />
      </span>
      <span className="truncate">{info.title}</span>
    </button>
  );
}

/** A group's name, 12 semibold in the faint colour, with a chevron that folds it. */
function GroupHeader({ title, open, toggle }: { title: string; open: boolean; toggle: () => void }) {
  const Chevron = open ? ChevronDown : ChevronRight;
  return (
    <button type="button" className="flex w-full cursor-pointer items-center gap-1.5 px-1.5 pt-3.5 pb-1 text-footnote font-semibold text-faint" onClick={toggle} aria-expanded={open}>
      <span className="grid w-3 place-items-center">
        <Chevron size={10} strokeWidth={3} />
      </span>
      {title}
    </button>
  );
}
