import { useEffect, useState } from 'react';
import { runtimeStanding, START_RETRY_MS, type RuntimeStanding } from '../../core/domain/runtime-away';
import { useObserved, type SettingsParts } from '../settings/parts';

/** When this window's code loaded, which is when the wait for a service still being started begins; a test moves it. */
export const windowOpened = { at: Date.now() };

/**
 * Where the service stands for this window, read off the home it already keeps. While it is still starting the home
 * is asked again every couple of seconds, so the page fills by itself the moment the service answers.
 */
export function useRuntimeStanding(parts: SettingsParts): RuntimeStanding {
  const { home } = parts;
  useObserved(home);
  const [, tick] = useState(0);
  const standing = runtimeStanding({ unavailable: home.unavailable, read: home.home !== undefined }, Date.now() - windowOpened.at);
  useEffect(() => {
    if (standing !== 'starting') return;
    const timer = setInterval(() => {
      // The tick redraws once the wait has run out, even if the read changed nothing.
      void home.refresh().then(() => tick((n) => n + 1));
    }, START_RETRY_MS);
    return () => clearInterval(timer);
  }, [standing]);
  return standing;
}

