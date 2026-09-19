# Roadmap — which policies run a script

## What

Show, for each script, the policies that actually run it — and let a search find a script by the
policy that uses it, the way Jamf Pro's own search does.

In the maintainer's words: *"I can't find a policy with tempadmin+ script in it. For instance in Jamf
I search for 'add mdm' and it finds this, but if I search for 'tempadmin+' nothing shows. Can we fix
that in Scripts?"*

## Why

The Scripts module lists scripts and nothing else. It cannot answer the only question anybody asks of
a script they are about to delete: **is anything using this?**

Until this was written the module *appeared* to answer it. Every script carried a green "Scoped"
badge — hardcoded to `.active`, checked against nothing. Scripts have no scope and no enabled state in
Jamf; they are run by whichever policies reference them. That badge has been removed rather than left
saying the same untrue thing about every row, and this entry is what should replace it.

It matters more now that Scripts can delete. Deleting a script a policy still runs breaks that policy
from its next run, silently, and the app currently gives no way to check first.

## What it touches

The data is **already being read**. `scanPolicyEstate` hydrates every policy in full, and
`PolicyDetailXML` decodes a `scripts` array. Nothing new needs fetching from Jamf — the scan simply
discards that part today.

- `PolicyEstateScan` gains `scriptUsage: [String: [String]]` — script id to the names of the policies
  running it, mirroring the existing `packageUsage` exactly.
- The scan's task group reads `detail.scripts` alongside what it already reads. A few lines.
- `ScriptsDashboardView` runs the scan **lazily**, as the Packages module's Deployed tab does — never
  on open, because it reads every policy in the tenant and Scripts currently loads instantly.
- Search then also matches a script by the policies using it.
- The Unused audit could list scripts nothing runs, which it cannot do today.

The service-side change is small. The cost is all in the UX: a module that is instant today gains an
action taking tens of seconds, and that has to be somebody's deliberate choice rather than something
that happens when they open it.

## Known traps

**1. Do not make Scripts slow.** It is one of the few modules that opens immediately. Whatever is
built must keep that true — an explicit "Check usage" action with its own progress, not an automatic
scan on open.

**2. "No policy uses this" is only true if the scan completed.** A scan that failed or was cancelled
must not render as "unused", which is precisely the claim somebody would act on by deleting. The
Packages library already handles this: rows read "Checking…" until the scan answers. Copy that
behaviour rather than inventing another.

**3. A script can be run by a policy the scan skipped.** The scan drops any policy Jamf will not
return after three attempts. That is acceptable for a count; it is not acceptable for "nothing uses
this". If the scan skipped anything, say so.

## Open questions

1. **Automatic or on demand?** See trap 1. On demand is the safe default.
2. **Does the result cache?** Same question as `docs/roadmap/CACHING.md`, and the answer should be the
   same for both.
3. **A usage badge, or a column?** Whatever it is must distinguish "used", "unused" and "not checked"
   — three states, not two.
4. **Should deleting a script that is in use be blocked, or warned?** Blocking is safer; warning
   respects that the maintainer may know something the app does not.
