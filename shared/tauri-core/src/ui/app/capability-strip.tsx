import type { AgentConnection, CapabilityLevel, CapabilityLevels } from '../../core/domain/agent-wire';
import { connectionKindLine, connectionLevel, connectionStatusLine, LEVEL_WORDS, levelRows, levelTone, seamRows, type LevelRow } from '../../core/domain/capability-level-lines';
import { BrandLogo, StatusWord } from '../kit';

/** A level in its plain words and its colour, the same pill on every screen. */
export function LevelPill({ level }: { level: CapabilityLevel }) {
  return (
    <span title={level}>
      <StatusWord tone={levelTone(level)}>{LEVEL_WORDS[level]}</StatusWord>
    </span>
  );
}

/** A connection as a pill: who it is and how sure Memnox is through it. */
export function ConnectionPill({ connection }: { connection: AgentConnection }) {
  const who = connection.agentKind ?? connection.kind;
  return (
    <span className="inline-flex items-center gap-1.5" title={`${connectionKindLine(connection)}, ${connectionStatusLine(connection).toLowerCase()}`}>
      <BrandLogo agent={who} name={who} size={16} />
      <LevelPill level={connectionLevel(connection)} />
    </span>
  );
}

function Row({ row }: { row: LevelRow }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-body-sm text-foreground">{row.title}</span>
      <LevelPill level={row.level} />
    </div>
  );
}

/** How sure Memnox is of each thing an agent does, in plain words, with the technical names folded under Advanced. */
export function CapabilityStrip({ levels }: { levels: CapabilityLevels }) {
  const rows = [...levelRows(levels), ...seamRows(levels)];
  return (
    <div aria-label="How sure Memnox is" className="flex flex-col gap-1.5">
      {rows.map((each) => (
        <Row key={each.key} row={each} />
      ))}
      <details>
        <summary className="mx-focus cursor-pointer text-meta font-medium text-muted select-none">Advanced</summary>
        <div className="flex flex-col gap-0.5 pt-1">
          {rows.map((each) => (
            <code key={each.key} className="text-meta text-muted select-text">
              {each.technical}
            </code>
          ))}
        </div>
      </details>
    </div>
  );
}
