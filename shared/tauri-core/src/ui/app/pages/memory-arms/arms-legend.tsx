import { Check, Eye, EyeOff } from "lucide-react";

import { Pressable } from "../../../kit";
import { BrainLegendLines, layerWord } from "../../../../core/domain/memory-brain-lines";
import type { LegendLayer } from "../../../../core/domain/memory-arms/arms-legend";
import { LAYER_INK } from "../../../../core/domain/memory-arms/arms-ink";
import { MAP_PANEL } from "./arms-foot";

/** The eye's glyph, Memnox.TextSize.caption, and the drawn tick box's check, MapBox's tick at a bold weight. */
const EYE_GLYPH = 11;
const TICK_GLYPH = 8;
const TICK_STROKE = 4;


type AreaRow = { key: string; label: string; count: number; ink: string };

/**
 * The areas and the layers, the Mac's `BrainLegend`: each memory area with its colour and count, a press lighting its
 * sector and the eye taking it off the brain or putting it back; each other layer the same way; then the two checks.
 */
export function BrainLegend({
  areas,
  layers,
  hiddenAreas,
  hiddenLayers,
  lit,
  onLight,
  onArea,
  onLayer,
  attentionOnly,
  onAttention,
  allLabels,
  onAllLabels,
}: {
  areas: readonly AreaRow[];
  layers: readonly { layer: LegendLayer; count: number }[];
  hiddenAreas: ReadonlySet<string>;
  hiddenLayers: ReadonlySet<LegendLayer>;
  /** The area lit in the legend or by its hub. */
  lit: string | undefined;
  onLight: (key: string) => void;
  onArea: (key: string) => void;
  onLayer: (layer: LegendLayer) => void;
  attentionOnly: boolean;
  onAttention: () => void;
  allLabels: boolean;
  onAllLabels: () => void;
}) {
  return (
    <section
      aria-label={BrainLegendLines.label}
      onPointerDown={(event) => event.stopPropagation()}
      className={`flex w-brain-card shrink-0 flex-col gap-1 rounded-card p-3 ${MAP_PANEL}`}
    >
      <Heading words={BrainLegendLines.areas} />
      {areas.map((row) => {
        const on = !hiddenAreas.has(row.key);
        return (
          <div key={row.key} className={`flex items-center gap-2.5 py-0.5 ${on ? "" : "opacity-40"}`}>
            <Pressable
              aria-label={`${row.label}, ${row.count}`}
              aria-pressed={lit === row.key}
              title={BrainLegendLines.lights}
              onClick={() => onLight(row.key)}
              className="flex min-w-0 flex-1 cursor-pointer items-center gap-2.5 text-left"
            >
              <Dot ink={row.ink} />
              <span className={`min-w-0 flex-1 truncate text-meta text-foreground ${lit === row.key ? "font-semibold" : ""}`}>{row.label}</span>
              <span className="pl-1.5 font-code text-meta tabular-nums text-muted">{row.count}</span>
            </Pressable>
            <EyeButton on={on} name={row.label} toggle={() => onArea(row.key)} />
          </div>
        );
      })}
      {layers.length > 0 && <Heading words={BrainLegendLines.layers} top />}
      {layers.map((row) => {
        const on = !hiddenLayers.has(row.layer);
        const name = layerWord(row.layer);
        return (
          <div key={row.layer} className="flex flex-col gap-1">
            <div className={`flex items-center gap-2.5 py-0.5 ${on ? "" : "opacity-40"}`}>
              <Dot ink={LAYER_INK[row.layer]} />
              <span className="min-w-0 flex-1 truncate text-meta text-foreground">{name}</span>
              <span className="pl-1.5 font-code text-meta tabular-nums text-muted">{row.count}</span>
              <EyeButton on={on} name={name} toggle={() => onLayer(row.layer)} />
            </div>
            {row.layer === "rule" && <p className="text-label text-faint">{BrainLegendLines.routinesLater}</p>}
          </div>
        );
      })}
      <span aria-hidden className="my-1 h-px bg-panel-edge" />
      <TickRow title={BrainLegendLines.attentionOnly} on={attentionOnly} toggle={onAttention} />
      <TickRow title={BrainLegendLines.allLabels} on={allLabels} toggle={onAllLabels} />
    </section>
  );
}

function Heading({ words, top = false }: { words: string; top?: boolean }) {
  return <p className={`pb-1 font-code text-brain-caption font-medium tracking-heading text-faint ${top ? "pt-1" : ""}`}>{words}</p>;
}

/** A legend row's dot, glowing in its own ink by half its side, as the Mac's shadow does. */
function Dot({ ink }: { ink: string }) {
  return <span aria-hidden className="size-2 shrink-0 rounded-full" style={{ background: ink, boxShadow: `0 0 var(--spacing) ${ink}` }} />;
}

function EyeButton({ on, name, toggle }: { on: boolean; name: string; toggle: () => void }) {
  const said = on ? BrainLegendLines.hide(name) : BrainLegendLines.show(name);
  return (
    <Pressable aria-label={said} title={said} onClick={toggle} className="shrink-0 cursor-pointer text-muted">
      {on ? <Eye size={EYE_GLYPH} aria-hidden /> : <EyeOff size={EYE_GLYPH} aria-hidden />}
    </Pressable>
  );
}

/** One of the two checks, with the tick box drawn rather than native so it wears the console's blue, the Mac's `MapBox`. */
function TickRow({ title, on, toggle }: { title: string; on: boolean; toggle: () => void }) {
  return (
    <Pressable role="checkbox" aria-checked={on} onClick={toggle} className="flex cursor-pointer items-center gap-2.5 text-left">
      <span aria-hidden className={`grid size-map-box shrink-0 place-items-center rounded-key border ${on ? "border-primary bg-primary text-white" : "border-panel-edge bg-background"}`}>
        {on && <Check size={TICK_GLYPH} strokeWidth={TICK_STROKE} />}
      </span>
      <span className="text-meta text-foreground">{title}</span>
    </Pressable>
  );
}
