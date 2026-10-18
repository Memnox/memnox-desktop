import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { pageNamed } from '../../core/domain/settings-pages';
import '../styles.css';
import './settings.css';
import { paintLook } from './parts';
import { previewState } from './preview-world';
import { SettingsApp } from './SettingsApp';
import { inApp, worldParts } from './world';

/** The Settings window's own page, opened by the island's Settings satellite, the tray, or a link to one page. */
const parts = worldParts();
const first = pageNamed(new URLSearchParams(window.location.search).get('page'));
paintLook(parts.preferences.look);

// A preview opens straight on the variant it was asked for, such as the QR up on Phones.
if (!inApp) {
  if (previewState === 'qr' || previewState === 'digits') void parts.pairing.pair();
  if (previewState === 'installing') void parts.steps.installVoice();
  if (previewState === 'code') void parts.account.start();
}

const root = document.getElementById('root');
if (root === null) throw new Error('settings.html has no root');
createRoot(root).render(
  <StrictMode>
    <SettingsApp parts={parts} first={first} />
  </StrictMode>,
);
