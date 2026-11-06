import type { Effect } from './studio-lines';
import type { RuleAlternative, RuleMatchTable } from './rule-toml';

/**
 * The console's ready-made rules, word for word, ported from the Mac's `ReadyRuleLibrary.swift` so Windows and Linux
 * offer the same library a workspace starts from. `test/ready-rule-library.test.ts` reads the Swift file and fails
 * when the two drift apart.
 */

export type ReadyRuleCategory = 'code' | 'cloud' | 'deploys' | 'data' | 'money' | 'secrets' | 'reach';

/** The kinds of ready-made rule, in the console's library order. */
export const READY_RULE_CATEGORIES: readonly { id: ReadyRuleCategory; title: string }[] = [
  { id: 'code', title: 'Code and git' },
  { id: 'cloud', title: 'Cloud' },
  { id: 'deploys', title: 'Deploys' },
  { id: 'data', title: 'Databases' },
  { id: 'money', title: 'Money' },
  { id: 'secrets', title: 'Secrets and access' },
  { id: 'reach', title: 'Tools and network' },
];

/** What a ready-made rule is about: a product, drawn with its own logo, or a kind of act, drawn as a glyph. */
export const RULE_MARKS = [
  'github', 'vercel', 'netlify', 'railway', 'fly', 'docker', 'postgresql', 'mongodb', 'stripe', 'heroku',
  'mcp', 'git', 'files', 'key', 'terraform', 'kubernetes', 'cloud', 'production', 'access', 'message', 'network', 'package',
  'rocket', 'terminal', 'workflow', 'storage', 'settings', 'signin',
] as const;

export type RuleMark = (typeof RULE_MARKS)[number];

/** The Composio toolkit whose logo is the product's own, for the products that have a real mark there. */
const TOOLKITS: Partial<Record<RuleMark, string>> = {
  github: 'github',
  vercel: 'vercel',
  netlify: 'netlify',
  railway: 'railway',
  fly: 'fly',
  heroku: 'heroku',
  mongodb: 'mongodb',
  stripe: 'stripe',
  docker: 'docker_hub',
  postgresql: 'postgres',
};

/** The toolkit a mark draws its logo from, undefined for a kind of act or a CLI Composio has no real mark for. */
export function markToolkit(mark: RuleMark): string | undefined {
  return TOOLKITS[mark];
}

/** The glyph a kind of tool wears, named for the Mac's SF Symbol so both draw the same one; unknown tools are a terminal. */
export type ActionGlyph = 'asterisk' | 'branch' | 'pull' | 'doc' | 'puzzle' | 'globe' | 'cloud' | 'box' | 'stack' | 'send' | 'cylinder' | 'terminal';

const ACTION_GLYPHS: Readonly<Record<string, ActionGlyph>> = {
  '*': 'asterisk',
  git: 'branch',
  gh: 'pull',
  filesystem: 'doc',
  mcp: 'puzzle',
  http: 'globe',
  aws: 'cloud',
  gcloud: 'cloud',
  az: 'cloud',
  kubectl: 'box',
  docker: 'box',
  npm: 'box',
  terraform: 'stack',
  vercel: 'send',
  fly: 'send',
  heroku: 'send',
  netlify: 'send',
  psql: 'cylinder',
  mysql: 'cylinder',
};

/** The glyph for the first word of an action, as the Mac's `RuleSymbols.action` picks it. */
export function actionGlyph(action: string): ActionGlyph {
  return ACTION_GLYPHS[action.split('.')[0] ?? action] ?? 'terminal';
}

/** One square of a rule's stack of marks: a product's logo, a glyph for a kind of act, or one read from an action. */
export type MarkTile = { readonly kind: 'logo'; readonly toolkit: string } | { readonly kind: 'mark'; readonly mark: RuleMark } | { readonly kind: 'action'; readonly glyph: ActionGlyph };

/** At most four marks stand in the stack, and at most two glyphs read from actions, as the Mac's `RuleMarks` draws them. */
export const MOST_MARKS = 4;
export const MOST_ACTION_MARKS = 2;
/** How far each square tucks under the one before it, as a share of its side. */
export const MARK_OVERLAP_SHARE = 0.22;

/** The squares a rule's card stacks, in order: its marks, else the distinct glyphs of its actions. */
export function markTiles(marks: readonly RuleMark[], actions: readonly string[]): MarkTile[] {
  if (marks.length > 0) {
    return marks.slice(0, MOST_MARKS).map((mark) => {
      const toolkit = markToolkit(mark);
      return toolkit === undefined ? { kind: 'mark', mark } : { kind: 'logo', toolkit };
    });
  }
  const glyphs: ActionGlyph[] = [];
  for (const glyph of actions.map(actionGlyph)) if (!glyphs.includes(glyph)) glyphs.push(glyph);
  return glyphs.slice(0, MOST_ACTION_MARKS).map((glyph) => ({ kind: 'action', glyph }));
}

/** A ready-made rule as the console's library writes it: what it covers, the effect it is offered with, and why. */
export interface LibraryRule {
  /** Also the rule's name, so adding it twice is one rule rather than two. */
  readonly id: string;
  readonly category: ReadyRuleCategory;
  readonly title: string;
  /** One line on what it covers, in the words somebody would use. */
  readonly says: string;
  readonly recommended: Effect;
  /** Why that and not stricter, the end of the reason an agent is told. */
  readonly because: string;
  readonly marks: readonly RuleMark[];
  readonly match: RuleMatchTable;
  readonly alternative?: RuleAlternative;
}

/** The runtime's own first run set, so a new machine starts where `memnox protect` does. */
export const STARTER_SET: readonly string[] = [
  'keep-out-of-credentials', 'no-history-rewrites', 'ask-before-deleting-files', 'ask-before-mcp-changes',
  'ask-before-http-changes', 'ask-before-moving-money', 'ask-before-changing-production',
];

/** What changes something, as every classifier spells it. Reads go through. */
const changing = ['write', 'destructive', 'communication'];
/** A server tool nobody classified is treated as changing, since it may. */
const changingOrUnknown = [...changing, 'unknown'];
/** Action namespaces that stay on the machine that ran them. */
const localNamespaces = ['filesystem', 'file', 'fs', 'shell', 'process', 'git', 'editor', 'test', 'build', 'package'];
/** Everything that reaches outside the machine: every action but the local ones. */
const outsideThisMachine = ['*', ...localNamespaces.map((each) => `!${each}.*`)];
/** Credential directories and dotenv files; each directory is named as well as its contents. */
const credentialPaths = ['**/.ssh', '**/.ssh/**', '**/.aws', '**/.aws/**', '**/.gcloud', '**/.gcloud/**', '**/.kube', '**/.kube/**', '**/.env', '**/.env.*'];

const code: LibraryRule[] = [
  {
    id: 'no-history-rewrites', category: 'code', title: 'No force pushes or history rewrites',
    says: 'Force push, hard reset, branch -D, filter-repo and dropping stashes.', recommended: 'deny',
    because: 'it rewrites history somebody else may already have pulled', marks: ['git'],
    match: {
      actions: [
        'git.push-force', 'git.push-f', 'git.reset-hard', 'git.branch-d', 'git.branch-delete-force',
        'git.push-delete', 'git.clean-f', 'git.clean-fd', 'git.clean-force', 'git.reflog-expire',
        'git.reflog-delete', 'git.stash-clear', 'git.stash-drop', 'git.filter-branch', 'git.filter-repo',
        'git.gc-prune-now',
      ],
    },
    alternative: { action: 'git.push', note: 'Push a branch and open a pull request.' },
  },
  {
    id: 'ask-before-merge', category: 'code', title: 'Ask before merging a pull request',
    says: 'gh pr merge, and approving a review as somebody.', recommended: 'ask',
    because: 'a merge ships what nobody has looked at yet', marks: ['github'],
    match: { actions: ['gh.pr-merge', 'gh.pr-review-approve'] },
    alternative: { action: 'gh.pr-view', note: 'Leave the pull request open and let a person merge it.' },
  },
  {
    id: 'ask-before-github-deletes', category: 'code', title: 'Ask before deleting on GitHub',
    says: 'Repositories, releases, secrets, variables, workflow runs and DELETE calls.', recommended: 'ask',
    because: 'none of these come back once they are gone', marks: ['github'],
    match: {
      actions: [
        'gh.repo-delete', 'gh.release-delete', 'gh.secret-delete', 'gh.variable-delete', 'gh.run-delete',
        'gh.cache-delete', 'gh.api-x-delete', 'gh.api-method-delete',
      ],
    },
  },
  {
    id: 'ask-before-deleting-files', category: 'code', title: 'Ask before deleting files',
    says: 'rm -rf, dd, truncate and every other delete on this machine.', recommended: 'ask',
    because: 'sometimes it really is the build directory, so a person should look', marks: ['files'],
    match: { actions: ['filesystem.delete'] },
  },
  {
    id: 'ask-before-publishing', category: 'code', title: 'Ask before publishing a package or image',
    says: 'npm publish, unpublish, deprecate, dist-tag and docker push.', recommended: 'ask',
    because: 'whoever installs it next runs what was published', marks: ['package', 'docker'],
    match: { actions: ['npm.publish', 'npm.unpublish', 'npm.deprecate', 'npm.dist-tag-add', 'npm.dist-tag-rm', 'docker.push'] },
  },
  {
    id: 'ask-before-pushing', category: 'code', title: 'Ask before pushing to the remote',
    says: 'Every git push, for a team that reviews before anything leaves the laptop.', recommended: 'ask',
    because: 'a push is the moment work stops being only yours', marks: ['git'],
    match: { actions: ['git.push'] },
  },
  {
    id: 'ask-before-ci-changes', category: 'code', title: 'Ask before running or disabling CI',
    says: 'gh workflow run, enable and disable, and cancelling or rerunning a run.', recommended: 'ask',
    because: 'a workflow can deploy, publish or spend minutes on its own', marks: ['workflow', 'github'],
    match: { actions: ['gh.workflow-run', 'gh.workflow-enable', 'gh.workflow-disable', 'gh.run-cancel', 'gh.run-rerun'] },
  },
  {
    id: 'ask-before-repo-settings', category: 'code', title: 'Ask before changing a repository',
    says: 'Renaming, archiving or editing a repository, and transferring an issue.', recommended: 'ask',
    because: 'everybody who works in the repository feels the change', marks: ['settings', 'github'],
    match: { actions: ['gh.repo-edit', 'gh.repo-rename', 'gh.repo-archive', 'gh.issue-transfer'] },
  },
  {
    id: 'ask-before-closing-work', category: 'code', title: 'Ask before closing issues or pull requests',
    says: 'Closing, deleting or locking an issue or a pull request.', recommended: 'ask',
    because: "closing somebody's thread is a decision about their work", marks: ['github'],
    match: { actions: ['gh.issue-close', 'gh.issue-delete', 'gh.issue-lock', 'gh.pr-close', 'gh.pr-lock'] },
  },
];

const cloud: LibraryRule[] = [
  {
    id: 'ask-before-terraform', category: 'cloud', title: 'Ask before terraform apply or destroy',
    says: 'apply, destroy, state rm and deleting a workspace.', recommended: 'ask',
    because: 'a plan is cheap to read and an apply is not cheap to undo', marks: ['terraform'],
    match: { actions: ['terraform.apply', 'terraform.destroy', 'terraform.state-rm', 'terraform.workspace-delete'] },
    alternative: { action: 'terraform.plan', note: 'Run terraform plan and hand the plan to a person.' },
  },
  {
    id: 'ask-before-kubernetes-deletes', category: 'cloud', title: 'Ask before deleting from a cluster',
    says: 'kubectl delete of any kind, and draining a node.', recommended: 'ask',
    because: 'a namespace or a volume takes everything inside it along', marks: ['kubernetes'],
    match: { actions: ['kubectl.delete', 'kubectl.delete-namespace', 'kubectl.delete-deployment', 'kubectl.delete-pvc', 'kubectl.drain'] },
  },
  {
    id: 'ask-before-cloud-deletes', category: 'cloud', title: 'Ask before deleting cloud resources',
    says: 'Anything destructive through the aws, gcloud or az CLIs.', recommended: 'ask',
    because: 'listing and describing is how an agent finds its way, deleting is not', marks: ['cloud'],
    match: { actions: ['aws.*', 'gcloud.*', 'az.*'], classes: ['destructive'] },
  },
  {
    id: 'ask-before-docker-deletes', category: 'cloud', title: 'Ask before deleting containers, images or volumes',
    says: 'docker rm, rmi, every prune, and compose down with volumes.', recommended: 'ask',
    because: 'a volume holds data nothing else has a copy of', marks: ['docker'],
    match: {
      actions: [
        'docker.rm', 'docker.rmi', 'docker.rmi-f', 'docker.container-rm', 'docker.image-rm', 'docker.volume-rm',
        'docker.network-rm', 'docker.system-prune', 'docker.system-prune-a', 'docker.container-prune',
        'docker.image-prune', 'docker.volume-prune', 'docker.compose-down-volumes',
      ],
    },
  },
  {
    id: 'no-bucket-deletes', category: 'cloud', title: 'No deleting storage buckets',
    says: 'aws s3 rb, recursive s3 rm, and gcloud storage rm.', recommended: 'deny',
    because: 'a bucket emptied by an agent is rarely one anybody backed up', marks: ['storage'],
    match: { actions: ['aws.s3-rb', 'aws.s3-rm', 'aws.s3-rm-recursive', 'gcloud.storage-rm'] },
    alternative: { action: 'aws.s3-ls', note: 'List what is there, and let a person remove it.' },
  },
  {
    id: 'ask-before-cluster-changes', category: 'cloud', title: 'Ask before changing a cluster',
    says: 'kubectl apply, patch, replace, scale, edit, rollouts, cordon and taint.', recommended: 'ask',
    because: 'a cluster runs what your users are using right now', marks: ['kubernetes'],
    match: {
      actions: [
        'kubectl.apply', 'kubectl.patch', 'kubectl.replace', 'kubectl.scale', 'kubectl.set', 'kubectl.edit',
        'kubectl.rollout-restart', 'kubectl.rollout-undo', 'kubectl.rollout-pause', 'kubectl.cordon', 'kubectl.taint',
      ],
    },
    alternative: { action: 'kubectl.get', note: 'Read the cluster, and hand the change to a person.' },
  },
  {
    id: 'ask-before-shell-in-pod', category: 'cloud', title: 'Ask before getting inside a running pod',
    says: 'kubectl exec, debug, attach, cp and port-forward.', recommended: 'ask',
    because: 'inside a pod an agent is past every other rule you wrote', marks: ['terminal', 'kubernetes'],
    match: { actions: ['kubectl.exec', 'kubectl.debug', 'kubectl.attach', 'kubectl.cp', 'kubectl.port-forward'] },
  },
  {
    id: 'ask-before-terraform-state', category: 'cloud', title: 'Ask before editing terraform state',
    says: 'state mv, push and replace-provider, import, taint and force-unlock.', recommended: 'ask',
    because: 'state that disagrees with the world is how the next apply goes wrong', marks: ['terraform'],
    match: {
      actions: [
        'terraform.state-mv', 'terraform.state-push', 'terraform.state-replace-provider', 'terraform.import',
        'terraform.taint', 'terraform.untaint', 'terraform.force-unlock',
      ],
    },
  },
];

const deploys: LibraryRule[] = [
  {
    id: 'ask-before-production-deploys', category: 'deploys', title: 'Ask before a production deploy',
    says: 'Vercel and Netlify production deploys, Railway and Fly deploys, promotes and rollbacks.', recommended: 'ask',
    because: 'a preview is for the agent and production is for your users', marks: ['vercel', 'netlify', 'railway', 'fly'],
    match: {
      actions: [
        'vercel.deploy-prod', 'vercel.prod', 'vercel.promote', 'vercel.rollback', 'netlify.deploy-prod',
        'railway.up', 'railway.redeploy', 'railway.down', 'fly.deploy', 'gcloud.deploy',
      ],
    },
  },
  {
    id: 'ask-before-changing-production', category: 'deploys', title: 'Ask before any change in production',
    says: 'Every write, delete or message in an environment named like prod, production or live.', recommended: 'ask',
    because: 'reading production is how an incident gets understood, and changing it is where one gets made',
    marks: ['production'],
    match: { actions: outsideThisMachine, environments: ['prod*', 'production', 'live'], classes: changing },
  },
  {
    id: 'no-destroying-apps', category: 'deploys', title: 'No destroying a whole app or project',
    says: 'fly apps destroy, heroku apps:destroy, netlify sites:delete and gcloud projects delete.', recommended: 'deny',
    because: 'an app destroyed takes its domains, data and history along', marks: ['fly', 'heroku', 'netlify'],
    match: {
      actions: [
        'fly.apps-destroy', 'heroku.apps:destroy', 'netlify.sites:delete', 'gcloud.projects-delete',
        'vercel.project-rm', 'railway.delete',
      ],
    },
  },
  {
    id: 'ask-before-hosting-deletes', category: 'deploys', title: 'Ask before removing domains, deployments or volumes',
    says: 'Vercel domains, DNS and deployments, and Railway environments and volumes.', recommended: 'ask',
    because: 'a removed domain or volume is an outage before it is a cleanup', marks: ['vercel', 'railway'],
    match: {
      actions: [
        'vercel.domains-rm', 'vercel.dns-rm', 'vercel.remove', 'vercel.rm', 'railway.environment-delete',
        'railway.volume-delete',
      ],
    },
  },
  {
    id: 'ask-before-any-deploy', category: 'deploys', title: 'Ask before any deploy, through any tool',
    says: 'Anything that puts code in front of users, whatever CLI or MCP tool does it.', recommended: 'ask',
    because: 'a deploy is the change your users notice first', marks: ['rocket'],
    match: { actions: outsideThisMachine, capabilities: ['deploy'] },
  },
];

const data: LibraryRule[] = [
  {
    id: 'ask-before-database-writes', category: 'data', title: 'Ask before writing to a database',
    says: 'Anything that changes data through psql, mysql or mongosh.', recommended: 'ask',
    because: 'a query is how an agent learns the shape, and a write is a change somebody owns',
    marks: ['postgresql', 'mongodb'],
    match: { actions: ['psql.*', 'mysql.*', 'mongosh.*'], classes: changing },
  },
  {
    id: 'ask-before-database-mcp-changes', category: 'data', title: 'Ask before a database MCP tool changes data',
    says: 'Postgres, Supabase, Neon and MongoDB MCP servers. Queries go through.', recommended: 'ask',
    because: 'a write through a server leaves nothing on this machine to rewind', marks: ['postgresql', 'mongodb'],
    match: { actions: ['mcp.postgres*', 'mcp.supabase.*', 'mcp.neon.*', 'mcp.mongo*'], classes: changingOrUnknown },
  },
];

const money: LibraryRule[] = [
  {
    id: 'ask-before-moving-money', category: 'money', title: 'Ask before moving money',
    says: 'A refund, a payout, a charge or a transfer, through any tool.', recommended: 'ask',
    because: 'money that has moved is the hardest change of all to take back', marks: ['stripe'],
    match: { actions: outsideThisMachine, capabilities: ['transfer'] },
  },
  {
    id: 'ask-before-stripe-changes', category: 'money', title: 'Ask before any Stripe change',
    says: 'Every Stripe CLI and Stripe MCP call that is not a read.', recommended: 'ask',
    because: 'customers, subscriptions and invoices are your revenue', marks: ['stripe'],
    match: { actions: ['stripe.*', 'mcp.stripe.*'], classes: changingOrUnknown },
  },
  {
    id: 'no-payouts-or-transfers', category: 'money', title: 'No payouts, transfers or refunds by an agent',
    says: 'stripe payouts, transfers and refunds create, refused outright.', recommended: 'deny',
    because: 'money sent out is money a person should have sent', marks: ['stripe'],
    match: { actions: ['stripe.payouts-create', 'stripe.transfers-create', 'stripe.refunds-create'] },
    alternative: { action: 'stripe.retrieve', note: 'Look the charge up, and let a person refund it.' },
  },
  {
    id: 'ask-before-billing-changes', category: 'money', title: 'Ask before changing a subscription or invoice',
    says: 'Cancelling a subscription, paying, voiding or sending an invoice, deleting a customer.', recommended: 'ask',
    because: 'a customer feels these the moment they happen', marks: ['stripe'],
    match: {
      actions: [
        'stripe.subscriptions-cancel', 'stripe.invoices-pay', 'stripe.void_invoice', 'stripe.finalize_invoice',
        'stripe.send_invoice', 'stripe.mark_uncollectible', 'stripe.customers-delete',
      ],
    },
  },
];

const secrets: LibraryRule[] = [
  {
    id: 'keep-out-of-credentials', category: 'secrets', title: 'Keep agents out of credentials',
    says: '~/.ssh, ~/.aws, ~/.kube, .env files, and variables named like a key or token.', recommended: 'deny',
    because: "almost no task needs the key itself, and a leaked one is somebody's weekend", marks: ['key'],
    match: {
      actions: ['filesystem.read', 'environment.read'],
      targets: [
        ...credentialPaths,
        '!**/.env.example', '!**/.env.sample', '!**/.env.template', 'all', '*_KEY', '*_KEYS', '*_SECRET',
        '*_TOKEN', '*_PASSWORD', '*_CREDENTIALS', 'DATABASE_URL', 'MONGODB_URI', 'REDIS_URL',
      ],
    },
  },
  {
    id: 'ask-before-granting-access', category: 'secrets', title: 'Ask before handing out access',
    says: 'A new admin, a changed role or an IAM change, through any tool.', recommended: 'ask',
    because: "who may do what should be a person's decision", marks: ['access'],
    match: { actions: outsideThisMachine, capabilities: ['admin'] },
  },
  {
    id: 'ask-before-secret-changes', category: 'secrets', title: 'Ask before changing secrets or env vars',
    says: 'GitHub secrets and variables, Vercel env, Railway variables.', recommended: 'ask',
    because: 'a changed secret breaks whatever was reading the old one', marks: ['key', 'github', 'vercel'],
    match: {
      actions: [
        'gh.secret-set', 'gh.secret-delete', 'gh.variable-set', 'gh.variable-delete', 'vercel.env-add',
        'vercel.env-rm', 'railway.variable-set', 'railway.variables-set', 'railway.variable-delete',
      ],
    },
  },
  {
    id: 'ask-before-cli-sign-in', category: 'secrets', title: 'Ask before signing a CLI in or out',
    says: 'gh auth, docker login, stripe login and logout.', recommended: 'ask',
    because: 'signing in decides whose account every later command acts as', marks: ['signin'],
    match: { actions: ['gh.auth-login', 'gh.auth-logout', 'docker.login', 'stripe.login', 'stripe.logout'] },
  },
  {
    id: 'ask-before-iam-changes', category: 'secrets', title: 'Ask before AWS IAM changes',
    says: 'Any aws iam command that creates, attaches or deletes.', recommended: 'ask',
    because: 'an IAM change is a new answer to who may do anything at all', marks: ['access', 'cloud'],
    match: { actions: ['aws.iam', 'aws.iam-delete'] },
  },
  {
    id: 'ask-before-package-owners', category: 'secrets', title: 'Ask before changing who can publish',
    says: 'npm owner add and rm, npm access and npm token.', recommended: 'ask',
    because: 'an owner added today publishes under your name tomorrow', marks: ['package'],
    match: { actions: ['npm.owner-add', 'npm.owner-rm', 'npm.access', 'npm.token'] },
  },
];

const reach: LibraryRule[] = [
  {
    id: 'ask-before-mcp-changes', category: 'reach', title: 'Ask before an MCP tool changes something',
    says: 'Any MCP call that writes, deletes or sends. Lists and reads go through.', recommended: 'ask',
    because: 'these are the calls whose consequences other people see', marks: ['mcp'],
    match: { actions: ['mcp.*'], classes: changingOrUnknown },
  },
  {
    id: 'ask-before-sending-messages', category: 'reach', title: 'Ask before an agent messages people',
    says: 'A comment, an email, a chat message or a review, through any tool.', recommended: 'ask',
    because: 'the people receiving it never agreed to hear from an agent', marks: ['message'],
    match: { actions: outsideThisMachine, classes: ['communication'] },
  },
  {
    id: 'ask-before-http-changes', category: 'reach', title: 'Ask before changing another host over HTTP',
    says: 'POST, PUT, PATCH and DELETE requests. Fetching a page goes through.', recommended: 'ask',
    because: "a change on somebody else's server is somebody else's state", marks: ['network'],
    match: { actions: ['http.request'], arguments: [{ name: 'method', values: ['POST', 'PUT', 'PATCH', 'DELETE', 'UNKNOWN'] }] },
  },
  {
    id: 'no-mcp-deletes', category: 'reach', title: 'No MCP tool that deletes',
    says: 'Any MCP call classified as destructive, refused outright.', recommended: 'deny',
    because: 'a tool that deletes through a server leaves nothing on this machine to rewind', marks: ['mcp'],
    match: { actions: ['mcp.*'], classes: ['destructive'] },
  },
];

/** Every library rule in category order. */
export const LIBRARY_RULES: readonly LibraryRule[] = [...code, ...cloud, ...deploys, ...data, ...money, ...secrets, ...reach];
