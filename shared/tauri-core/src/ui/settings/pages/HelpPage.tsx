import { ClipboardCopy, ShieldHalf, Volume2 } from 'lucide-react';
import { overviewSteps } from '../../../core/domain/setup-steps';
import { SettingsCard, SettingsDivider, SettingsRow, useCopied } from '../kit';
import type { SettingsParts } from '../parts';
import { Button } from '../../kit';
import { HelpPageLines } from '../../../core/domain/help-page-lines';

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
  // The island's diary of steps first, as the Mac copies it, then where this computer stands.
  const [copied, copy] = useCopied((text) => host.copyWhatHappened?.(text) ?? host.copy(text));
  return (
    <SettingsCard>
      <SettingsRow icon={ShieldHalf} title={HelpPageLines.sayRule} caption={HelpPageLines.sayRuleCaption}>
        <Button onClick={() => host.talk('rule')}>{HelpPageLines.sayRule}</Button>
      </SettingsRow>
      <SettingsDivider />
      <SettingsRow icon={Volume2} title={HelpPageLines.saySomething} caption={HelpPageLines.saySomethingCaption}>
        <Button onClick={() => void host.voices.test()}>{HelpPageLines.tryIt}</Button>
      </SettingsRow>
      <SettingsDivider />
      <SettingsRow icon={ClipboardCopy} title={HelpPageLines.copyWhat} caption={HelpPageLines.copyWhatCaption}>
        <Button onClick={() => copy(whatHappened(parts))}>{copied ? HelpPageLines.copied : HelpPageLines.copy}</Button>
      </SettingsRow>
    </SettingsCard>
  );
}
