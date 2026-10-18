import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import type { OnboardingStage, OnboardingStep } from '../../core/domain/onboarding';
import '../styles.css';
import '../settings/settings.css';
import { paintLook } from '../settings/parts';
import { previewState } from '../settings/preview-world';
import { inApp, worldParts } from '../settings/world';
import { OnboardingApp } from './OnboardingApp';

/** The first run's own window, opened by the island on a first launch; a preview opens on ?stage= and ?step=. */
const parts = worldParts();
paintLook(parts.preferences.look);

const asked = new URLSearchParams(window.location.search);
const stage = (['intro', 'name', 'steps'] as const).find((each) => each === asked.get('stage')) satisfies OnboardingStage | undefined;
const stepNumber = Number(asked.get('step') ?? '0');
const step = ([0, 1, 2] as const).find((each) => each === stepNumber) satisfies OnboardingStep | undefined;

if (!inApp && (previewState === 'qr' || previewState === 'digits')) void parts.pairing.pair();

const root = document.getElementById('root');
if (root === null) throw new Error('onboarding.html has no root');
createRoot(root).render(
  <StrictMode>
    <OnboardingApp parts={parts} stage={stage} step={step} />
  </StrictMode>,
);
