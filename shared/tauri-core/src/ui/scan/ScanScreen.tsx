import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { AgentNode } from '@memnox/core/wire';
import { agentColour } from '../../core';
import { agentStatus, connectionLines, reachLine, ringPoint, SCAN_TIMING, scanCountLabel, scanCapabilities, scanRing, scanTotals } from '../../core/domain/scan';
import { BrandLogo } from '../kit';
import { Orb } from '../Orb';
import { SYSTEM_MONO } from '../cards/MarkdownText';

type Phase = 'scanning' | 'found' | 'leaving';

/**
 * The scan, on the whole screen, from the Mac's `ScanOverlay`: Memnox in the middle with pulse rings,
 * each agent found in turn and set on a ring with its logo, a dotted line back to the middle, what it
 * reaches and what it is doing now, and the totals along the bottom. Always dark, since a light veil
 * would whiten the desktop. A click or Escape closes it, and it goes by itself after 25 s.
 */
export function ScanScreen({ agents, onClose, still = false }: { agents: readonly AgentNode[]; onClose: () => void; still?: boolean }) {
  const [size, setSize] = useState({ width: window.innerWidth, height: window.innerHeight });
  const [revealed, setRevealed] = useState(still ? agents.length : 0);
  const [phase, setPhase] = useState<Phase>(still ? 'found' : 'scanning');

  useLayoutEffect(() => {
    const resized = () => setSize({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener('resize', resized);
    return () => window.removeEventListener('resize', resized);
  }, []);

  // The sweep finds one agent a beat after the last, after a moment to warm up, then rests.
  useEffect(() => {
    if (still) return;
    setRevealed(0);
    setPhase('scanning');
    const timers = agents.map((_, index) => setTimeout(() => setRevealed(index + 1), SCAN_TIMING.warmUpMs + index * SCAN_TIMING.perAgentMs));
    timers.push(setTimeout(() => setPhase('found'), SCAN_TIMING.warmUpMs + agents.length * SCAN_TIMING.perAgentMs + 600));
    return () => timers.forEach(clearTimeout);
    // Keyed on the count, so a capability figure landing later updates the screen rather than sweeping again.
  }, [agents.length, still]);

  const leave = useRef(onClose);
  leave.current = onClose;
  useEffect(() => {
    const close = () => {
      setPhase('leaving');
      setTimeout(() => leave.current(), SCAN_TIMING.fadeOutMs + 50);
    };
    const escape = (event: KeyboardEvent) => event.key === 'Escape' && close();
    window.addEventListener('keydown', escape);
    const away = still ? undefined : setTimeout(close, SCAN_TIMING.showMs);
    (window as unknown as { closeScan?: () => void }).closeScan = close;
    return () => {
      window.removeEventListener('keydown', escape);
      if (away !== undefined) clearTimeout(away);
    };
  }, [still]);

  const centre = { x: size.width / 2, y: size.height / 2 + 10 };
  // On a short screen the ring flattens, so the top card clears the heading and the bottom one the totals.
  const HEADING_TOP = 90;
  const HEADING_HEIGHT = 110;
  const CARD_HALF = 100;
  const fit = scanRing(size);
  const ring = { width: fit.width, height: Math.max(80, Math.min(fit.height, centre.y - HEADING_TOP - HEADING_HEIGHT - CARD_HALF)) };
  const found = phase !== 'scanning';
  const totals = scanTotals(agents);

  return (
    <div
      className="fixed inset-0 cursor-pointer overflow-hidden font-sans text-white transition-[opacity,scale,filter] duration-[350ms] ease-in"
      style={{ opacity: phase === 'leaving' ? 0 : 1, scale: phase === 'leaving' ? '1.03' : '1', filter: phase === 'leaving' ? 'blur(6px)' : 'none' }}
      onClick={() => (window as unknown as { closeScan?: () => void }).closeScan?.()}
      role="dialog"
      aria-label="Scan of the agents on this computer"
    >
      <div className="absolute inset-0 bg-black/90 backdrop-blur-2xl" />
      {/* A dot grid every 34, the dots 1.4 in white 8%, at 45%. */}
      <div className="absolute inset-0 opacity-45" style={{ backgroundImage: 'radial-gradient(circle, rgb(255 255 255 / 0.08) 0.7px, transparent 0.8px)', backgroundSize: '34px 34px' }} />
      <svg className="absolute inset-0" width={size.width} height={size.height} aria-hidden>
        {agents.slice(0, revealed).map((agent, index) => {
          const point = ringPoint(index, agents.length, centre, ring);
          const length = Math.hypot(point.x - centre.x, point.y - centre.y);
          return (
            <g key={agent.id}>
              <line
                x1={centre.x}
                y1={centre.y}
                x2={point.x}
                y2={point.y}
                stroke={agentColour(agent.kind)}
                strokeOpacity={0.55}
                strokeWidth={1.2}
                strokeDasharray="2 5"
                style={{ animation: 'fade-in 550ms ease-out both' }}
              />
              {agent.working > 0 && (
                <circle r={3} fill={agentColour(agent.kind)} style={{ filter: `drop-shadow(0 0 8px ${agentColour(agent.kind)})`, offsetPath: `path('M ${centre.x} ${centre.y} L ${point.x} ${point.y}')`, animation: `scan-light 1.6s linear infinite`, ['--len' as string]: length }} />
              )}
            </g>
          );
        })}
      </svg>
      {/* Three pulse rings in the blue behind the orb, a lap of 2.4 s each, 0.8 s apart. */}
      {[0, 1, 2].map((wave) => (
        <span
          key={wave}
          className="pointer-events-none absolute size-[200px] -translate-x-1/2 -translate-y-1/2 rounded-full border border-primary"
          style={{ left: centre.x, top: centre.y, ['--ring-opacity' as string]: found ? 0.12 : 0.45, animation: `scan-ring 2.4s ease-out ${wave * 0.8}s infinite both` }}
        />
      ))}
      <div className="pointer-events-none absolute" style={{ left: 0, top: 0 }}>
        <Orb x={centre.x} y={centre.y} diameter={200 * 0.62} state={found ? 'idle' : 'thinking'} waiting={false} loudness={() => 0} />
      </div>
      <Heading found={found} count={revealed} total={agents.length} top={Math.max(HEADING_TOP, centre.y - ring.height - CARD_HALF - HEADING_HEIGHT - 50)} />
      {agents.slice(0, revealed).map((agent, index) => {
        const point = ringPoint(index, agents.length, centre, ring);
        return <AgentCard key={agent.id} agent={agent} x={point.x} y={point.y} />;
      })}
      <Summary shown={found} totals={totals} capabilities={scanCapabilities(agents)} bottom={70} />
    </div>
  );
}

/** The badge and the count over the ring. */
function Heading({ found, count, total, top }: { found: boolean; count: number; total: number; top: number }) {
  return (
    <div className="pointer-events-none absolute inset-x-0 flex flex-col items-center gap-2.5" style={{ top, animation: 'pill-in 500ms ease-out both' }}>
      <span className="flex items-center gap-2 rounded-full bg-white/[0.07] px-3 py-1.5">
        <span className={`size-[7px] rounded-full ${found ? 'bg-green' : 'bg-island-sky'}`} />
        <span className="text-footnote font-semibold text-white/70">{found ? 'Scan complete' : 'Scanning this computer'}</span>
      </span>
      <span className="flex items-baseline gap-3">
        <span className="tabular font-display text-[58px] font-semibold leading-none text-white">{count}</span>
        <span className="font-display text-[28px] font-semibold text-white/80">{scanCountLabel(total)}</span>
      </span>
    </div>
  );
}

/** One agent on the ring: 230 wide, its logo, name, reach, connections and status, on a rimmed surface. */
function AgentCard({ agent, x, y }: { agent: AgentNode; x: number; y: number }) {
  const status = agentStatus(agent);
  const tone = status?.tone === 'green' ? '#30d158' : status?.tone === 'amber' ? '#ff9f0a' : undefined;
  return (
    <div
      className="pointer-events-none absolute flex w-[230px] -translate-x-1/2 -translate-y-1/2 flex-col gap-2 rounded-island bg-[#28282b] p-3"
      style={{
        left: x,
        top: y,
        boxShadow: `0 10px 40px rgb(0 0 0 / 0.5), inset 0 0 0 ${tone === undefined ? 0.7 : 1}px ${tone === undefined ? 'rgb(255 255 255 / 0.11)' : `${tone}99`}`,
        animation: 'scan-card-in 550ms cubic-bezier(0.34, 1.35, 0.64, 1) both',
      }}
    >
      <div className="flex items-center gap-2.5">
        <BrandLogo agent={agent.kind} name={agent.name} size={36} />
        <div className="flex min-w-0 flex-col gap-px">
          <span className="truncate text-headline font-semibold text-white">{agent.name}</span>
          <span className="truncate text-caption text-white/[0.62]">{reachLine(agent)}</span>
        </div>
      </div>
      {connectionLines(agent).map((line) => (
        <span key={line} className={`truncate whitespace-pre ${SYSTEM_MONO} text-caption text-white/70`}>
          {line}
        </span>
      ))}
      {status !== undefined && tone !== undefined && (
        <span className="flex items-center gap-1.5 self-start rounded-full px-[9px] py-[3px] text-caption font-medium" style={{ color: tone, backgroundColor: `${tone}24` }}>
          <span className="size-1.5 rounded-full" style={{ backgroundColor: tone }} />
          {status.text}
        </span>
      )}
    </div>
  );
}

/** A figure that counts up once the scan is done. */
function Figure({ value, label, tint = 'text-white', shown }: { value: number | undefined; label: string; tint?: string; shown: boolean }) {
  const [now, setNow] = useState(0);
  useEffect(() => {
    if (!shown || value === undefined) return;
    let frame = 0;
    const begin = performance.now() + SCAN_TIMING.countUpDelayMs;
    const step = (time: number) => {
      const progress = Math.min(1, Math.max(0, (time - begin) / SCAN_TIMING.countUpMs));
      setNow(Math.round(value * (1 - (1 - progress) ** 3)));
      if (progress < 1) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [shown, value]);
  return (
    <span className="flex items-baseline gap-1.5">
      {/* Not counted yet reads as counting, never as a zero. */}
      <span className={`tabular text-title font-semibold ${tint}`}>{value === undefined ? 'counting' : shown ? now : 0}</span>
      <span className="text-footnote text-white/55">{label}</span>
    </span>
  );
}

/** The totals along the bottom in the island's own black pill. */
function Summary({ shown, totals, capabilities, bottom }: { shown: boolean; totals: ReturnType<typeof scanTotals>; capabilities: number | undefined; bottom: number }) {
  return (
    <div
      className="pointer-events-none absolute left-1/2 flex items-center gap-[22px] rounded-full bg-black px-[22px] py-3 shadow-[0_10px_48px_rgb(0_0_0/0.6)] transition-[opacity,translate] duration-[550ms] ease-[cubic-bezier(0.34,1.45,0.64,1)]"
      style={{ bottom, opacity: shown ? 1 : 0, translate: shown ? '-50% 0' : '-50% 24px', boxShadow: '0 10px 48px rgb(0 0 0 / 0.6), inset 0 0 0 1px rgb(255 255 255 / 0.08)' }}
    >
      <Figure value={totals.agents} label="agents" shown={shown} />
      <Figure value={totals.tools} label="MCP tools" shown={shown} />
      <Figure value={capabilities} label="real capabilities" tint="text-amber" shown={shown} />
      <Figure value={totals.working} label="working" tint="text-green" shown={shown} />
      <span className="h-[22px] w-px bg-white/10" />
      <span className="flex items-center gap-1.5">
        <span className="grid h-[18px] min-w-[18px] place-items-center rounded-key bg-[#454545] px-1.5 text-caption font-medium text-[#e1e1e1]">esc</span>
        <span className="text-caption text-white/50">or click to close</span>
      </span>
    </div>
  );
}
