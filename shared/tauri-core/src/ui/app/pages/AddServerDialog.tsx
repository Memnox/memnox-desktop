import { Minus, Plus, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import type { HubOutcome, HubServerDraft } from '../../../core/application/mcp-hub';
import { agentLabel, headerProblem, headersOf, isCredentialHeader, remoteAddressProblem, serverNameFrom, splitCommand, type HeaderRow } from '../../../core/domain/mcp-hub-lines';
import { BrandLogo } from '../../kit/logos';
import { KitButton } from '../../settings/kit';
import type { SettingsParts } from '../../settings/parts';

interface Variable {
  name: string;
  value: string;
  secret: boolean;
}

const STEPS = ['Server', 'Variables', 'Agents'] as const;

/**
 * Adding a server in three short steps, with no JSON unless asked for. A variable marked secret goes to
 * this computer's own store and the server is written with only its name, so no agent's config holds it. A remote
 * server's header kept as a secret goes the same way, sent as `memnox-secret:<name>` for the proxy to fill in.
 */
export function AddServerDialog({ parts, agents, close, said }: { parts: SettingsParts; agents: readonly string[]; close: () => void; said: (outcome: HubOutcome) => void }) {
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
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => first.current?.focus(), []);

  const draft = (): HubServerDraft | string => {
    const named = serverNameFrom(name);
    if (named === '') return 'Give the server a name.';
    const env: Record<string, string> = {};
    const secrets: Record<string, string> = {};
    for (const each of variables.filter((variable) => variable.name.trim() !== '')) {
      if (each.secret) secrets[each.name.trim()] = `${named}-${each.name.trim().toLowerCase().replace(/_/g, '-')}`;
      else env[each.name.trim()] = each.value;
    }
    const base = { name: named, ...(description.trim() === '' ? {} : { description: description.trim() }), env, secrets };
    if (remote) {
      if (url.trim() === '') return 'Give the address the server answers on.';
      const problem = remoteAddressProblem(url) ?? headerProblem(headers);
      if (problem !== undefined) return problem;
      const sent = headersOf(named, headers).headers;
      return { ...base, transport: 'http', url: url.trim(), ...(Object.keys(sent).length === 0 ? {} : { headers: sent }) };
    }
    const split = splitCommand(launch);
    if (split === undefined) return 'Give the command that starts the server.';
    return { ...base, transport: 'stdio', command: split.command, args: split.args };
  };

  const finish = async () => {
    const server = draft();
    if (typeof server === 'string') {
      setProblem(server);
      return;
    }
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
    said(outcome);
    // Each agent is asked for once the person has signed the server in, one signature each.
    hub.giveOnceAdded(server.name, [...given]);
    close();
  };

  const field = 'h-9 w-full mx-field rounded-lg border border-field-edge bg-field px-3 text-body text-foreground outline-none placeholder:text-faint focus:border-primary';
  const preview = draft();
  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 px-4 py-[8vh]" role="presentation" onMouseDown={close}>
      <div role="dialog" aria-modal="true" aria-label="Add a server" className="flex w-full max-w-[560px] flex-col rounded-xl border border-panel-edge bg-card shadow-[0_24px_60px_rgb(0_0_0/0.18)]" onMouseDown={(event) => event.stopPropagation()}>
        <header className="flex items-center gap-3 border-b border-panel-edge px-5 py-3.5">
          <span className="flex-1 text-lg font-semibold">Add a server</span>
          <span className="text-footnote text-muted">{`${STEPS[step]} · step ${step + 1} of ${STEPS.length}`}</span>
          <button type="button" aria-label="Close" onClick={close} className="mx-focus grid size-7 cursor-pointer place-items-center rounded-md text-muted hover:bg-hover">
            <X size={15} />
          </button>
        </header>

        <div className="flex flex-col gap-4 px-5 py-5">
          {step === 0 && (
            <>
              <Labelled label="Name">
                <input ref={first} className={field} value={name} onChange={(event) => setName(event.target.value)} placeholder="github" />
              </Labelled>
              <Labelled label="What it is for, optional">
                <input className={field} value={description} onChange={(event) => setDescription(event.target.value)} placeholder="Issues and pull requests" />
              </Labelled>
              <div role="radiogroup" aria-label="How it runs" className="grid grid-cols-2 gap-2">
                <Choice on={!remote} title="On this computer" body="Started by a command" pick={() => setRemote(false)} />
                <Choice on={remote} title="Remote" body="Reached at an address" pick={() => setRemote(true)} />
              </div>
              {remote ? (
                <Labelled label="Address">
                  <input className={field} value={url} onChange={(event) => setUrl(event.target.value)} placeholder="https://mcp.example.com/mcp" />
                </Labelled>
              ) : (
                <Labelled label="Command">
                  <input className={`${field} font-mono`} value={launch} onChange={(event) => setLaunch(event.target.value)} placeholder="npx -y @modelcontextprotocol/server-github" />
                </Labelled>
              )}
              {remote && <HeaderRows rows={headers} change={setHeaders} field={field} />}
              {remote && <p className="text-footnote text-muted">Memnox stands in front of a remote server, so every call to it is ruled on and recorded. Plain http is only for one on this computer.</p>}
            </>
          )}

          {step === 1 && (
            <>
              <p className="text-footnote text-muted">Mark a token or key as secret: this computer keeps it, and agents' configs only name it.</p>
              {variables.map((variable, at) => (
                <div key={at} className="flex flex-wrap items-center gap-2">
                  <input
                    className={`${field} max-w-[180px] font-mono`}
                    aria-label="Variable name"
                    placeholder="GITHUB_TOKEN"
                    value={variable.name}
                    onChange={(event) => setVariables(variables.map((each, i) => (i === at ? { ...each, name: event.target.value } : each)))}
                  />
                  <input
                    className={`${field} min-w-[140px] flex-1`}
                    aria-label="Value"
                    type={variable.secret ? 'password' : 'text'}
                    autoComplete="off"
                    value={variable.value}
                    onChange={(event) => setVariables(variables.map((each, i) => (i === at ? { ...each, value: event.target.value } : each)))}
                  />
                  <label className="flex items-center gap-1.5 text-footnote text-foreground">
                    <input type="checkbox" checked={variable.secret} onChange={() => setVariables(variables.map((each, i) => (i === at ? { ...each, secret: !each.secret } : each)))} />
                    Secret
                  </label>
                  <button type="button" aria-label="Remove this variable" onClick={() => setVariables(variables.filter((_, i) => i !== at))} className="mx-focus grid size-7 cursor-pointer place-items-center rounded-md text-muted hover:bg-hover">
                    <Minus size={14} />
                  </button>
                </div>
              ))}
              <div>
                <KitButton icon={Plus} onClick={() => setVariables([...variables, { name: '', value: '', secret: true }])}>
                  Add a variable
                </KitButton>
              </div>
            </>
          )}

          {step === 2 && (
            <>
              <p className="text-footnote text-muted">{`Choose who gets it. Each one waits for your signature with ${parts.words.keyTitle}.`}</p>
              {agents.length === 0 ? (
                <p className="text-body text-muted">No agent with an MCP config was found yet. The server is kept, and you can give it later.</p>
              ) : (
                <div className="flex flex-col gap-1.5">
                  {agents.map((agent) => (
                    <label key={agent} className="flex cursor-pointer items-center gap-2.5 rounded-lg px-2 py-1.5 hover:bg-hover">
                      <input
                        type="checkbox"
                        checked={given.has(agent)}
                        onChange={() => {
                          const next = new Set(given);
                          if (next.has(agent)) next.delete(agent);
                          else next.add(agent);
                          setGiven(next);
                        }}
                      />
                      <BrandLogo agent={agent} name={agentLabel(agent)} size={20} />
                      <span className="text-body text-foreground">{agentLabel(agent)}</span>
                    </label>
                  ))}
                </div>
              )}
              <button type="button" className="mx-focus cursor-pointer self-start text-footnote text-muted underline" onClick={() => setAdvanced(!advanced)} aria-expanded={advanced}>
                {advanced ? 'Hide what will be written' : 'Show what will be written'}
              </button>
              {advanced && (
                <pre className="max-h-48 overflow-auto rounded-lg bg-card p-3 font-mono text-micro text-foreground">
                  {typeof preview === 'string' ? preview : JSON.stringify(preview, null, 2)}
                </pre>
              )}
            </>
          )}
          {problem !== undefined && (
            <p role="alert" className="text-footnote text-destructive">
              {problem}
            </p>
          )}
        </div>

        <footer className="flex items-center gap-2 border-t border-panel-edge px-5 py-3.5">
          {step > 0 && <KitButton onClick={() => setStep(step - 1)}>Back</KitButton>}
          <span className="flex-1" />
          {step < STEPS.length - 1 ? (
            <KitButton kind="primary" onClick={() => (step === 0 && typeof draft() === 'string' ? setProblem(draft() as string) : (setProblem(undefined), setStep(step + 1)))}>
              Continue
            </KitButton>
          ) : (
            <KitButton kind="primary" disabled={hub.busy !== undefined} onClick={() => void finish()}>
              Add server
            </KitButton>
          )}
        </footer>
      </div>
    </div>
  );
}

/** A remote server's headers, a credential kept as a secret from the moment its name is typed. */
function HeaderRows({ rows, change, field }: { rows: readonly HeaderRow[]; change: (rows: HeaderRow[]) => void; field: string }) {
  const update = (at: number, next: Partial<HeaderRow>) => change(rows.map((each, i) => (i === at ? { ...each, ...next } : each)));
  return (
    <div className="flex flex-col gap-2">
      <span className="text-footnote font-medium text-muted">Headers, optional</span>
      {rows.map((row, at) => (
        <div key={at} className="flex flex-wrap items-center gap-2">
          <input
            className={`${field} max-w-[170px] font-mono`}
            aria-label="Header name"
            placeholder="Authorization"
            value={row.name}
            // A credential header starts kept, and is kept while its name says it is one.
            onChange={(event) => update(at, { name: event.target.value, ...(isCredentialHeader(event.target.value) ? { secret: true } : {}) })}
          />
          <input
            className={`${field} min-w-[140px] flex-1`}
            aria-label="Header value"
            placeholder="Bearer your token"
            type={row.secret ? 'password' : 'text'}
            autoComplete="off"
            value={row.value}
            onChange={(event) => update(at, { value: event.target.value })}
          />
          <label className="flex items-center gap-1.5 text-footnote text-foreground" title={isCredentialHeader(row.name) ? 'This header carries a credential, so it is always kept as a secret.' : undefined}>
            <input type="checkbox" checked={row.secret} disabled={isCredentialHeader(row.name)} onChange={() => update(at, { secret: !row.secret })} />
            Keep as secret
          </label>
          <button type="button" aria-label="Remove this header" onClick={() => change(rows.filter((_, i) => i !== at))} className="mx-focus grid size-7 cursor-pointer place-items-center rounded-md text-muted hover:bg-hover">
            <Minus size={14} />
          </button>
        </div>
      ))}
      <div>
        <KitButton icon={Plus} onClick={() => change([...rows, { name: '', value: '', secret: false }])}>
          Add a header
        </KitButton>
      </div>
    </div>
  );
}

function Labelled({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-footnote font-medium text-muted">{label}</span>
      {children}
    </label>
  );
}

function Choice({ on, title, body, pick }: { on: boolean; title: string; body: string; pick: () => void }) {
  return (
    <button type="button" role="radio" aria-checked={on} onClick={pick} className={`mx-focus flex cursor-pointer flex-col gap-0.5 rounded-xl border px-3.5 py-3 text-left ${on ? 'border-primary bg-hover' : 'border-panel-edge hover:bg-hover'}`}>
      <span className="text-body font-medium text-foreground">{title}</span>
      <span className="text-footnote text-muted">{body}</span>
    </button>
  );
}
