import { Minus, Plus } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { HubServerDraft } from '../../../core/application/mcp-hub';
import { AddServerLines, addedLine, agentLabel, COMMAND_HINT, headerProblem, headersOf, isCredentialHeader, remoteAddressProblem, serverNameFrom, splitCommand, type HeaderRow } from '../../../core/domain/mcp-hub-lines';
import type { SettingsParts } from '../../settings/parts';
import { BrandLogo, Button, Checkbox, Dialog, ErrorLine, Field, IconButton, Input, PRESS_DIP, Pressable } from '../../kit';

interface Variable {
  name: string;
  value: string;
  secret: boolean;
}

/** A variable's or header's name is short, so its field is capped and the value takes the rest of the row. */
const NAME_FIELD = 'max-w-app-variable-name';
const HEADER_FIELD = 'max-w-app-variable-name';
/** The value never narrows past what a token's start reads at. */
const VALUE_MIN = 140;

/** The agents' logos in the list, as large as a row of 13 point words. */
const AGENT_LOGO = 20;

/** The written config is read by a person, so it is indented as a file would be. */
const JSON_INDENT = 2;

/**
 * Adding a server in three short steps, with no JSON unless asked for. A variable marked secret goes to
 * this computer's own store and the server is written with only its name, so no agent's config holds it. A remote
 * server's header kept as a secret goes the same way, sent as `memnox-secret:<name>` for the proxy to fill in.
 */
export function AddServerDialog({ parts, agents, close, noted }: { parts: SettingsParts; agents: readonly string[]; close: () => void; noted: (line: string | undefined) => void }) {
  const { hub } = parts;
  const [step, setStep] = useState(0);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [remote, setRemote] = useState(false);
  const [launch, setLaunch] = useState('');
  const [url, setUrl] = useState('');
  const [variables, setVariables] = useState<Variable[]>([]);
  const [headers, setHeaders] = useState<HeaderRow[]>([]);
  const [given, setGiven] = useState<ReadonlySet<string>>(new Set());
  const [advanced, setAdvanced] = useState(false);
  const [problem, setProblem] = useState<string | undefined>(undefined);
  const [working, setWorking] = useState(false);
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => first.current?.focus(), []);

  const draft = (): HubServerDraft | string => {
    const named = serverNameFrom(name);
    if (named === '') return AddServerLines.needsName;
    const env: Record<string, string> = {};
    const secrets: Record<string, string> = {};
    for (const each of variables.filter((variable) => variable.name.trim() !== '')) {
      if (each.secret) secrets[each.name.trim()] = `${named}-${each.name.trim().toLowerCase().replace(/_/g, '-')}`;
      else env[each.name.trim()] = each.value;
    }
    const base = { name: named, ...(description.trim() === '' ? {} : { description: description.trim() }), env, secrets };
    if (remote) {
      if (url.trim() === '') return AddServerLines.needsAddress;
      const problem = remoteAddressProblem(url) ?? headerProblem(headers);
      if (problem !== undefined) return problem;
      const sent = headersOf(named, headers).headers;
      return { ...base, transport: 'http', url: url.trim(), ...(Object.keys(sent).length === 0 ? {} : { headers: sent }) };
    }
    const split = splitCommand(launch);
    if (split === undefined) return AddServerLines.needsCommand;
    return { ...base, transport: 'stdio', command: split.command, args: split.args };
  };

  const finish = async () => {
    const server = draft();
    if (typeof server === 'string') {
      setProblem(server);
      return;
    }
    setWorking(true);
    await put(server);
    setWorking(false);
  };

  const put = async (server: HubServerDraft) => {
    // Secrets first, so the server never starts without its credential.
    const headerSecrets = remote ? Object.entries(headersOf(server.name, headers).secrets) : [];
    for (const [secret, value] of headerSecrets) {
      const outcome = await hub.setSecret(secret, value);
      if (outcome.kind === 'failed') {
        setProblem(outcome.why);
        return;
      }
    }
    for (const each of variables.filter((variable) => variable.secret && variable.name.trim() !== '' && variable.value !== '')) {
      const outcome = await hub.setSecret(server.secrets[each.name.trim()] ?? '', each.value);
      if (outcome.kind === 'failed') {
        setProblem(outcome.why);
        return;
      }
    }
    const outcome = await hub.putServer(server);
    if (outcome.kind === 'failed') {
      setProblem(outcome.why);
      return;
    }
    // Each agent is asked for once the person has signed the server in, one signature each.
    const chosen = agents.filter((agent) => given.has(agent));
    hub.giveOnceAdded(server.name, chosen);
    // What waits, what will run in place of an install, and who is asked next, said on the page the dialog leaves.
    noted(addedLine(hub.press(server.name), server.name, chosen, parts.words.keyTitle));
    close();
  };

  const preview = draft();
  const steps = AddServerLines.steps;
  return (
    <Dialog
      title={AddServerLines.title}
      step={AddServerLines.stepOf(steps[step] ?? '', step + 1, steps.length)}
      close={close}
      actions={
        <>
          {step > 0 && <Button onClick={() => setStep(step - 1)}>{AddServerLines.back}</Button>}
          <span className="flex-1" />
          {step < steps.length - 1 ? (
            <Button kind="primary" onClick={() => (step === 0 && typeof draft() === 'string' ? setProblem(draft() as string) : (setProblem(undefined), setStep(step + 1)))}>
              {AddServerLines.continue}
            </Button>
          ) : (
            <Button kind="primary" disabled={working || hub.busy !== undefined} onClick={() => void finish()}>
              {AddServerLines.add}
            </Button>
          )}
        </>
      }
    >
      {step === 0 && (
        <>
          <Field label={AddServerLines.name}>
            <Input ref={first} wide value={name} onValue={setName} placeholder={AddServerLines.namePlaceholder} />
          </Field>
          <Field label={AddServerLines.description}>
            <Input wide value={description} onValue={setDescription} placeholder={AddServerLines.descriptionPlaceholder} />
          </Field>
          <div role="radiogroup" aria-label={AddServerLines.howItRuns} className="grid grid-cols-2 gap-2">
            <Choice on={!remote} title={AddServerLines.local} body={AddServerLines.localBody} pick={() => setRemote(false)} />
            <Choice on={remote} title={AddServerLines.remote} body={AddServerLines.remoteBody} pick={() => setRemote(true)} />
          </div>
          {remote ? (
            <Field label={AddServerLines.address}>
              <Input wide value={url} onValue={setUrl} placeholder={AddServerLines.addressPlaceholder} />
            </Field>
          ) : (
            <Field label={AddServerLines.command} help={COMMAND_HINT}>
              <Input wide mono value={launch} onValue={setLaunch} placeholder={AddServerLines.commandPlaceholder} />
            </Field>
          )}
          {remote && <HeaderRows rows={headers} change={setHeaders} />}
          {remote && <p className="text-footnote text-muted">{AddServerLines.remoteNote}</p>}
        </>
      )}

      {step === 1 && (
        <>
          <p className="text-footnote text-muted">{AddServerLines.secretNote}</p>
          {variables.map((variable, at) => (
            <div key={at} className="flex flex-wrap items-center gap-2">
              <Input
                wide
                mono
                className={NAME_FIELD}
                aria-label={AddServerLines.variableName}
                placeholder={AddServerLines.variablePlaceholder}
                value={variable.name}
                onValue={(typed) => setVariables(variables.map((each, i) => (i === at ? { ...each, name: typed } : each)))}
              />
              <Input
                wide
                className="flex-1"
                minWidth={VALUE_MIN}
                aria-label={AddServerLines.value}
                type={variable.secret ? 'password' : 'text'}
                autoComplete="off"
                value={variable.value}
                onValue={(typed) => setVariables(variables.map((each, i) => (i === at ? { ...each, value: typed } : each)))}
              />
              <Checkbox checked={variable.secret} onToggle={() => setVariables(variables.map((each, i) => (i === at ? { ...each, secret: !each.secret } : each)))}>
                {AddServerLines.secret}
              </Checkbox>
              <IconButton icon={Minus} size="sm" label={AddServerLines.removeVariable} onClick={() => setVariables(variables.filter((_, i) => i !== at))} />
            </div>
          ))}
          <div>
            <Button icon={Plus} onClick={() => setVariables([...variables, { name: '', value: '', secret: true }])}>
              {AddServerLines.addVariable}
            </Button>
          </div>
        </>
      )}

      {step === 2 && (
        <>
          <p className="text-footnote text-muted">{AddServerLines.chooseAgents(parts.words.keyTitle)}</p>
          {agents.length === 0 ? (
            <p className="text-body text-muted">{AddServerLines.noAgents}</p>
          ) : (
            <div className="flex flex-col gap-1.5">
              {agents.map((agent) => (
                <Checkbox
                  key={agent}
                  checked={given.has(agent)}
                  onToggle={() => {
                    const next = new Set(given);
                    if (next.has(agent)) next.delete(agent);
                    else next.add(agent);
                    setGiven(next);
                  }}
                >
                  <BrandLogo agent={agent} name={agentLabel(agent)} size={AGENT_LOGO} />
                  <span className="text-body text-foreground">{agentLabel(agent)}</span>
                </Checkbox>
              ))}
            </div>
          )}
          <Button kind="link" size="small" onClick={() => setAdvanced(!advanced)} aria-expanded={advanced}>
            {advanced ? AddServerLines.hideWritten : AddServerLines.showWritten}
          </Button>
          {advanced && (
            <pre className="max-h-48 overflow-auto rounded-control bg-hover p-3 font-code text-micro text-foreground">
              {typeof preview === 'string' ? preview : JSON.stringify(preview, null, JSON_INDENT)}
            </pre>
          )}
        </>
      )}
      {problem !== undefined && <ErrorLine>{problem}</ErrorLine>}
    </Dialog>
  );
}

/** A remote server's headers, a credential kept as a secret from the moment its name is typed. */
function HeaderRows({ rows, change }: { rows: readonly HeaderRow[]; change: (rows: HeaderRow[]) => void }) {
  const update = (at: number, next: Partial<HeaderRow>) => change(rows.map((each, i) => (i === at ? { ...each, ...next } : each)));
  return (
    <div className="flex flex-col gap-2">
      <span className="text-footnote font-medium text-muted">{AddServerLines.headers}</span>
      {rows.map((row, at) => (
        <div key={at} className="flex flex-wrap items-center gap-2">
          <Input
            wide
            mono
            className={HEADER_FIELD}
            aria-label={AddServerLines.headerName}
            placeholder={AddServerLines.headerPlaceholder}
            value={row.name}
            // A credential header starts kept, and is kept while its name says it is one.
            onValue={(typed) => update(at, { name: typed, ...(isCredentialHeader(typed) ? { secret: true } : {}) })}
          />
          <Input
            wide
            className="flex-1"
                minWidth={VALUE_MIN}
            aria-label={AddServerLines.headerValue}
            placeholder={AddServerLines.headerValuePlaceholder}
            type={row.secret ? 'password' : 'text'}
            autoComplete="off"
            value={row.value}
            onValue={(typed) => update(at, { value: typed })}
          />
          <Checkbox
            checked={row.secret}
            disabled={isCredentialHeader(row.name)}
            title={isCredentialHeader(row.name) ? AddServerLines.credentialHeader : undefined}
            onToggle={() => update(at, { secret: !row.secret })}
          >
            {AddServerLines.keepSecret}
          </Checkbox>
          <IconButton icon={Minus} size="sm" label={AddServerLines.removeHeader} onClick={() => change(rows.filter((_, i) => i !== at))} />
        </div>
      ))}
      <div>
        <Button icon={Plus} onClick={() => change([...rows, { name: '', value: '', secret: false }])}>
          {AddServerLines.addHeader}
        </Button>
      </div>
    </div>
  );
}

/** One way the server runs, as a card that is either chosen or not. */
function Choice({ on, title, body, pick }: { on: boolean; title: string; body: string; pick: () => void }) {
  return (
    <Pressable role="radio" aria-checked={on} onClick={pick} className={`mx-focus flex cursor-pointer flex-col gap-0.5 rounded-card border px-3.5 py-3 text-left ${PRESS_DIP} ${on ? 'border-primary bg-hover' : 'border-panel-edge hover:bg-hover'}`}>
      <span className="text-body font-medium text-foreground">{title}</span>
      <span className="text-footnote text-muted">{body}</span>
    </Pressable>
  );
}
