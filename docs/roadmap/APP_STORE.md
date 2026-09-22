# Roadmap — releasing on the Mac App Store

## What

Distribute the app through the Mac App Store, alongside or instead of the current direct
distribution (Developer ID, notarised).

## Why

Discovery, and the trust a store listing carries with an administrator who has not heard of the
author. Today somebody has to be sent a build and choose to run it.

**Not obviously the right channel**, and that judgement should be made before any of the work below.
The audience is Mac admins, who are entirely comfortable with a notarised download; against that, the
store costs a review cycle on every update, locks the sandbox in permanently, and takes 15–30% if the
app is ever paid for. Recorded here because the question was asked, not because the answer is yes.

## Where it already stands — better than expected

Checked 22 September 2026 against the built app, not assumed:

- **App Sandbox is on**, and Hardened Runtime with it.
- The entitlements the built app actually carries are the minimal set a store submission wants, with
  no temporary exceptions and no disabled library validation:
  `com.apple.security.app-sandbox`, `com.apple.security.network.client`,
  `com.apple.security.files.user-selected.read-write`.
  (`get-task-allow` is also present, which is Debug-only and absent from a Release build.)
- No private API. It is SwiftUI, AppKit and URLSession throughout.
- `DEVELOPMENT_TEAM` is set with automatic signing, so the distribution side is largely a different
  destination in the Organizer.

The usual reason a Mac app cannot go to the store — it is not sandboxed and its architecture assumes
it never will be — does not apply here.

## Three things in the code

1. **`ExportService.createZipArchive` spawns `/usr/bin/zip`** through `Process`. A sandboxed child
   inherits the sandbox so it may well work, but shelling out to a system binary invites review
   attention and is fragile regardless of channel. `NSFileCoordinator` coordinating a read with
   `.forUploading` produces a zip of a directory in-process; the change is contained to that one
   function.
2. **Notifications are posted without ever requesting authorisation.**
   `ExportService.showNotification` calls `UNUserNotificationCenter.current().add(_:)` and nothing in
   the app calls `requestAuthorization`, so export-complete notifications silently do nothing today.
   Not a store rule, but a reviewer meeting a feature that does not fire is a rejection risk, and it
   is a real bug either way.
3. **Credentials live in `UserDefaults`** — `@AppStorage("clientId")` and `@AppStorage("clientSecret")`
   in `LoginView`, `ConfigurationView` and `SettingsTransferSection`, which means plaintext in a plist
   in the container. Not a formal blocker. It should be the Keychain before *any* public release, and
   `auth-and-credentials.md` already calls it a known weak point rather than a pattern to extend.

## The trap — the reviewer has no Jamf tenant

This is the part that costs time, and it is not a code change.

App Review launches the app and sees a login screen for a Jamf Pro instance they do not have. Nothing
beyond that screen can be evaluated. Guideline 2.1 requires a working demo account for an app that
needs one, so a submission needs either:

- a test tenant whose credentials go in the App Store Connect review notes — which means a live Jamf
  instance reachable by a stranger, with whatever that implies; or
- a demo mode that populates the modules from fabricated data with no tenant at all.

The second is more work and more useful: it is also what would let somebody evaluate the app before
committing credentials, and what would make screenshots possible without exposing a real estate.

## The paperwork

- **The name.** "Jamf" in an App Store title is a trademark problem (5.2.5), not a courtesy. The app
  was renamed to **Commander** on 22 September 2026 partly for this. The description and screenshots
  must not imply affiliation either; the guide's "not affiliated with Jamf" line should appear in the
  listing as well.
- **App Privacy questionnaire** — almost certainly "Data Not Collected". Nothing leaves the Mac except
  requests to the administrator's own Jamf instance and the Installomator label list on GitHub. There
  is no backend of the author's and no analytics.
- **Export compliance** — HTTPS only, so the standard exemption applies:
  `ITSAppUsesNonExemptEncryption = false` in the Info.plist avoids the annual declaration.
- Screenshots, description, keywords, support URL, privacy policy URL, age rating, and the
  distribution certificate.

## Traps spotted while looking

- **Screenshots of a real tenant leak an estate.** Every screenshot to date shows real machine names
  and real staff email addresses. A demo mode solves the review problem and this one together.
- **The store version is sandboxed for ever.** Anything later that wants a privileged operation — a
  helper tool, writing outside a user-selected location — would be available to the direct build and
  not to the store build, and the two would quietly diverge.

## Open questions

- Is the store worth it at all, given the audience? (See **Why**.)
- Free or paid? That decides which agreements are needed and whether the 15–30% matters.
- If both channels ship, which is the canonical one, and how does a user move between them? The two
  builds cannot share a container.
