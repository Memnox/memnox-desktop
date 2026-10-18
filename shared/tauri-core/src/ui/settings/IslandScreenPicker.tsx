import { useEffect, useState } from 'react';
import { ISLAND_SCREEN_LINES, islandScreenOptions, shownIslandScreen } from '../../core/domain/island-screen';
import { SelectMenu, SettingsRow } from './kit';
import { islandWindow } from '../adapters/tauri-island-window';

type Listed = { chosen: string; displays: { id: string; name: string }[] };

/**
 * `IslandScreenPicker`: which display the island hangs from, the main one, wherever the pointer is, or one
 * display by name, read again each time the page is shown so a monitor plugged in since is listed.
 */
export function IslandScreenPicker() {
  const [listed, setListed] = useState<Listed>({ chosen: 'notch', displays: [] });
  useEffect(() => {
    void islandWindow.screens().then(setListed, () => undefined);
  }, []);
  const pick = (stored: string) => {
    setListed({ ...listed, chosen: stored });
    void islandWindow.chooseScreen(stored).catch(() => undefined);
  };
  return (
    <SettingsRow title={ISLAND_SCREEN_LINES.title} caption={ISLAND_SCREEN_LINES.caption}>
      <SelectMenu value={shownIslandScreen(listed.chosen, listed.displays)} options={islandScreenOptions(listed.displays)} onChange={pick} label={ISLAND_SCREEN_LINES.title} />
    </SettingsRow>
  );
}
