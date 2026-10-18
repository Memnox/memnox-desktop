import { StrictMode, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { invoke } from '@tauri-apps/api/core';
import { emit, listen } from '@tauri-apps/api/event';
import type { DisplayHost } from '@memnox/core/wire';
import { CARD_PANEL, CARD_TIMING, type FloatingCard } from '../../../core/domain/floating-cards';
import { FloatingCardView } from './FloatingCards';
import { WINDOW_EVENTS, type CardSessionAsk } from '../../adapters/tauri-windows';
import { previewCard } from './preview-cards';
import '../../styles.css';
import './floating.css';

const asked = new URLSearchParams(window.location.search);
const preview = asked.get('preview') ?? undefined;
if (asked.get('theme') === 'light' || asked.get('theme') === 'dark') document.documentElement.dataset.theme = asked.get('theme') ?? undefined;

/**
 * The card panel, the Mac's `CardPanel`: a borderless window 20 in from the top left of the screen,
 * drawing one card in a 40 margin for its shadow. It fades in, stays a minute, or 15 s once the pointer
 * leaves, never goes while the pointer is on it, and fades out over 0.3 s.
 */
function CardPanel() {
  const [card, setCard] = useState<FloatingCard | undefined>(preview === undefined ? undefined : previewCard(preview));
  const [leaving, setLeaving] = useState(false);
  const [hovered, setHovered] = useState(false);
  const [left, setLeft] = useState(false);
  const holder = useRef<HTMLDivElement>(null);

  const close = useCallback(() => {
    setLeaving(true);
    setTimeout(() => {
      setCard(undefined);
      setLeaving(false);
      if (preview === undefined) void invoke('cards_hide').catch(() => undefined);
    }, CARD_TIMING.fadeOutMs);
  }, []);

  useEffect(() => {
    if (preview !== undefined) return;
    const shown = listen<FloatingCard>(WINDOW_EVENTS.card, (event) => {
      setLeaving(false);
      setLeft(false);
      setCard(event.payload);
    });
    const dismissed = listen(WINDOW_EVENTS.cardsDismiss, () => close());
    return () => {
      void shown.then((stop) => stop());
      void dismissed.then((stop) => stop());
    };
  }, [close]);

  // A minute on screen, or 15 s once the pointer has been and gone; never while it rests on the card.
  useEffect(() => {
    if (card === undefined || hovered || preview !== undefined) return;
    const wait = setTimeout(close, left ? CARD_TIMING.afterLeaveMs : CARD_TIMING.stayMs);
    return () => clearTimeout(wait);
  }, [card, hovered, left, close]);

  // The window hugs the card, so nothing outside it catches a click meant for the app underneath.
  useLayoutEffect(() => {
    const element = holder.current;
    if (element === null || preview !== undefined) return;
    const fit = () => void invoke('cards_fit', { height: Math.ceil(element.getBoundingClientRect().height) + 2 * CARD_PANEL.margin }).catch(() => undefined);
    const watcher = new ResizeObserver(fit);
    watcher.observe(element);
    return () => watcher.disconnect();
  }, [card]);

  function ask(sessionId: string, host: DisplayHost | undefined, watch: boolean) {
    const message: CardSessionAsk = { sessionId, host, watch };
    void emit(WINDOW_EVENTS.cardSession, message).catch(() => undefined);
    close();
  }

  return (
    <div style={{ padding: CARD_PANEL.margin, width: CARD_PANEL.width + 2 * CARD_PANEL.margin }}>
      <div ref={holder} className={`transition-opacity ease-out ${leaving ? 'opacity-0 duration-300' : 'opacity-100 duration-[250ms]'}`}>
        {card !== undefined && (
          <FloatingCardView
            key={JSON.stringify(card).length}
            card={card}
            actions={{
              close,
              watch: (sessionId, host) => ask(sessionId, host, true),
              open: (sessionId, host) => ask(sessionId, host, false),
              link: (href) => void invoke('open_link', { url: href }).catch(() => undefined),
              hovering: (over) => {
                setHovered(over);
                if (!over) setLeft(true);
              },
            }}
          />
        )}
      </div>
    </div>
  );
}

const root = document.getElementById('root');
if (root === null) throw new Error('cards.html has no root');
createRoot(root).render(
  <StrictMode>
    <CardPanel />
  </StrictMode>,
);
