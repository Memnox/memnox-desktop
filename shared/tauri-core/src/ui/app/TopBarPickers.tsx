import { ALL_PROJECTS, SCOPE_CHOICES, SCOPE_LABEL, SWITCHER_LABEL, type ShownScope } from '../../core/domain/shell-lines';
import type { WidthClass } from '../../core/domain/destinations';
import { SelectMenu } from '../settings/kit';
import { useShellChoices } from './shell-choices';

/** The value the switcher keeps for every project, which no project id can be. */
const EVERY_PROJECT = '';
/** Wide enough for a project's name, narrow enough to leave the title room. */
const SWITCHER_WIDTH = 168;
const SWITCHER_WIDTH_COMPACT = 120;

/**
 * The workspace switcher and, once an organization handed anything down, the scope selector. The switcher shows
 * only where this computer's runtime keeps projects and no project is open; the selector only where there is an organization to show.
 */
export function TopBarPickers({ width, inProject = false }: { width: WidthClass; inProject?: boolean }) {
  const choices = useShellChoices();
  const projects = choices.projects;
  return (
    <>
      {choices.connected && (
        <div role="radiogroup" aria-label={SCOPE_LABEL} className="flex h-7 shrink-0 items-center rounded-full border border-control-edge bg-secondary p-0.5">
          {SCOPE_CHOICES.map((each) => (
            <ScopeButton key={each.scope} scope={each.scope} title={each.title} on={choices.scope === each.scope} choose={choices.chooseScope} />
          ))}
        </div>
      )}
      {/* Inside a project its sidebar's own switcher moves between projects, so the bar holds no second one. */}
      {!inProject && projects !== undefined && projects.length > 0 && (
        <SelectMenu
          value={choices.project?.id ?? EVERY_PROJECT}
          label={SWITCHER_LABEL}
          width={width === 'compact' ? SWITCHER_WIDTH_COMPACT : SWITCHER_WIDTH}
          options={[{ value: EVERY_PROJECT, label: ALL_PROJECTS }, ...projects.map((project) => ({ value: project.id, label: project.name }))]}
          onChange={(id) => choices.chooseProject(id === EVERY_PROJECT ? undefined : id)}
        />
      )}
    </>
  );
}

function ScopeButton({ scope, title, on, choose }: { scope: ShownScope; title: string; on: boolean; choose: (scope: ShownScope) => void }) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={on}
      onClick={() => choose(scope)}
      className={`mx-focus h-6 cursor-pointer rounded-full px-2.5 text-footnote ${on ? 'bg-background font-medium text-foreground' : 'text-muted hover:text-foreground'}`}
    >
      {title}
    </button>
  );
}
