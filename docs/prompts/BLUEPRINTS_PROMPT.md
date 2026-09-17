# Implementation Prompt — Blueprints, continued

> Hand this to Claude Code in the JamfCommander repo.

## Read these first, in this order

1. **`docs/prompts/BLUEPRINTS_HANDOVER.md`** — the state of play: what is built, what is *proven
   against the live tenant*, what has never run, and the facts that are not in any documentation.
   Do not start without it.
2. Root **`CLAUDE.md`** — the non-negotiable safety invariants.
3. **`.claude/rules/`** — `architecture.md` always; then `services-and-networking.md`,
   `models-and-decoding.md`, `swiftui-views.md`, `design-system.md`, `auth-and-credentials.md` as
   they match the files you open.
4. **`docs/JAMF_API_REFERENCE.md`** — endpoints, auth, and the traps (merge-patch content type,
   403 meanings, the `com.jamf.ddm-strict` declaration shape).
5. **`docs/cleanup.md`** — only if the task is the UI audit.
6. **`JamfCommander/README.md`** — how the module reads to a user; keep it consistent if behaviour
   changes.

## The task

Pick up the numbered list under "Outstanding work" in the handover. The maintainer will say which
item; if they have not, ask before starting rather than guessing.

## Guardrails — follow, do not restate

The repo's own instructions are authoritative. The ones that bite this area hardest:

- **Every write hits a live production Jamf tenant and real Macs.** Gate each one behind
  `CommanderConfirmation`, report the real per-item outcome via `OperationResultView`, and never
  display a success the API did not confirm. A **Sandbox (EU)** environment exists — suggest it for
  anything untested; only the Environment ID in Settings needs changing.
- **Never invent endpoints or payload shapes.** The handover records what is proven and what is
  merely documented. If something is needed that neither covers, find it — the component catalogue
  endpoints, or a real object read back from the tenant — rather than inferring it.
- **Deploy and undeploy return 202.** The server finishes afterwards. Never report them as complete.
- **Respect rate limits** — sequential paging with a delay, as the existing code does.
- **Credentials are secrets.** Never log, print or display the client ID, secret, environment ID or
  token. Note that `.jamfconfig` now carries two secrets and is base64, which is obfuscation, not
  encryption — do not describe it as secure.
- **British English** in all user-facing copy; calm, professional, enterprise tone.
- **Reuse `SharedUI`** and the Liquid Glass helpers rather than new visual treatments.
- **Do not commit or push.** Leave the working tree for the maintainer.

## How to work

- **Work in phases.** Each phase coherent, reviewable, and leaving the app building.
- End every phase with the PHASE COMPLETE summary the root `CLAUDE.md` specifies, then ask the
  Commit Ceremony question and wait.
- **Build with** `xcodebuild -scheme JamfCommander -destination "platform=macOS" build`.
  There is **no test target** — never claim tests ran.
- **A clean build does not mean it looks right.** Two layout defects shipped in the last session
  because compiling was treated as verification. If a change affects layout, either verify it
  visually or state plainly in the summary that you have not.
- Keep `docs/JAMF_API_REFERENCE.md` accurate about what is verified live versus documented only,
  and update `JamfCommander/README.md` if user-facing behaviour changes.
