## What this changes

<!-- One or two sentences. Link the issue it closes, if there is one: Closes #123 -->

## Why

<!-- The problem it solves for the person using the app. -->

## How I checked it

- [ ] `swift test` passes
- [ ] I ran the app (`./scripts/bundle.sh`, then `open build/Memnox.app`) and tried the change
- [ ] For a change on screen: I looked at it with `open -n build/Memnox.app --args --island-preview` and added a screenshot or a short recording below

## Before review

- [ ] It sits in the right layer ([docs/ARCHITECTURE.md](../blob/main/docs/ARCHITECTURE.md)), and a new rule has a test at the mirrored path
- [ ] No magic numbers or identifier strings; design values use the `Memnox` tokens
- [ ] A `switch` over the app's own enums lists every case, with no `default`
- [ ] No `Any`, `as!`, `try!` or `print`
- [ ] Comments say why, and no dash stands in any copy or comment
- [ ] If the daemon protocol changed, `memnox-runtime`'s `protocol.ts` changes with it (link the pull request)
- [ ] Commits are one line each, in the `feat:` / `fix:` / `refactor:` / `docs:` / `chore:` form

## Screenshots or recording

<!-- Optional, and very welcome for anything you can see or hear. -->
