import { IMPACT_WORDS, impactEvidence, impactRows, type HeldImpact } from '../../core';

/**
 * `HeldImpactLines`: what a held action could affect, whether it can be undone and what was verified, in the
 * machine's own sentences. How each is known sits behind "More about this", never on the face of the card.
 */
export function HeldImpactLines({ impact }: { impact: HeldImpact }) {
  return (
    <div className="flex flex-col gap-1.5">
      <dl className="m-0 flex flex-col gap-1.5">
        {impactRows(impact).map((row) => (
          <div key={row.label}>
            <dt className="text-caption text-ink-secondary">{row.label}</dt>
            <dd className="m-0 text-footnote text-ink [overflow-wrap:anywhere]">{row.text}</dd>
          </div>
        ))}
      </dl>
      <details>
        <summary className="mx-focus cursor-pointer text-caption text-ink-secondary select-none">{IMPACT_WORDS.more}</summary>
        <ul className="m-0 mt-1 flex list-none flex-col gap-1 p-0">
          {impactEvidence(impact).map((each, index) => (
            <li key={index} className="text-caption text-ink-secondary [overflow-wrap:anywhere]">
              <span className="font-medium text-ink">{each.label}</span> {each.value}
            </li>
          ))}
        </ul>
      </details>
    </div>
  );
}
