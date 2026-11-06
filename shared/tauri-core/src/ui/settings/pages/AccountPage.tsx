import { BellDot, Monitor, Speech } from 'lucide-react';
import { useEffect, useState } from 'react';
import { accountDetail, accountState, accountTitle } from '../../../core/domain/account-whole';
import { nameStep } from '../../../core/domain/setup-steps';
import { Digits, NeedsHint, QuietLine, SettingsCard, SettingsDivider, SettingsRow, SettingsSection, StatusMark, Surface } from '../kit';
import { useObserved, usePreferences, type SettingsParts } from '../parts';
import { SetupStep } from '../steps';
import { Button, Input, Spinner } from '../../kit';
import { AccountPageLines } from '../../../core/domain/account-page-lines';

/** The name field, as wide as the Mac's beside its row. */
const NAME_FIELD_WIDTH = 220;

/**
 * The Account page, as the Mac's `AccountPage`: the person's name, the one sign in that gives this computer
 * everything, and what signing in turns on, said as plain words since none of it is a choice of its own.
 */
export function AccountPage({ parts }: { parts: SettingsParts }) {
  const { account, words } = parts;
  useObserved(account);
  usePreferences();
  useEffect(() => void account.refresh(), []);
  return (
    <>
      <SettingsSection title={AccountPageLines.you}>
        <Surface>
          <NameRow parts={parts} />
        </Surface>
      </SettingsSection>
      <SettingsSection title={AccountPageLines.cloud}>
        <Surface>
          <CloudRow parts={parts} />
        </Surface>
      </SettingsSection>
      <SettingsSection title={AccountPageLines.turnsOn}>
        <SettingsCard>
          <SettingsRow icon={BellDot} title={AccountPageLines.callsRouted(words.keyTitle)} />
          <SettingsDivider />
          <SettingsRow icon={Speech} title={AccountPageLines.appsMove} />
          <SettingsDivider />
          <SettingsRow icon={Monitor} title={AccountPageLines.rulesReach} />
        </SettingsCard>
      </SettingsSection>
    </>
  );
}

/** `SetupNameRow`: the mark, "Your name", and a 220 wide field kept as it is typed. */
export function NameRow({ parts }: { parts: SettingsParts }) {
  const { preferences } = parts;
  const [name, setName] = useState(preferences.name);
  return (
    <SetupStep
      state={nameStep(name)}
      title={AccountPageLines.yourName}
      detail={AccountPageLines.nameDetail}
      trailing={
        <Input
          value={name}
          placeholder={AccountPageLines.yourName}
          width={NAME_FIELD_WIDTH}
          onValue={(typed) => {
            setName(typed);
            preferences.name = typed;
          }}
        />
      }
    />
  );
}

/** The one sign in, as `AccountRow`: where it stands, and the code to approve while one is up. */
export function CloudRow({ parts, compact = false }: { parts: SettingsParts; compact?: boolean }) {
  const { account } = parts;
  useObserved(account);
  const whole = account.whole;
  const state = accountState(whole);
  return (
    <div className="flex flex-col gap-2.5 px-4 py-3">
      <div className="flex items-center gap-3">
        <StatusMark state={state} />
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="text-body text-foreground">{accountTitle(whole)}</span>
          <span className="text-footnote text-muted">{accountDetail(whole)}</span>
        </div>
        <div className="ml-2 flex shrink-0 items-center gap-1.5">
          <CloudControl parts={parts} />
        </div>
      </div>
      {whole.kind === 'showing-code' && (
        <div className="flex flex-col gap-1 pl-8">
          <Digits code={whole.code} size={compact ? 24 : 26} />
          <QuietLine size={compact ? 12 : 11}>Approve this computer in the console with the code {whole.code}.</QuietLine>
        </div>
      )}
      {state.kind === 'needs' && whole.kind !== 'too-old' && (
        <div className="pl-8">
          <NeedsHint why={state.why} />
        </div>
      )}
    </div>
  );
}

function CloudControl({ parts }: { parts: SettingsParts }) {
  const { account } = parts;
  const whole = account.whole;
  switch (whole.kind) {
    case 'signed-out':
    case 'failed':
      return (
        <Button kind="primary" onClick={() => void account.start()}>
          {AccountPageLines.signIn}
        </Button>
      );
    case 'working':
      return <Spinner />;
    case 'showing-code':
      return <Button onClick={() => account.cancel()}>{AccountPageLines.cancel}</Button>;
    case 'incomplete':
      return (
        <>
          <Button onClick={() => void account.signOut()}>{AccountPageLines.signOut}</Button>
          <Button kind="primary" onClick={() => void account.finish()}>
            {AccountPageLines.finish}
          </Button>
        </>
      );
    case 'too-old':
      return account.updating ? (
        <Spinner />
      ) : (
        <Button kind="primary" onClick={() => void account.bringUpToDate()}>
          {AccountPageLines.update}
        </Button>
      );
    case 'signed-in':
      return <Button onClick={() => void account.signOut()}>{AccountPageLines.signOut}</Button>;
  }
}
