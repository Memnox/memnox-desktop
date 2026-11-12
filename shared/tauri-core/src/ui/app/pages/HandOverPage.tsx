import { Gauge } from 'lucide-react';
import { useEffect } from 'react';
import { HOME_BRIEF_NONE, HOME_BRIEF_TITLE } from '../../../core/domain/home-brief';
import { HomeLines } from '../../../core/domain/home-lines';
import { useObserved, type SettingsParts } from '../../settings/parts';
import { Button, EmptyState, Note, Section } from '../../kit';

/** The button's words while the rule is being proposed and before, as the Mac's ready card says them. */
const HAND_OVER = 'Let it run on its own';
const PROPOSING = 'Proposing the rule';

/**
 * Hand over: the one action people keep saying yes to, offered as a rule that lets it run on its own, as the Mac's
 * `HandOverDestination` does. Budgets and autopilot join it as tabs once the runtime answers them.
 */
export function HandOverPage({ parts }: { parts: SettingsParts }) {
  const { home, words } = parts;
  useObserved(home);
  useEffect(() => {
    void home.refresh();
  }, []);
  const ready = home.home?.ready;
  if (ready === undefined) return <EmptyState icon={Gauge} title={HOME_BRIEF_TITLE.ready} body={HOME_BRIEF_NONE.ready} />;
  return (
    <Section title={HOME_BRIEF_TITLE.ready}>
      <div className="flex flex-col gap-3 rounded-card border border-panel-edge bg-card p-5">
        <p className="text-headline font-semibold text-foreground">{HomeLines.ready(ready)}</p>
        {ready.targets.map((target) => (
          <p key={target} className="truncate font-mono text-footnote text-foreground">
            {target}
          </p>
        ))}
        <p className="text-footnote text-muted">{ready.because}</p>
        <div className="flex items-center gap-3">
          <Button kind="primary" disabled={home.handingOver} onClick={() => void home.handOver(ready, words.keyTitle)}>
            {home.handingOver ? PROPOSING : HAND_OVER}
          </Button>
          {home.handOverNote !== undefined && <Note>{home.handOverNote}</Note>}
        </div>
      </div>
    </Section>
  );
}
