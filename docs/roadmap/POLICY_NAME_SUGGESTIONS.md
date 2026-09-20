# Roadmap — choosing a readable policy name

## What

When an Installomator label produces an unreadable policy name, offer the administrator a choice of
better ones rather than only flagging it in amber.

In the maintainer's words: *"it could have selectable options of `Install Autodesk fusion 360 Admin
install` / `Install Autodeskfusion 360` / `Install Autodesk fusion 360` with a selecter option? so
the user can choose easily."*

## Why

A policy name is what every administrator after you reads in Jamf, and it is derived from a label
that was never written to be read — `acroniscyberprotectconnectagent`. The deployment window already
says a name looks wrong. It cannot yet say what would be better, so the only way to fix one is to
rewrite the template, which changes *every* name in the run.

## The amber flag is not measuring what it claims

Worth fixing regardless of whether the rest is ever built, because it is actively misleading:

```swift
static func looksUnsegmented(_ displayName: String) -> Bool {
    !displayName.contains(" ") && displayName.count > 12
}
```

It tests for **a space**, not for readability. So `Abetterfinderattributes 7` passes as green purely
because the trailing `7` in the label gave the heuristic a boundary to split on, while
`Acroniscyberprotectconnect` goes amber. The two are equally unbroken. One of them just happened to
end in a digit.

## What already exists, and is the right shape

`InstallomatorLabelFormatter` (in `Models/PackageModels.swift`) already tries three things in order:
an explicit override, `segmentedName(from:)` against a curated `knownTokens` dictionary (~155 vendor
and product words, longest match first), and a heuristic that splits on letter/digit boundaries.

`segmentedName` is **all-or-nothing on purpose** — every character must be accounted for by at least
two known tokens, or it returns `nil` and the label is left alone. That rule is the reason it is
trustworthy, and it should survive anything built on top.

## A general dictionary is the wrong tool — measured, 20 September 2026

Tested with `NSSpellChecker` (en_GB) as a word oracle, longest-first greedy split:

| label | result | |
| --- | --- | --- |
| `acroniscyberprotectconnectagent` | no split | "acronis" is not a word |
| `abetterfinderattributes` | `abetter · finder · attributes` | wrong |
| `autodeskfusion360admininstall` | `auto · desk · fusion · admin · install` | wrong — "Autodesk" is one word |
| `googlechrome` | `google · chrome` | right |
| `microsoftteams` | **`micros · oft · teams`** | badly wrong |

**A general dictionary produces confident wrong answers**, which is worse than producing none: these
become real policy names on a live tenant. Brand names are not dictionary words, and dictionary words
hide inside brand names. Do not reach for `NSSpellChecker` here.

## What would actually help, cheapest first

1. ~~**Let the name be edited per policy.**~~ **Largely already possible**, as the maintainer
   pointed out (20 September 2026): for a **single-label** run the template field *is* the name, so
   typing `Install Acronis Cyber Protect Connect Agent` into it produces exactly that. What remains
   is the **multi-label** case, where one template has to serve every policy in the run and there is
   no way to correct one of them. That is a narrower job than it first looked.
2. **Fix the amber test** so it means "unreadable", not "no space" — a long unbroken *run* of
   letters, wherever it sits in the name.
3. **More `knownTokens`.** `acronis`, `cyber`, `protect`, `connect`, `agent` would have segmented the
   label that started this. Adding vendor words is boring, safe and immediately effective, and the
   all-or-nothing rule means a wrong guess costs nothing.
4. **Offer the candidates as a picker**, once there is more than one way to split a label. Only worth
   it once (3) produces alternatives worth choosing between.

## Apple Intelligence, some day

The maintainer raised it, and it is a real option rather than a fantasy — but it is not the answer to
*this* problem, which is a vocabulary problem rather than a language one.

- **The cheap version:** the system writing tools —
  <https://developer.apple.com/documentation/technologyoverviews/apple-intelligence>. Rewriting and
  proofreading, offered inside a text field. It would help somebody *editing* a name; it will not
  know that "Autodesk" is one word.
- **The expensive version:** on-device models via Core AI —
  <https://developer.apple.com/documentation/coreai> and
  <https://developer.apple.com/documentation/coreai/integrating-on-device-ai-models-in-your-app-with-core-ai>.

**Traps before anyone starts.** Core AI is macOS 27+, and this app targets macOS 26 — adopting it
means either raising the floor or carrying two paths. Apple Intelligence is not available on every
Mac or in every region, so anything built on it needs the non-AI path anyway, which is items 1–3
above. And a model that *invents* a plausible name is the same failure as `micros · oft · teams`,
just harder to predict: whatever suggests a name, the administrator must still choose it, and the
app must still be usable by somebody who declines every suggestion.

## Done already, 20 September 2026

**The token list was expanded** from ~155 to ~400, which is item 3 and the cheapest of them. It now
covers `acronis`, `cyber`, `protect`, `connect` and `agent` — the label that started this — along
with the common Mac-admin vendors (Kandji, Munki, Installomator, AutoPkg, the security and VPN
vendors), the JetBrains and Adobe families, the browsers, and a much larger set of product nouns.

The all-or-nothing rule is what makes that safe to do in bulk: a token that never matches costs
nothing, and a label only segments when every character is accounted for by at least two tokens.

## Open questions

1. **Does an edited name survive changing the template?** A per-policy edit and a run-wide template
   are two ways of deciding the same string, and they will disagree.
2. **Does it apply to one policy or to the label everywhere?** `InstallomatorOverrides` already
   stores per-label overrides — an edited name might belong there rather than in the window.
