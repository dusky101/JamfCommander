# The `docs/` folder

Four kinds of document, kept apart because they have different lifespans. Mixing them is what makes
project documentation untrustworthy: a reader cannot tell which parts have rotted.

| Folder | What it holds | Lifespan |
| --- | --- | --- |
| `docs/` (root) | Reference for how the app works now — architecture, the Jamf API surface | Living. Updated whenever the thing it describes changes. |
| `docs/roadmap/` | **Intent.** One file per idea: what the maintainer wants, and why | Durable. Describes a goal rather than code, so it does not rot. |
| `docs/handovers/` | **State.** Where a piece of work actually stands, what is proven and what is not | Perishable. Wrong the moment somebody commits. |
| `docs/prompts/` | **Instructions.** What to hand a fresh session to start work | Written with its handover, discarded with it. |

## The lifecycle

An idea starts as a **roadmap** entry, written when the maintainer thinks of it — possibly long
before anyone builds it. It says what he wants and why, not how.

When that work is about to start, its roadmap entry is read and a **handover** plus a **prompt** are
written *at that moment*, against the code as it stands that day. They are current because they were
written the day work began, not months earlier.

When the work lands, the handover is updated to say what was proven and what was not, and the prompt
is deleted. The roadmap entry goes too, or is trimmed to whatever remains undone.

**Do not write a handover for work that is not about to start.** That is the failure this structure
exists to prevent: a handover written in advance describes a codebase that will have moved by the time
anyone reads it, and the reader has no way of telling which parts are stale.

## Writing a roadmap entry

One file per idea, named for the idea (`CACHING.md`, `MOBILE_DEVICES.md`). It should answer:

- **What** the maintainer wants, in his words where possible.
- **Why** — the problem it solves. This is the part that survives; approaches change, problems do not.
- **What it touches**, roughly, so somebody can judge the size without reading the code.
- **Known traps** — anything already discovered that would bite an implementer.
- **Open questions** the maintainer has not answered yet.

Do not put an implementation plan in a roadmap entry. By the time it is built the plan will be wrong,
and its presence makes the entry look current when it is not.

## Writing a handover

Follow `docs/handovers/BLUEPRINTS_HANDOVER.md`, which sets the pattern:

- Dated, with the app version, and explicit about what is committed.
- **A table of what is proven against the live tenant versus what has never run.** This app talks to a
  production Jamf instance; "it compiles" is not "it works", and a handover that blurs the two is
  worse than none at all.
- The constraints an implementer will trip over, with file and symbol names.
- Open questions in the order they block work.

## For somebody picking this project up

Read in this order:

1. `CLAUDE.md` at the repo root — the safety invariants. They are not negotiable, and they exist
   because this app makes destructive changes to a live enterprise Jamf instance.
2. `JamfCommander/README.md` — what the app does, from a user's point of view.
3. `docs/PROJECT_OVERVIEW.md` — the architecture in narrative form.
4. `docs/JAMF_API_REFERENCE.md` — the exact endpoints, throttling and XML shapes. Never invent an
   endpoint: if it is not here or already proven in the code, confirm it against Jamf's documentation
   before writing it.
5. `docs/roadmap/` — where the maintainer wants this to go next.
