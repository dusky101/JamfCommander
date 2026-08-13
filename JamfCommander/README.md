# Jamf Commander

Jamf Commander is a macOS SwiftUI app for Jamf Pro administrators who need a faster way to inspect, organise, clone, export, and deploy common Jamf objects. It connects to a Jamf Pro tenant with OAuth client credentials and provides focused modules for computers, configuration profiles, policies, scripts, categories, exports, and Installomator-based package deployment.

The app uses both the Jamf Pro API and the Jamf Classic API because Jamf exposes different object details and mutation endpoints through each API family.

## What You Can Do

- View fleet totals for computers, policies, configuration profiles, and scripts.
- Manage Jamf categories from the dashboard.
- Browse computers, filter by managed status, inspect hardware, OS, security, user, profile, script, and policy information.
- Browse configuration profiles by category, inspect scope and raw source, move profiles between categories, update profile scope, clone profiles, delete profiles, and export profile data.
- Browse policies by category, inspect scope and raw source, move policies between categories, clone policies, delete policies, and export policy data.
- Browse scripts by category, inspect script metadata, parameters, and script source, and export script data.
- Compare deployed Installomator policies against the upstream Installomator label list.
- Create Jamf Self Service policies for selected Installomator labels.
- Export computers, policies, profiles, scripts, or all supported data to CSV/ZIP files.
- Import and export Jamf Commander connection settings with `.jamfconfig` files.

## Requirements

- macOS
- Xcode
- A Jamf Pro instance with API access enabled
- A Jamf Pro API client using the `client_credentials` OAuth grant
- Network access to your Jamf Pro tenant
- Network access to GitHub when using the Installomator Manager, because it downloads labels from the Installomator repository

## Jamf API Access

Jamf Commander authenticates against:

```text
POST /api/v1/oauth/token
```

After authentication, the app stores the bearer token in memory for the current session and uses it for subsequent API calls.

The app reads and writes data through endpoints including:

```text
/api/v1/computers-inventory
/api/v1/scripts
/JSSResource/categories
/JSSResource/computergroups
/JSSResource/osxconfigurationprofiles
/JSSResource/policies
```

Your Jamf API role must include the privileges needed for the actions you plan to use. Read-only browsing and CSV exports require read privileges for the relevant object types. Moving, cloning, scope changes, category management, policy creation, and deletion require write/create/delete privileges for those Jamf objects.

Recommended privilege areas:

- Computers: read inventory data.
- Computer Groups: read groups for deployment targeting.
- Categories: read, create, update, and delete if using category management.
- macOS Configuration Profiles: read, update, create, and delete if using profile actions.
- Policies: read, update, create, and delete if using policy actions or Installomator deployment.
- Scripts: read scripts and script metadata.

Use the least-privileged Jamf API role that supports your workflow.

## Configuration

Open the app and choose **Settings**. Enter:

- Jamf Instance URL, for example `https://yourcompany.jamfcloud.com`
- Client ID
- Client Secret

Then select **Initialise Connection**.

If the app has saved credentials from a previous run, it attempts to auto-connect on launch.

### Settings Files

The settings screen can export and import `.jamfconfig` files. These files contain:

- Jamf instance URL
- Client ID
- Client Secret
- Export date
- App version
- Jamf Commander file signature

Exported files are encrypted. You choose a passphrase when exporting (minimum 8 characters, entered twice), and whoever imports the file is asked for it. The file is sealed with AES-GCM under a key derived from that passphrase using PBKDF2-HMAC-SHA256.

Important: send the passphrase to your colleagues by a different route from the file itself, and choose a passphrase you would be comfortable protecting an API secret with. The file's protection is only as good as the passphrase. If the passphrase is lost the file cannot be recovered — export a new one.

Configuration files produced by earlier versions were Base64 encoded rather than encrypted. Those files still import, but treat any copy of one as a plaintext secret and replace it with a fresh export.

## App Modules

### Dashboard

The dashboard is the starting point after connection. It shows clickable totals for computers, policies, profiles, and scripts. It also includes:

- Category manager for creating, renaming, and deleting categories.
- Device status summary based on recent computer inventory records.
- Export All action that writes a ZIP archive containing CSV files for computers, policies, profiles, and scripts.

### Computers

The Computers module uses Jamf Pro computer inventory records. You can:

- Search devices by name or serial number.
- Filter to all devices or managed devices only.
- Export the visible computer data to CSV.
- Inspect a computer record.
- Copy a device serial number from the context menu.

The computer inspector includes tabs for:

- Hardware, OS, FileVault, IP address, last contact, and remote management status.
- Installed configuration profiles.
- Available Jamf scripts.
- Policies.
- User and location data.

### Profiles

The Profiles module works with macOS configuration profiles from the Classic API. It hydrates each profile with category and scope details so profiles can be grouped and labelled as scoped or unscoped.

You can:

- Search by profile name or ID.
- Filter by category.
- Expand and collapse category groups.
- Select one or more profiles.
- Use Shift-click range selection.
- Inspect profile scope and raw source.
- Move profiles to a different category.
- Set selected profiles to **All Computers**.
- Remove all scope from selected profiles.
- Clone profiles into a selected category.
- Delete profiles.
- Export detailed profile data to CSV.

Profile clones are named `Copy of [Original Name]`. Clone options include stripping scope so the cloned profile is not deployed immediately.

### Policies

The Policies module works with Jamf policies from the Classic API. It fetches the policy list, hydrates policy details in batches, and groups policies by category.

You can:

- Search by policy name or ID.
- Filter by category.
- Expand and collapse category groups.
- Select one or more policies.
- Use Shift-click range selection.
- Inspect policy scope and raw source.
- Move policies to a different category.
- Clone policies into a selected category.
- Delete policies.
- Export detailed policy data to CSV.

Policy clones are named `Copy of [Original Name]` and are disabled by default for safety. Clone options include:

- Remove scope.
- Remove triggers.
- Set frequency to `Once per computer`.
- Disable Self Service.

### Scripts

The Scripts module uses the Jamf Pro scripts API. You can:

- Search scripts by name.
- Browse scripts grouped by category.
- Inspect script metadata.
- View script parameters.
- View script source.
- Export scripts to CSV.

### Packages / Installomator Manager

The Packages module is an Installomator policy manager. It does not manage uploaded Jamf package files directly. Instead, it compares:

- Existing Jamf policies that use an Installomator script and a label in parameter 4.
- Available labels from the upstream Installomator `Labels.txt` file on GitHub.

You can:

- View deployed labels, available labels, or all labels.
- Search by app display name or raw Installomator label.
- Group by alphabet or Jamf category.
- Inspect deployed Installomator policies.
- Select available labels and create Jamf policies for them.
- Read what a label will actually do, via **Explain This Label** on any card's context menu.

A label is shown as **Deployed** when a policy runs an Installomator script with that label in
parameter 4. The script is matched by name or by ID, so a script that has been renamed is still
recognised once you have deployed with it at least once. A label whose app already appears to be
installed by some other policy is shown as **Possibly Deployed**, naming the policy it matched — it
stays selectable, because the match is a hint rather than a certainty.

When adding selected labels to Jamf, the deployment sheet lets you choose:

- Target category, including creating a new one.
- Installomator script.
- Policy name template, such as `Install {appName}`, with `{version}` available when pinning versions.
- Self Service options, including a **Self Service icon** — none, an uploaded image, or an existing
  Jamf icon reused by ID. The image is uploaded to Jamf's icon library once per run and the same icon
  is attached to every policy the run creates.
- Scope: all computers, specific computers, or computer groups. The computer list shows each Mac's
  assigned user and can be searched by name, serial, user or email.
- Version pinning (advanced, single-label runs only) — see below.

Before anything is written, the sheet:

- Checks the resolved policy names against the names already in Jamf and warns about any that would be
  rejected as duplicates, so you can change the template rather than collect failures.
- Lists every policy name the run will create under **Review policy names**, marking names the app
  could not tidy from the raw label.
- Asks you to confirm, stating how many policies will be created, in which category, and at what scope.

Created policies use the selected Installomator script and pass the label in script parameter 4, with
`DEBUG=0` in parameter 5 and `NOTIFY=silent` in parameter 6.

#### Version pinning

Installomator re-reads its `key=value` arguments after a label has run, so a value passed as a script
parameter overrides whatever the label worked out. Parameters 7 to 11 are free, giving five overrides
per policy.

For a run containing a single label you can list several versions and give one override pattern
containing `{version}`. The sheet creates **one policy per version**, all sharing the category, script,
icon and scope. For example, three versions of Python with:

```
appNewVersion  {version}
downloadURL    https://www.python.org/ftp/python/{version}/python-{version}-macos11.pkg
archiveName    python-{version}-macos11.pkg
```

produces `Install Python 3.11.9`, `Install Python 3.12.7` and `Install Python 3.13.1`, each carrying its
own resolved parameters. The exact strings are previewed before you deploy.

Important limits, by design:

- **The app cannot list the versions that are available.** Labels discover those by reading the vendor's
  own site on the Mac at install time, so the versions and the URL pattern are yours to supply. The app
  validates, expands and previews what you give it; it never invents a download URL.
- Overrides are offered only for a single-label run, because a pinned download URL describes one
  application.
- A pinned download URL **stops working when the vendor moves or removes the file**, and the policy will
  then fail on every Mac. Pinning an architecture-specific URL installs the wrong binary on the other
  architecture — for a genuine architecture split, create one policy per architecture and scope each to
  an architecture-based smart group.
- Values are validated before deploying: the variable must be one the app supports, a `downloadURL`
  must be `https://`, values may not contain spaces, and a run pinning more than one version must have
  `{version}` in the name template.

Version pinning is entirely optional. Leaving it on "Let Installomator decide" produces exactly the
policies the app has always created.

## Exporting Data

Jamf Commander can export:

- Computers CSV
- Policies CSV
- Detailed policies CSV
- Profiles CSV
- Detailed profiles CSV
- Scripts CSV
- All supported data as a ZIP archive

Exports use macOS save panels, so you choose the destination at export time.

Detailed policy and profile exports fetch extra object data in batches and include richer information such as scope, triggers, frequency, packages, scripts, exclusions, and deployment metadata where available.

## Safety Notes

Jamf Commander can make destructive changes to your Jamf tenant. Review selections before confirming actions.

Actions that modify Jamf include:

- Creating, renaming, and deleting categories.
- Moving policies and profiles between categories.
- Updating profile scope.
- Cloning policies and profiles.
- Creating Installomator deployment policies.
- Deleting policies and profiles.

Deletion is permanent from the app's perspective. Make sure you have backups or a recovery process before using bulk delete actions.

For safer cloning, cloned policies are disabled by default and can have scope, triggers, frequency, and Self Service stripped before creation.

## Data Storage

The Client ID and Client Secret are stored in your login Keychain, available only while your Mac is unlocked and never synchronised to iCloud. The Jamf instance URL is stored in the app's user defaults, as it is an address rather than a secret. The access token is kept in memory by `JamfAPIService` during the running session and is never written to disk.

If you used an earlier version, your existing credentials move to the Keychain automatically the first time you launch this one. Nothing is removed from the old location until the Keychain copy has been written and read back successfully.

The app does not include its own database.

## Project Structure

```text
JamfCommander/
  Auth/
    ConfigurationView.swift
    LoginView.swift
  Core/
    SidebarView.swift
  Models/
    ComputerModels.swift
    InspectorSelection.swift
    JamfModels.swift
    PackageModels.swift
    PolicyModels.swift
    ScriptModels.swift
  Modules/
    Cloning/
    Computers/
    Dashboard/
    Export/
    Packages/
    Policies/
    Profiles/
    Scripts/
  Services/
    Exports/
    ExportService.swift
    JamfAPIService.swift
    JamfAPIService+Cloning.swift
    JamfAPIService+Dashboard.swift
    JamfAPIService+Packages.swift
    SettingsService.swift
  Shared/
  SharedUI/
  Views/
  JamfCommanderApp.swift
```

## Architecture Overview

- `JamfCommanderApp` launches `ContentView`.
- `ContentView` owns the shared `JamfAPIService`, connection state, and main module navigation.
- `SidebarView` defines the app modules.
- `JamfAPIService` handles authentication, generic requests, and core Jamf API calls.
- `JamfAPIService+Dashboard`, `JamfAPIService+Packages`, and `JamfAPIService+Cloning` add focused API workflows.
- `Models` define Codable records for Jamf API responses and UI grouping.
- `Modules` contain feature-specific dashboards, inspectors, cards, and sheets.
- `ExportService` coordinates CSV and ZIP export flows and delegates CSV generation to specialised export services.
- `SettingsService` imports and exports `.jamfconfig` settings files.

The UI is built with SwiftUI and uses async/await for network operations.

## Building From Source

1. Clone the repository.
2. Open the project in Xcode.
3. Select the `JamfCommander` scheme.
4. Build and run the app.
5. Configure your Jamf instance URL and OAuth client credentials from Settings.

## Typical Workflow

1. Launch Jamf Commander.
2. Open Settings and enter your Jamf Pro URL, Client ID, and Client Secret.
3. Initialise the connection.
4. Use Dashboard to confirm object counts and manage categories.
5. Use Computers, Profiles, Policies, Scripts, or Packages depending on your task.
6. Inspect objects before making changes.
7. Export data before bulk operations when you need an audit trail.
8. Confirm destructive or tenant-changing actions only after validating your selections.

## Installomator Workflow

1. Confirm an Installomator script exists in Jamf.
2. Open the Packages module.
3. Let the app load deployed Installomator policies and available upstream labels.
4. Select available labels.
5. Choose **Add to Jamf**.
6. Select the target category and Installomator script.
7. Choose Self Service options, including an optional Self Service icon.
8. Choose the scope.
9. Optionally pin versions (single-label runs only) and check the previewed parameters.
10. Review the policy names, resolve any duplicate-name warnings, and confirm deployment.

The app creates Jamf policies that call the selected script and use the selected Installomator label as parameter 4. Results are reported per policy, including a policy that was created but whose icon could not be attached.

## Known Limitations

- `.jamfconfig` exports are encrypted, but only as strongly as the passphrase chosen and the channel the passphrase travels by. A forgotten passphrase cannot be recovered.
- The app assumes the Jamf API client has the required privileges for the selected action.
- Some inspectors expose raw source views, but not every visible editor control currently writes changes back to Jamf.
- Installomator label discovery depends on GitHub availability. **Explain This Label** also reads from
  GitHub; if it is unreachable the panel says so and deployment is unaffected.
- The app cannot list which versions of an application are available — that information only exists on
  the vendor's site, which the label reads on the Mac at install time. Pinned versions and download
  URLs are supplied by you, and a pinned URL will stop working if the vendor moves the file.
- Policy names are derived from the Installomator label. Well-known labels are recognised and split into
  proper names, but a label the app cannot split is flagged in the deployment sheet rather than
  corrected, and individual names cannot yet be edited — only the name template.
- Large Jamf tenants may take time to hydrate policy and profile details because detailed exports and dashboards fetch additional data in batches.

## Contributing

When contributing, keep changes scoped to the relevant module or service. Prefer SwiftUI patterns, async/await, and strongly typed models for Jamf responses. Avoid storing secrets in source control, sample files, or screenshots.

## Disclaimer

Jamf Commander is an administrative tool that can modify production Jamf Pro data. Test against a non-production Jamf tenant before using bulk actions in production.
