import type { ReactNode } from 'react';
import type { SettingsPage } from '../../core/domain/settings-pages';
import { AccountPage } from './pages/AccountPage';
import { HelpPage } from './pages/HelpPage';
import { AppearancePage, ConnectionPage, PermissionsPage, PhonesPage } from './pages/ComputerPages';
import { ToolsPage } from './pages/ToolsPage';
import { YourAppsPage } from './pages/YourAppsPage';
import { DictationPage, ListeningPage, VoicePage } from './pages/VoicePages';
import type { SettingsParts } from './parts';

/** One Settings page's body, drawn in the window under Settings, and Connection under Machines. */
export function PageBody({ page, parts }: { page: SettingsPage; parts: SettingsParts }): ReactNode {
  switch (page) {
    // The overview became Home, so a stale link naming it lands on Account.
    case 'overview':
    case 'account':
      return <AccountPage parts={parts} />;
    case 'permissions':
      return <PermissionsPage parts={parts} />;
    case 'connection':
      return <ConnectionPage parts={parts} />;
    case 'phones':
      return <PhonesPage parts={parts} />;
    case 'appearance':
      return <AppearancePage parts={parts} />;
    case 'tools':
      return <ToolsPage parts={parts} />;
    case 'apps':
      return <YourAppsPage parts={parts} />;
    case 'voice':
      return <VoicePage parts={parts} />;
    case 'listening':
      return <ListeningPage parts={parts} />;
    case 'dictation':
      return <DictationPage parts={parts} />;
    case 'help':
      return <HelpPage parts={parts} />;
  }
}
