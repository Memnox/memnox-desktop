import { useState } from 'react';
import { agentColour, agentInitial, agentLogo, hasOwnMark, toolkitName, toolLook } from '../../core';

/**
 * The logos every window draws: an agent's own, a tool's mark, and Memnox's. The files are the Mac's
 * own, from `macos/Support/AgentLogos` and `ToolLogos`, so both apps wear the same marks.
 */

/** Each agent logo file, by the name `agentLogo` gives it; Vite turns each into a served URL. */
const AGENT_FILES: Record<string, string> = {
  claude: new URL('../assets/agents/claude.svg', import.meta.url).href,
  cursor: new URL('../assets/agents/cursor.svg', import.meta.url).href,
  openai: new URL('../assets/agents/openai.svg', import.meta.url).href,
  hermes: new URL('../assets/agents/hermes.webp', import.meta.url).href,
  openclaw: new URL('../assets/agents/openclaw.webp', import.meta.url).href,
  cline: new URL('../assets/agents/cline.webp', import.meta.url).href,
  antigravity: new URL('../assets/agents/antigravity.svg', import.meta.url).href,
  copilot: new URL('../assets/agents/copilot.svg', import.meta.url).href,
  opencode: new URL('../assets/agents/opencode.svg', import.meta.url).href,
};

/** Each tool's bundled mark, a one colour glyph drawn white on the tool's own colour. */
const TOOL_FILES: Record<string, string> = {
  slack: new URL('../assets/tools/slack.svg', import.meta.url).href,
  github: new URL('../assets/tools/github.svg', import.meta.url).href,
  linear: new URL('../assets/tools/linear.svg', import.meta.url).href,
  gmail: new URL('../assets/tools/gmail.svg', import.meta.url).href,
  googledocs: new URL('../assets/tools/googledocs.svg', import.meta.url).href,
  notion: new URL('../assets/tools/notion.svg', import.meta.url).href,
};

/** Memnox's own mark in white, for the menu panel's header and the answer's disc. */
export const MEMNOX_MARK = new URL('../assets/memnox-mark-white.png', import.meta.url).href;
/** The name set in the brand's own letters, the Mac's `memnox-wordmark-template`, drawn in whatever ink the surface asks for. */
export const MEMNOX_WORDMARK = new URL('../assets/memnox-wordmark-template.png', import.meta.url).href;
/** The wordmark's own shape, 576 by 94, so its width follows whatever height it is given. */
const WORDMARK_ASPECT = 576 / 94;

/** The URL of an agent's own logo, or undefined where it has none. */
export function agentLogoUrl(agent: string | undefined): string | undefined {
  const file = agentLogo(agent);
  return file === undefined ? undefined : AGENT_FILES[file];
}

/** The logo by the agent's kind, else by the name it is shown under, since some rows carry an id the files do not know. */
function logoOf(agent: string | undefined, name: string | undefined): string | undefined {
  return agentLogoUrl(agent) ?? agentLogoUrl(name);
}

/** A tile rounds like an app icon, about a quarter of its side. */
const CORNER_SHARE = 0.26;

/**
 * `BrandLogo`: an agent's logo exactly as its brand ships it, filling a rounded tile with a 1 px rim of
 * ink 14%. Without one, its initial at 46% of the side, semibold rounded, in its colour on the grey.
 */
export function BrandLogo({ agent, name, size = 28, className }: { agent: string | undefined; name: string; size?: number; className?: string }) {
  const url = logoOf(agent, name);
  return (
    <span
      className={`relative grid shrink-0 place-items-center overflow-hidden ${className ?? ''}`}
      style={{ width: size, height: size, borderRadius: size * CORNER_SHARE, backgroundColor: url === undefined ? 'var(--mx-secondary, #383838)' : undefined }}
      role="img"
      aria-label={name}
    >
      {url !== undefined ? (
        <img src={url} alt="" className="size-full object-cover" draggable={false} />
      ) : (
        <span className="font-rounded font-semibold leading-none" style={{ fontSize: size * 0.46, color: agentColour(agent ?? name) }}>
          {agentInitial(name)}
        </span>
      )}
      <span className="pointer-events-none absolute inset-0 rounded-[inherit]" style={{ boxShadow: 'inset 0 0 0 1px var(--mx-ink-edge, rgb(255 255 255 / 0.14))' }} />
    </span>
  );
}

/**
 * `AgentMark`: the agent's logo at 58% of the side on a tile of its own colour, as the connected strip
 * and the tools grid draw an agent beside the apps.
 */
export function AgentMark({ agent, name, size = 26 }: { agent: string | undefined; name: string; size?: number }) {
  const url = logoOf(agent, name);
  return (
    <span className="grid shrink-0 place-items-center overflow-hidden" style={{ width: size, height: size, borderRadius: size * CORNER_SHARE, backgroundColor: agentColour(agent ?? name) }} role="img" aria-label={name}>
      {url !== undefined ? (
        <img src={url} alt="" className="object-contain" style={{ width: size * 0.58, height: size * 0.58, borderRadius: size * 0.1 }} draggable={false} />
      ) : (
        <span className="font-semibold leading-none text-white" style={{ fontSize: size * 0.46 }}>
          {agentInitial(name)}
        </span>
      )}
    </span>
  );
}

/**
 * `SessionLogo` inside the island: the agent's logo on a disc, ringed in black so overlapping discs stay
 * apart, or its initial on its colour. The disc is light so every brand file reads on the black notch.
 */
export function SessionDisc({ agent, name, size = 16, ring = 1.5 }: { agent: string | undefined; name?: string; size?: number; ring?: number }) {
  const url = logoOf(agent, name);
  return (
    <span
      className="grid shrink-0 place-items-center overflow-hidden rounded-full"
      style={{ width: size, height: size, backgroundColor: url === undefined ? agentColour(agent) : '#fff', boxShadow: `0 0 0 ${ring}px #000` }}
      aria-hidden
    >
      {url !== undefined ? (
        <img src={url} alt="" className="size-full object-cover" draggable={false} />
      ) : (
        <span className="font-bold leading-none text-black" style={{ fontSize: size * 0.5 }}>
          {agentInitial(name ?? agent ?? '')}
        </span>
      )}
    </span>
  );
}

/**
 * `AgentName`: an agent's name inline in a line of text with its logo just before it, for the places a
 * name sits in a sentence or a list rather than in a row of its own.
 */
export function AgentName({ agent, name, size = 14, className }: { agent: string | undefined; name: string; size?: number; className?: string }) {
  return (
    <span className={`inline-flex items-center gap-1 align-middle ${className ?? ''}`}>
      <BrandLogo agent={agent} name={name} size={size} />
      {name}
    </span>
  );
}

/** `AgentLogos`: several agents' logos overlapped in a row, ahead of a line that names them together. */
export function AgentLogos({ agents, size = 16 }: { agents: readonly { agent: string; name: string }[]; size?: number }) {
  if (agents.length === 0) return null;
  return (
    <span className="inline-flex shrink-0 -space-x-1 align-middle">
      {agents.map((each) => (
        <BrandLogo key={each.agent} agent={each.agent} name={each.name} size={size} className="ring-2 ring-card" />
      ))}
    </span>
  );
}

/** Composio's logo address for a toolkit slug, the one its catalogue hands back as the toolkit's logo. */
const COMPOSIO_LOGOS = 'https://logos.composio.dev/api/';
/** Slugs that failed once are not asked for again, so a missing logo never costs a request per redraw. */
const missingLogos = new Set<string>();
/** Logos that arrived, so a mark drawn again starts with its logo rather than the fallback. */
const arrivedLogos = new Set<string>();

/**
 * `ToolMark`: a tool's Composio logo in its own colours on a white tile, as an app icon sits; until it
 * arrives, or where Composio has none, the bundled mark white on the tool's colour, or its initial.
 * `online` false keeps it to the bundled marks, as the preview does with no network.
 */
export function ToolMark({ toolkit, size = 22, online = true, className }: { toolkit: string; size?: number; online?: boolean; className?: string }) {
  const [, rerender] = useState(0);
  const remote = online && !missingLogos.has(toolkit);
  const arrived = arrivedLogos.has(toolkit);
  const bundled = TOOL_FILES[toolkit];
  const radius = size * CORNER_SHARE;
  return (
    <span
      className={`relative grid shrink-0 place-items-center overflow-hidden ${className ?? ''}`}
      style={{ width: size, height: size, borderRadius: radius, backgroundColor: arrived ? '#fff' : toolLook(toolkit).colour }}
      role="img"
      aria-label={toolkitName(toolkit)}
    >
      {!arrived &&
        (bundled !== undefined && hasOwnMark(toolkit) ? (
          <span
            className="block bg-white"
            style={{ width: size * 0.58, height: size * 0.58, mask: `url("${bundled}") center / contain no-repeat`, WebkitMask: `url("${bundled}") center / contain no-repeat` }}
          />
        ) : (
          <span className="font-bold leading-none text-white" style={{ fontSize: size * 0.58 }}>
            {toolkitName(toolkit).charAt(0)}
          </span>
        ))}
      {remote && (
        <img
          src={`${COMPOSIO_LOGOS}${encodeURIComponent(toolkit)}`}
          alt=""
          draggable={false}
          className={arrived ? 'object-contain' : 'absolute size-0 opacity-0'}
          style={arrived ? { width: size * 0.72, height: size * 0.72 } : undefined}
          onLoad={() => {
            if (arrivedLogos.has(toolkit)) return;
            arrivedLogos.add(toolkit);
            rerender((n) => n + 1);
          }}
          onError={() => {
            missingLogos.add(toolkit);
            rerender((n) => n + 1);
          }}
        />
      )}
    </span>
  );
}

/** Memnox's mark as a template in the colour of the words around it, as the Mac draws its mark in `ink`. */
export function LogoMark({ size = 24, className }: { size?: number; className?: string }) {
  const mask = `url("${MEMNOX_MARK}") center / contain no-repeat`;
  return <span className={`inline-block shrink-0 bg-current ${className ?? ''}`} style={{ width: size, height: size, mask, WebkitMask: mask }} aria-hidden />;
}

/** The wordmark in flat ink, as the Mac's `Wordmark`: the sidebar's top and the first screen, wherever the name is shown. */
export function Wordmark({ height, className }: { height: number | string; className?: string }) {
  const mask = `url("${MEMNOX_WORDMARK}") center / contain no-repeat`;
  return <span role="img" aria-label="Memnox" className={`inline-block shrink-0 bg-current ${className ?? ''}`} style={{ height, aspectRatio: WORDMARK_ASPECT, mask, WebkitMask: mask }} />;
}
