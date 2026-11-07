import { AppWindow, Code2, MessagesSquare, Puzzle, SquareTerminal } from 'lucide-react';
import { Fragment, useEffect } from 'react';
import { AGENT_HOMES, AgentHomesLines, CLAUDE_EXTENSION_PAGE, homeReady, type FoundHome } from '../../../core/domain/agent-homes';
import type { AgentHomes } from '../../../core/application/agent-homes';
import type { Platform } from '../../../core/domain/platform';
import { DONE, WAITING } from '../../../core/domain/step-state';
import { Button } from '../../kit';
import { AppTile, AppTileGrid, KitCard, KitDivider, KitRow, StatusMark } from '../kit';
import { useObserved } from '../parts';

/** Often enough that an extension landing ticks without pressing anything, as the Mac's step looks every 2 seconds. */
const LOOK_EVERY_MS = 2_000;

/**
 * The picker and the chosen app's checklist, as the Mac's `AgentHomesSetup`: every terminal and the editor here as a
 * tile, the one a session opens in ticked, then what it still needs. The Mac's Automation and Accessibility rows are
 * left out, since Windows and Linux ask for neither.
 */
export function AgentHomesSetup({ homes, platform }: { homes: AgentHomes; platform: Platform }) {
  useObserved(homes);
  useEffect(() => {
    void homes.look();
    const timer = setInterval(() => void homes.look(), LOOK_EVERY_MS);
    return () => clearInterval(timer);
  }, []);
  const found = homes.found ?? [];
  const chosen = found.find((each) => each.kind === homes.chosen);
  const ready = chosen !== undefined && homeReady(chosen, homes.chatOpened(chosen.kind)) ? 1 : 0;
  return (
    <div className="flex flex-col gap-4">
      <KitCard icon={AppWindow} title={AgentHomesLines.yourApps} detail={AgentHomesLines.picked(chosen === undefined ? 0 : 1, ready)}>
        {found.length === 0 ? (
          <KitRow icon={AppWindow} title={AgentHomesLines.noneTitle} detail={AgentHomesLines.noneDetail(platform)} />
        ) : (
          <AppTileGrid>
            {found.map((each) => (
              <AppTile
                key={each.kind}
                icon={AGENT_HOMES[each.kind].editor ? Code2 : SquareTerminal}
                name={AGENT_HOMES[each.kind].name}
                chosen={each.kind === homes.chosen}
                hint={each.kind === homes.chosen ? AgentHomesLines.chosenHint : AgentHomesLines.otherHint}
                choose={() => homes.toggle(each.kind)}
              />
            ))}
          </AppTileGrid>
        )}
      </KitCard>
      {chosen !== undefined && <HomeCard homes={homes} home={chosen} />}
    </div>
  );
}

/** The chosen app's checklist: for the editor its extension and the chat link; a terminal here needs nothing more. */
function HomeCard({ homes, home }: { homes: AgentHomes; home: FoundHome }) {
  const { name, editor } = AGENT_HOMES[home.kind];
  const ready = homeReady(home, homes.chatOpened(home.kind));
  return (
    <KitCard icon={editor ? Code2 : SquareTerminal} title={name} detail={ready ? AgentHomesLines.ready : AgentHomesLines.editorSummary}>
      {editor && (
        <Fragment>
          <KitRow icon={Puzzle} title={AgentHomesLines.extension} detail={home.memnoxExtension === true ? AgentHomesLines.extensionIn : AgentHomesLines.extensionComing}>
            <StatusMark state={home.memnoxExtension === true ? DONE : WAITING} />
          </KitRow>
          <KitDivider />
          <ChatRow homes={homes} home={home} name={name} />
        </Fragment>
      )}
    </KitCard>
  );
}

/** Claude Code's chat, opened by the link every follow up uses, which the editor asks about the first time. */
function ChatRow({ homes, home, name }: { homes: AgentHomes; home: FoundHome; name: string }) {
  if (home.claudeCode !== true) {
    return (
      <KitRow icon={MessagesSquare} title={AgentHomesLines.claudeIn(name)} detail={AgentHomesLines.claudeMissing}>
        <Button onClick={() => homes.open(CLAUDE_EXTENSION_PAGE)}>{AgentHomesLines.getIt}</Button>
      </KitRow>
    );
  }
  if (homes.isTrying(home.kind)) {
    return (
      <KitRow icon={MessagesSquare} title={AgentHomesLines.didChatOpen} detail={AgentHomesLines.didChatOpenDetail(name)}>
        <Button onClick={() => homes.chatCameUp(home.kind, false)}>{AgentHomesLines.notYet}</Button>
        <Button kind="primary" onClick={() => homes.chatCameUp(home.kind, true)}>
          {AgentHomesLines.itOpened}
        </Button>
      </KitRow>
    );
  }
  const opened = homes.chatOpened(home.kind);
  return (
    <KitRow icon={MessagesSquare} title={AgentHomesLines.openChats} detail={opened ? AgentHomesLines.chatsOpen : AgentHomesLines.chatsAsk(name)}>
      {opened ? (
        <StatusMark state={DONE} />
      ) : (
        <Button kind="primary" onClick={() => homes.tryChat(home.kind)}>
          {AgentHomesLines.tryIt}
        </Button>
      )}
    </KitRow>
  );
}
