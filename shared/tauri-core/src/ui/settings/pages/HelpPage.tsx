import { ClipboardCopy, ShieldHalf, Volume2 } from 'lucide-react';
import { overviewSteps } from '../../../core/domain/setup-steps';
import { KitButton, SettingsCard, SettingsDivider, SettingsRow, useCopied } from '../kit';
import type { SettingsParts } from '../parts';

/**
 * Where this computer stands, for support: each setup step and why one is still open, the daemon's
 * state, and the system. Names and states only, never anything the person said.
 */
function whatHappened(parts: SettingsParts): string {
  const steps = overviewSteps(parts.steps.setupFacts(parts.preferences.name));
  const { runtime, doing, failed } = parts.setup.state;
  return [
    `Memnox: where this computer stands, ${new Date().toISOString()}`,
    `System: ${parts.host.platform}, ${navigator.userAgent}`,
    `Service: ${runtime?.kind ?? 'not checked'}${doing === undefined ? '' : `, ${doing}`}${failed === undefined ? '' : `, ${failed}`}`,
    `Account: ${parts.account.whole.kind}`,
    ...steps.map((step) => `${step.title}: ${step.state.kind}${step.state.kind === 'needs' ? `, ${step.state.why}` : ''}`),
  ].join('\n');
}

/** The Help page: say a rule, check that Memnox hears and answers, and copy what happened for support. */
export function HelpPage({ parts }: { parts: SettingsParts }) {
  const { host } = parts;
  const [copied, copy] = useCopied(host.copy);
  return (
    <SettingsCard>
      <SettingsRow icon={ShieldHalf} title="Say a rule" caption={'Turns a sentence like “never deploy on Fridays” into a rule.'}>
        <KitButton onClick={() => host.talk('rule')}>Say a rule</KitButton>
      </SettingsRow>
      <SettingsDivider />
      <SettingsRow icon={Volume2} title="Say something" caption="Checks that Memnox hears and answers you.">
        <KitButton onClick={() => host.talk()}>Try it</KitButton>
      </SettingsRow>
      <SettingsDivider />
      <SettingsRow icon={ClipboardCopy} title="Copy what happened" caption="Puts where this computer stands on your clipboard to send to support.">
        <KitButton onClick={() => copy(whatHappened(parts))}>{copied ? 'Copied' : 'Copy'}</KitButton>
      </SettingsRow>
    </SettingsCard>
  );
}
