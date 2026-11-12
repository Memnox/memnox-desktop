import { ArrowUpCircle } from 'lucide-react';
import { useEffect, useSyncExternalStore } from 'react';
import type { Updates } from '../core/application/updates';
import { UPDATE_CHECK_MS, UpdateLines, type UpdateOffer } from '../core/domain/updates';
import { Button, IslandButton, Note, Spinner, UnderPill } from './kit';

/**
 * The offers a window draws, looked for as it opens and every few hours after, as the Mac's `watchForUpdates`. Each
 * read is given twice, since a page drawn to a string in a test asks for the server's reading too.
 */
function useOffers(updates: Updates): { offers: readonly UpdateOffer[]; busy: boolean; failed: string | undefined } {
  const offers = useSyncExternalStore(
    (changed) => updates.observe(changed),
    () => updates.offers,
    () => updates.offers,
  );
  const busy = useSyncExternalStore(
    (changed) => updates.observe(changed),
    () => updates.busy !== undefined,
    () => updates.busy !== undefined,
  );
  const failed = useSyncExternalStore(
    (changed) => updates.observe(changed),
    () => updates.failed,
    () => updates.failed,
  );
  useEffect(() => {
    void updates.look();
    const timer = setInterval(() => void updates.look(), UPDATE_CHECK_MS);
    return () => clearInterval(timer);
  }, [updates]);
  return { offers, busy, failed };
}

/** A newer Memnox under the island, in every mode until the person updates or presses Later, as the Mac's update pill. */
export function UpdatePills({ updates }: { updates: Updates }) {
  const { offers, busy, failed } = useOffers(updates);
  return (
    <>
      {offers.map((offer) => {
        const working = busy && offer.kind === 'runtime';
        return (
          <UnderPill key={offer.kind} symbol={<ArrowUpCircle size={11} strokeWidth={2.25} />} tone="neutral">
            <span className="truncate">{working ? UpdateLines.updatingRuntime : offer.kind === 'runtime' && failed !== undefined ? UpdateLines.failed(failed) : UpdateLines.title(offer)}</span>
            {!working && (
              <>
                <IslandButton onClick={() => void updates.update(offer)}>{UpdateLines.action(offer)}</IslandButton>
                <IslandButton onClick={() => updates.later(offer)}>{UpdateLines.later}</IslandButton>
              </>
            )}
          </UnderPill>
        );
      })}
    </>
  );
}

/** The same offers on Home, each with what updating does and the two presses, so nobody has to find the island for it. */
export function UpdateBanner({ updates }: { updates: Updates }) {
  const { offers, busy, failed } = useOffers(updates);
  if (offers.length === 0) return null;
  return (
    <div className="flex flex-col gap-2">
      {offers.map((offer) => {
        const working = busy && offer.kind === 'runtime';
        return (
          <Note key={offer.kind} roomy>
            <span className="flex flex-wrap items-center gap-x-4 gap-y-2">
              <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                <span className="font-medium text-foreground">{UpdateLines.title(offer)}</span>
                <span className="text-muted">{offer.kind === 'runtime' && failed !== undefined ? UpdateLines.failed(failed) : UpdateLines.detail(offer)}</span>
              </span>
              {working ? (
                <span className="flex items-center gap-2 text-muted">
                  <Spinner />
                  {UpdateLines.updatingRuntime}
                </span>
              ) : (
                <span className="flex shrink-0 items-center gap-2">
                  <Button kind="primary" onClick={() => void updates.update(offer)}>
                    {UpdateLines.action(offer)}
                  </Button>
                  <Button onClick={() => updates.later(offer)}>{UpdateLines.later}</Button>
                </span>
              )}
            </span>
          </Note>
        );
      })}
    </div>
  );
}
