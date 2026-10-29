import Foundation

/// The kinds of ready-made rule, in the console's library order.
public enum ReadyRuleCategory: String, CaseIterable, Equatable, Sendable {
    case code, cloud, deploys, data, money, secrets, reach

    public var title: String {
        switch self {
        case .code: "Code and git"
        case .cloud: "Cloud"
        case .deploys: "Deploys"
        case .data: "Databases"
        case .money: "Money"
        case .secrets: "Secrets and access"
        case .reach: "Tools and network"
        }
    }
}

/// What a ready-made rule is about: a product, drawn with its own logo, or a kind of act, drawn as a glyph.
public enum RuleMark: String, CaseIterable, Equatable, Sendable {
    case github, vercel, netlify, railway, fly, docker, postgresql, mongodb, stripe, heroku
    case mcp, git, files, key, terraform, kubernetes, cloud, production, access, message, network, package
    case rocket, terminal, workflow, storage, settings, signin

    /// The Composio toolkit whose logo is the product's own, nil for a kind of act or a CLI Composio has no real mark for.
    public var toolkit: String? {
        switch self {
        case .github, .vercel, .netlify, .railway, .fly, .heroku, .mongodb, .stripe: rawValue
        case .docker: "docker_hub"
        case .postgresql: "postgres"
        case .mcp, .git, .files, .key, .terraform, .kubernetes, .cloud, .production, .access, .message, .network,
             .package, .rocket, .terminal, .workflow, .storage, .settings, .signin: nil
        }
    }
}

/// A ready-made rule as the console's library writes it: what it covers, the effect it is offered with, and why.
public struct LibraryRule: Equatable, Sendable {
    /// Also the rule's name, so adding it twice is one rule rather than two.
    public let id: String
    public let category: ReadyRuleCategory
    public let title: String
    /// One line on what it covers, in the words somebody would use.
    public let says: String
    public let recommended: RuleEffect
    /// Why that and not stricter, the end of the reason an agent is told.
    public let because: String
    public let marks: [RuleMark]
    public let match: RuleMatchTable
    public let alternative: RuleAlternative?

    init(_ id: String, _ category: ReadyRuleCategory, _ title: String, says: String, recommended: RuleEffect,
         because: String, marks: [RuleMark], match: RuleMatchTable, alternative: RuleAlternative? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.says = says
        self.recommended = recommended
        self.because = because
        self.marks = marks
        self.match = match
        self.alternative = alternative
    }
}

/// The console's ready-made rules, word for word, so this Mac offers the same library a workspace starts from.
public enum ReadyRuleLibrary {
    /// The runtime's own first run set, so a new machine starts where `memnox protect` does.
    public static let starterSet = [
        "keep-out-of-credentials", "no-history-rewrites", "ask-before-deleting-files", "ask-before-mcp-changes",
        "ask-before-http-changes", "ask-before-moving-money", "ask-before-changing-production",
    ]

    /// What changes something, as every classifier spells it. Reads go through.
    private static let changing = ["write", "destructive", "communication"]
    /// A server tool nobody classified is treated as changing, since it may.
    private static let changingOrUnknown = changing + ["unknown"]
    /// Action namespaces that stay on the machine that ran them.
    private static let localNamespaces = ["filesystem", "file", "fs", "shell", "process", "git", "editor", "test", "build", "package"]
    /// Everything that reaches outside the machine: every action but the local ones.
    private static let outsideThisMachine = ["*"] + localNamespaces.map { "!\($0).*" }
    /// Credential directories and dotenv files; each directory is named as well as its contents.
    private static let credentialPaths = [
        "**/.ssh", "**/.ssh/**", "**/.aws", "**/.aws/**", "**/.gcloud", "**/.gcloud/**", "**/.kube", "**/.kube/**",
        "**/.env", "**/.env.*",
    ]

    public static let rules: [LibraryRule] = code + cloud + deploys + data + money + secrets + reach

    private static let code: [LibraryRule] = [
        LibraryRule("no-history-rewrites", .code, "No force pushes or history rewrites",
                    says: "Force push, hard reset, branch -D, filter-repo and dropping stashes.", recommended: .deny,
                    because: "it rewrites history somebody else may already have pulled", marks: [.git],
                    match: RuleMatchTable(actions: [
                        "git.push-force", "git.push-f", "git.reset-hard", "git.branch-d", "git.branch-delete-force",
                        "git.push-delete", "git.clean-f", "git.clean-fd", "git.clean-force", "git.reflog-expire",
                        "git.reflog-delete", "git.stash-clear", "git.stash-drop", "git.filter-branch", "git.filter-repo",
                        "git.gc-prune-now",
                    ]),
                    alternative: RuleAlternative(action: "git.push", note: "Push a branch and open a pull request.")),
        LibraryRule("ask-before-merge", .code, "Ask before merging a pull request",
                    says: "gh pr merge, and approving a review as somebody.", recommended: .ask,
                    because: "a merge ships what nobody has looked at yet", marks: [.github],
                    match: RuleMatchTable(actions: ["gh.pr-merge", "gh.pr-review-approve"]),
                    alternative: RuleAlternative(action: "gh.pr-view", note: "Leave the pull request open and let a person merge it.")),
        LibraryRule("ask-before-github-deletes", .code, "Ask before deleting on GitHub",
                    says: "Repositories, releases, secrets, variables, workflow runs and DELETE calls.", recommended: .ask,
                    because: "none of these come back once they are gone", marks: [.github],
                    match: RuleMatchTable(actions: [
                        "gh.repo-delete", "gh.release-delete", "gh.secret-delete", "gh.variable-delete", "gh.run-delete",
                        "gh.cache-delete", "gh.api-x-delete", "gh.api-method-delete",
                    ])),
        LibraryRule("ask-before-deleting-files", .code, "Ask before deleting files",
                    says: "rm -rf, dd, truncate and every other delete on this machine.", recommended: .ask,
                    because: "sometimes it really is the build directory, so a person should look", marks: [.files],
                    match: RuleMatchTable(actions: ["filesystem.delete"])),
        LibraryRule("ask-before-publishing", .code, "Ask before publishing a package or image",
                    says: "npm publish, unpublish, deprecate, dist-tag and docker push.", recommended: .ask,
                    because: "whoever installs it next runs what was published", marks: [.package, .docker],
                    match: RuleMatchTable(actions: [
                        "npm.publish", "npm.unpublish", "npm.deprecate", "npm.dist-tag-add", "npm.dist-tag-rm", "docker.push",
                    ])),
        LibraryRule("ask-before-pushing", .code, "Ask before pushing to the remote",
                    says: "Every git push, for a team that reviews before anything leaves the laptop.", recommended: .ask,
                    because: "a push is the moment work stops being only yours", marks: [.git],
                    match: RuleMatchTable(actions: ["git.push"])),
        LibraryRule("ask-before-ci-changes", .code, "Ask before running or disabling CI",
                    says: "gh workflow run, enable and disable, and cancelling or rerunning a run.", recommended: .ask,
                    because: "a workflow can deploy, publish or spend minutes on its own", marks: [.workflow, .github],
                    match: RuleMatchTable(actions: [
                        "gh.workflow-run", "gh.workflow-enable", "gh.workflow-disable", "gh.run-cancel", "gh.run-rerun",
                    ])),
        LibraryRule("ask-before-repo-settings", .code, "Ask before changing a repository",
                    says: "Renaming, archiving or editing a repository, and transferring an issue.", recommended: .ask,
                    because: "everybody who works in the repository feels the change", marks: [.settings, .github],
                    match: RuleMatchTable(actions: ["gh.repo-edit", "gh.repo-rename", "gh.repo-archive", "gh.issue-transfer"])),
        LibraryRule("ask-before-closing-work", .code, "Ask before closing issues or pull requests",
                    says: "Closing, deleting or locking an issue or a pull request.", recommended: .ask,
                    because: "closing somebody's thread is a decision about their work", marks: [.github],
                    match: RuleMatchTable(actions: ["gh.issue-close", "gh.issue-delete", "gh.issue-lock", "gh.pr-close", "gh.pr-lock"])),
    ]

    private static let cloud: [LibraryRule] = [
        LibraryRule("ask-before-terraform", .cloud, "Ask before terraform apply or destroy",
                    says: "apply, destroy, state rm and deleting a workspace.", recommended: .ask,
                    because: "a plan is cheap to read and an apply is not cheap to undo", marks: [.terraform],
                    match: RuleMatchTable(actions: ["terraform.apply", "terraform.destroy", "terraform.state-rm", "terraform.workspace-delete"]),
                    alternative: RuleAlternative(action: "terraform.plan", note: "Run terraform plan and hand the plan to a person.")),
        LibraryRule("ask-before-kubernetes-deletes", .cloud, "Ask before deleting from a cluster",
                    says: "kubectl delete of any kind, and draining a node.", recommended: .ask,
                    because: "a namespace or a volume takes everything inside it along", marks: [.kubernetes],
                    match: RuleMatchTable(actions: [
                        "kubectl.delete", "kubectl.delete-namespace", "kubectl.delete-deployment", "kubectl.delete-pvc", "kubectl.drain",
                    ])),
        LibraryRule("ask-before-cloud-deletes", .cloud, "Ask before deleting cloud resources",
                    says: "Anything destructive through the aws, gcloud or az CLIs.", recommended: .ask,
                    because: "listing and describing is how an agent finds its way, deleting is not", marks: [.cloud],
                    match: RuleMatchTable(actions: ["aws.*", "gcloud.*", "az.*"], classes: ["destructive"])),
        LibraryRule("ask-before-docker-deletes", .cloud, "Ask before deleting containers, images or volumes",
                    says: "docker rm, rmi, every prune, and compose down with volumes.", recommended: .ask,
                    because: "a volume holds data nothing else has a copy of", marks: [.docker],
                    match: RuleMatchTable(actions: [
                        "docker.rm", "docker.rmi", "docker.rmi-f", "docker.container-rm", "docker.image-rm", "docker.volume-rm",
                        "docker.network-rm", "docker.system-prune", "docker.system-prune-a", "docker.container-prune",
                        "docker.image-prune", "docker.volume-prune", "docker.compose-down-volumes",
                    ])),
        LibraryRule("no-bucket-deletes", .cloud, "No deleting storage buckets",
                    says: "aws s3 rb, recursive s3 rm, and gcloud storage rm.", recommended: .deny,
                    because: "a bucket emptied by an agent is rarely one anybody backed up", marks: [.storage],
                    match: RuleMatchTable(actions: ["aws.s3-rb", "aws.s3-rm", "aws.s3-rm-recursive", "gcloud.storage-rm"]),
                    alternative: RuleAlternative(action: "aws.s3-ls", note: "List what is there, and let a person remove it.")),
        LibraryRule("ask-before-cluster-changes", .cloud, "Ask before changing a cluster",
                    says: "kubectl apply, patch, replace, scale, edit, rollouts, cordon and taint.", recommended: .ask,
                    because: "a cluster runs what your users are using right now", marks: [.kubernetes],
                    match: RuleMatchTable(actions: [
                        "kubectl.apply", "kubectl.patch", "kubectl.replace", "kubectl.scale", "kubectl.set", "kubectl.edit",
                        "kubectl.rollout-restart", "kubectl.rollout-undo", "kubectl.rollout-pause", "kubectl.cordon", "kubectl.taint",
                    ]),
                    alternative: RuleAlternative(action: "kubectl.get", note: "Read the cluster, and hand the change to a person.")),
        LibraryRule("ask-before-shell-in-pod", .cloud, "Ask before getting inside a running pod",
                    says: "kubectl exec, debug, attach, cp and port-forward.", recommended: .ask,
                    because: "inside a pod an agent is past every other rule you wrote", marks: [.terminal, .kubernetes],
                    match: RuleMatchTable(actions: ["kubectl.exec", "kubectl.debug", "kubectl.attach", "kubectl.cp", "kubectl.port-forward"])),
        LibraryRule("ask-before-terraform-state", .cloud, "Ask before editing terraform state",
                    says: "state mv, push and replace-provider, import, taint and force-unlock.", recommended: .ask,
                    because: "state that disagrees with the world is how the next apply goes wrong", marks: [.terraform],
                    match: RuleMatchTable(actions: [
                        "terraform.state-mv", "terraform.state-push", "terraform.state-replace-provider", "terraform.import",
                        "terraform.taint", "terraform.untaint", "terraform.force-unlock",
                    ])),
    ]

    private static let deploys: [LibraryRule] = [
        LibraryRule("ask-before-production-deploys", .deploys, "Ask before a production deploy",
                    says: "Vercel and Netlify production deploys, Railway and Fly deploys, promotes and rollbacks.", recommended: .ask,
                    because: "a preview is for the agent and production is for your users", marks: [.vercel, .netlify, .railway, .fly],
                    match: RuleMatchTable(actions: [
                        "vercel.deploy-prod", "vercel.prod", "vercel.promote", "vercel.rollback", "netlify.deploy-prod",
                        "railway.up", "railway.redeploy", "railway.down", "fly.deploy", "gcloud.deploy",
                    ])),
        LibraryRule("ask-before-changing-production", .deploys, "Ask before any change in production",
                    says: "Every write, delete or message in an environment named like prod, production or live.", recommended: .ask,
                    because: "reading production is how an incident gets understood, and changing it is where one gets made",
                    marks: [.production],
                    match: RuleMatchTable(actions: outsideThisMachine, environments: ["prod*", "production", "live"], classes: changing)),
        LibraryRule("no-destroying-apps", .deploys, "No destroying a whole app or project",
                    says: "fly apps destroy, heroku apps:destroy, netlify sites:delete and gcloud projects delete.", recommended: .deny,
                    because: "an app destroyed takes its domains, data and history along", marks: [.fly, .heroku, .netlify],
                    match: RuleMatchTable(actions: [
                        "fly.apps-destroy", "heroku.apps:destroy", "netlify.sites:delete", "gcloud.projects-delete",
                        "vercel.project-rm", "railway.delete",
                    ])),
        LibraryRule("ask-before-hosting-deletes", .deploys, "Ask before removing domains, deployments or volumes",
                    says: "Vercel domains, DNS and deployments, and Railway environments and volumes.", recommended: .ask,
                    because: "a removed domain or volume is an outage before it is a cleanup", marks: [.vercel, .railway],
                    match: RuleMatchTable(actions: [
                        "vercel.domains-rm", "vercel.dns-rm", "vercel.remove", "vercel.rm", "railway.environment-delete",
                        "railway.volume-delete",
                    ])),
        LibraryRule("ask-before-any-deploy", .deploys, "Ask before any deploy, through any tool",
                    says: "Anything that puts code in front of users, whatever CLI or MCP tool does it.", recommended: .ask,
                    because: "a deploy is the change your users notice first", marks: [.rocket],
                    match: RuleMatchTable(actions: outsideThisMachine, capabilities: ["deploy"])),
    ]

    private static let data: [LibraryRule] = [
        LibraryRule("ask-before-database-writes", .data, "Ask before writing to a database",
                    says: "Anything that changes data through psql, mysql or mongosh.", recommended: .ask,
                    because: "a query is how an agent learns the shape, and a write is a change somebody owns",
                    marks: [.postgresql, .mongodb],
                    match: RuleMatchTable(actions: ["psql.*", "mysql.*", "mongosh.*"], classes: changing)),
        LibraryRule("ask-before-database-mcp-changes", .data, "Ask before a database MCP tool changes data",
                    says: "Postgres, Supabase, Neon and MongoDB MCP servers. Queries go through.", recommended: .ask,
                    because: "a write through a server leaves nothing on this machine to rewind", marks: [.postgresql, .mongodb],
                    match: RuleMatchTable(actions: ["mcp.postgres*", "mcp.supabase.*", "mcp.neon.*", "mcp.mongo*"],
                                          classes: changingOrUnknown)),
    ]

    private static let money: [LibraryRule] = [
        LibraryRule("ask-before-moving-money", .money, "Ask before moving money",
                    says: "A refund, a payout, a charge or a transfer, through any tool.", recommended: .ask,
                    because: "money that has moved is the hardest change of all to take back", marks: [.stripe],
                    match: RuleMatchTable(actions: outsideThisMachine, capabilities: ["transfer"])),
        LibraryRule("ask-before-stripe-changes", .money, "Ask before any Stripe change",
                    says: "Every Stripe CLI and Stripe MCP call that is not a read.", recommended: .ask,
                    because: "customers, subscriptions and invoices are your revenue", marks: [.stripe],
                    match: RuleMatchTable(actions: ["stripe.*", "mcp.stripe.*"], classes: changingOrUnknown)),
        LibraryRule("no-payouts-or-transfers", .money, "No payouts, transfers or refunds by an agent",
                    says: "stripe payouts, transfers and refunds create, refused outright.", recommended: .deny,
                    because: "money sent out is money a person should have sent", marks: [.stripe],
                    match: RuleMatchTable(actions: ["stripe.payouts-create", "stripe.transfers-create", "stripe.refunds-create"]),
                    alternative: RuleAlternative(action: "stripe.retrieve", note: "Look the charge up, and let a person refund it.")),
        LibraryRule("ask-before-billing-changes", .money, "Ask before changing a subscription or invoice",
                    says: "Cancelling a subscription, paying, voiding or sending an invoice, deleting a customer.", recommended: .ask,
                    because: "a customer feels these the moment they happen", marks: [.stripe],
                    match: RuleMatchTable(actions: [
                        "stripe.subscriptions-cancel", "stripe.invoices-pay", "stripe.void_invoice", "stripe.finalize_invoice",
                        "stripe.send_invoice", "stripe.mark_uncollectible", "stripe.customers-delete",
                    ])),
    ]

    private static let secrets: [LibraryRule] = [
        LibraryRule("keep-out-of-credentials", .secrets, "Keep agents out of credentials",
                    says: "~/.ssh, ~/.aws, ~/.kube, .env files, and variables named like a key or token.", recommended: .deny,
                    because: "almost no task needs the key itself, and a leaked one is somebody's weekend", marks: [.key],
                    match: RuleMatchTable(actions: ["filesystem.read", "environment.read"], targets: credentialPaths + [
                        "!**/.env.example", "!**/.env.sample", "!**/.env.template", "all", "*_KEY", "*_KEYS", "*_SECRET",
                        "*_TOKEN", "*_PASSWORD", "*_CREDENTIALS", "DATABASE_URL", "MONGODB_URI", "REDIS_URL",
                    ])),
        LibraryRule("ask-before-granting-access", .secrets, "Ask before handing out access",
                    says: "A new admin, a changed role or an IAM change, through any tool.", recommended: .ask,
                    because: "who may do what should be a person's decision", marks: [.access],
                    match: RuleMatchTable(actions: outsideThisMachine, capabilities: ["admin"])),
        LibraryRule("ask-before-secret-changes", .secrets, "Ask before changing secrets or env vars",
                    says: "GitHub secrets and variables, Vercel env, Railway variables.", recommended: .ask,
                    because: "a changed secret breaks whatever was reading the old one", marks: [.key, .github, .vercel],
                    match: RuleMatchTable(actions: [
                        "gh.secret-set", "gh.secret-delete", "gh.variable-set", "gh.variable-delete", "vercel.env-add",
                        "vercel.env-rm", "railway.variable-set", "railway.variables-set", "railway.variable-delete",
                    ])),
        LibraryRule("ask-before-cli-sign-in", .secrets, "Ask before signing a CLI in or out",
                    says: "gh auth, docker login, stripe login and logout.", recommended: .ask,
                    because: "signing in decides whose account every later command acts as", marks: [.signin],
                    match: RuleMatchTable(actions: ["gh.auth-login", "gh.auth-logout", "docker.login", "stripe.login", "stripe.logout"])),
        LibraryRule("ask-before-iam-changes", .secrets, "Ask before AWS IAM changes",
                    says: "Any aws iam command that creates, attaches or deletes.", recommended: .ask,
                    because: "an IAM change is a new answer to who may do anything at all", marks: [.access, .cloud],
                    match: RuleMatchTable(actions: ["aws.iam", "aws.iam-delete"])),
        LibraryRule("ask-before-package-owners", .secrets, "Ask before changing who can publish",
                    says: "npm owner add and rm, npm access and npm token.", recommended: .ask,
                    because: "an owner added today publishes under your name tomorrow", marks: [.package],
                    match: RuleMatchTable(actions: ["npm.owner-add", "npm.owner-rm", "npm.access", "npm.token"])),
    ]

    private static let reach: [LibraryRule] = [
        LibraryRule("ask-before-mcp-changes", .reach, "Ask before an MCP tool changes something",
                    says: "Any MCP call that writes, deletes or sends. Lists and reads go through.", recommended: .ask,
                    because: "these are the calls whose consequences other people see", marks: [.mcp],
                    match: RuleMatchTable(actions: ["mcp.*"], classes: changingOrUnknown)),
        LibraryRule("ask-before-sending-messages", .reach, "Ask before an agent messages people",
                    says: "A comment, an email, a chat message or a review, through any tool.", recommended: .ask,
                    because: "the people receiving it never agreed to hear from an agent", marks: [.message],
                    match: RuleMatchTable(actions: outsideThisMachine, classes: ["communication"])),
        LibraryRule("ask-before-http-changes", .reach, "Ask before changing another host over HTTP",
                    says: "POST, PUT, PATCH and DELETE requests. Fetching a page goes through.", recommended: .ask,
                    because: "a change on somebody else's server is somebody else's state", marks: [.network],
                    match: RuleMatchTable(actions: ["http.request"],
                                          arguments: [RuleArgument("method", ["POST", "PUT", "PATCH", "DELETE", "UNKNOWN"])])),
        LibraryRule("no-mcp-deletes", .reach, "No MCP tool that deletes",
                    says: "Any MCP call classified as destructive, refused outright.", recommended: .deny,
                    because: "a tool that deletes through a server leaves nothing on this machine to rewind", marks: [.mcp],
                    match: RuleMatchTable(actions: ["mcp.*"], classes: ["destructive"])),
    ]
}
