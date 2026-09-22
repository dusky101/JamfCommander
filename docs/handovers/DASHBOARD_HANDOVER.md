# Handover — the Dashboard's Device Status

**State at handover:** 22 September 2026, app version 9.0. **Built and confirmed on screen by the
maintainer.** There is no roadmap entry; this was a defect found by looking at the app.

---

## What was wrong, because it is the point of the whole change

The section was headed **"Recent Check-ins"** and drew a green **Active** badge on every row. It had
no check-in data of any kind:

- `BasicComputerRecord` carried five fields — id, name, username, realname, email. **No date.**
- The request had no `sort=`, so the order was whatever Jamf returned.
- The view took `computers.prefix(20)` off that unsorted list.
- The badge was a literal: `Circle().fill(Color.green)` and `Text("Active")`, with no condition
  anywhere in the file.

So a Mac last seen on 15 June 2026 appeared in a list headed "Recent Check-ins", marked Active. The
maintainer found it by recognising the machine.

**The lesson worth keeping:** `CLAUDE.md`'s rule about never reporting a success the API did not
confirm is usually read as being about writes. It applies to *state* as well. A fleet dashboard
asserting that 153 Macs are all Active is a false report, and a more dangerous one than a failed
delete, because nothing about it looks like an error.

## Proven — and what is NOT

| Established | Not established |
| --- | --- |
| The states are correct. 19 checks against a fixed "now": the 2-hour boundary either side, 14 and 16 days (the holiday case), 18 days, the real 15 June 2026 machine, never-contacted, empty string, fractional seconds, and a Mac whose clock runs an hour fast | How it looks on a **narrow window**. The controls are a 320pt segmented picker, a checkbox and a count picker on one row — the arithmetic `START_HERE.md` warns about with Installomator's header. Nobody has measured it |
| The section reads real data, confirmed on screen: the machine that started this shows *Not seen* with its real date | Whether 17 days is the right number **in practice**. It is reasoned, not observed. If the *Not seen* list is dominated by machines that turn out to be fine, it is too short; if known-dead machines hide in *Recent*, too long |
| `Recent` admits `Live`, and a live machine keeps its green badge while listed under Recent | Behaviour on a large estate. 200 rows is the cap; nobody has drawn it on a fleet where *Not seen* runs to thousands |
| No extra request. `lastContactTime` arrives in the `GENERAL` section `fetchDashboardComputers` already asks for | Whether Jamf ever returns a timestamp shape neither formatter parses. One that fails to parse reads as *never seen*, which promotes a healthy Mac into the problem list rather than hiding a broken one — the safe direction, but still wrong |
| The session cache is memory-only, so no cached record decodes without the new field | |

## The two thresholds

Both are in `Models/DeviceContact.swift`, with the reasoning beside them.

- **Live — 2 hours.** Jamf's default check-in is every 15 minutes, so this is several missed
  check-ins: long enough not to flicker, short enough to mean "on and talking".
- **Not seen — 17 days.** Deliberately not 14 and not 30. **Two weeks is a normal holiday**, and a
  list that puts everybody returning from leave at the top of a problem queue teaches its reader to
  ignore the queue. Seventeen covers the fortnight plus the weekend either side.

`Recent` is everything from 0 to 17 days **including Live**. The three tile the whole range, so no
machine falls through a gap, and a machine that never contacted Jamf is `notSeen` rather than a
fourth case.

## What it is made of

| File | What it holds |
| --- | --- |
| `Models/DeviceContact.swift` | `DeviceContactState` (the thresholds, the state machine, how each presents), `DeviceContactClock` (parsing Jamf's timestamp, ages, wording), `DeviceListLimit` |
| `Modules/Dashboard/DeviceStatusSection.swift` | The section, its four controls, the domain grouping and the row |
| `Services/JamfAPIService+Dashboard.swift` | `BasicComputerRecord.lastContactTime`, plus `contactAge` and `contactState` |

Four controls, each remembered between launches in `@AppStorage`: the state chooser
(`deviceStatusSelection`, defaults to *Not seen*), the domain grouping (`deviceStatusGroupByDomain`,
off), and the row count (`deviceStatusLimit`, 50).

**Sorting happens before capping.** That is the real difference from `prefix(20)`: a limit on an
unsorted list hides an arbitrary set of machines, a limit on a sorted one hides the least
interesting. The footnote says "Showing 50 of 118", so a capped list never passes for the whole set.

## Loose ends, in the order worth doing them

1. **Two copies of the same ISO-8601 parser.** `ComputersDashboardView.formattedLastContact` has a
   private one that predates `DeviceContactClock` and does the same job. Collapse it.
2. **`ComputerInspectorView` prints `lastContactTime` raw** — `2026-06-15T08:12:00Z` where a reader
   wants a date, and "Never" where the field is missing rather than the current "Never" fallback on
   an empty optional. One line through `DeviceContactClock.absoluteDescription(since:)`.
3. **`ComputerExportService` writes the raw string to CSV.** Defensible — a machine-readable export
   arguably wants ISO 8601 — but it should be a decision rather than an accident, and the column is
   headed for humans.
4. **Nothing else surfaces contact state.** The Computers module has a sortable "Last Contact"
   column but no notion of stale; the Unused audit finds objects nothing uses but not *machines*
   nothing has heard from. A Mac silent for six months is at least as interesting as an unscoped
   profile.

## If somebody asks for richer saved views

Named views, or an editor sheet, would be a new idea and belong in `docs/roadmap/` first. What exists
already covers the request that prompted this: the four controls are remembered, so the view somebody
sets up is the view they get back.
