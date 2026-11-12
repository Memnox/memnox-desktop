# The wire

A copy of the wire memnox-runtime builds from `packages/core/src/wire.ts`: the daemon's methods, requests,
responses and events as the Windows and Linux app imports them under `@memnox/core/wire`. It is kept here so
this repo builds and tests alone, with no second repo checked out and no network.

**Never edit these files by hand.** When the runtime's wire changes, run `pnpm wire` in `shared/tauri-core`
with a memnox-runtime checkout beside this repo, and commit what it changes in the same pull request as the
code that needs it. A chunk's name changes with its bytes, so a refresh may replace a file by another.

A pull request is built from this copy alone. Whether the copy still matches the runtime's `main` is checked
apart from pull requests, by the Runtime copies workflow, and again before a release.
