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
- Upload a custom .pkg or .dmg to Jamf and create its Self Service install policy.
- Browse the packages already in Jamf, and see which of them a policy actually installs.
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
- Packages: read, create, and update if uploading custom packages from **Packages**.
- Scripts: read scripts and script metadata.

Use the least-privileged Jamf API role that supports your workflow.

### Platform API access (Blueprints only)

The **Blueprints** module does not use the Jamf Pro API client above. Blueprints live behind Jamf's
Platform API Gateway, which needs its own integration:

1. Sign in to **Jamf Account** (not Jamf Pro) and choose **Integrations**.
2. **Create integration**, set the scope level to **Platform environment**, and select the
   environment you want to manage.
3. Grant **Blueprints** (Read, Create, Update, Delete, Deploy) and **Device groups → Read**.
4. Click **Create integration** and copy the **client secret immediately** — it is shown once, and
   regenerating it is the only way to replace it. Integrations expire after six months.
5. Open the integration and click the **environment pill** to copy the **environment ID**.

Enter the region, environment ID, client ID and secret under **Settings → Platform API —
Blueprints**, then use **Test Connection**.

Three different UUIDs are involved and they are easy to confuse: the **environment ID** (the
platform environment), the **client ID** (the integration), and the **tenant ID** (the Jamf Pro
instance, offered by a "Copy ID" button in Jamf Account). Blueprints uses the first two; the tenant
ID is not used by this app.

The region must match where your instances are hosted — access tokens are region-locked, and a
token from the wrong region is rejected with a 401.

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

Important: `.jamfconfig` files are Base64 encoded for light obfuscation, not encrypted. Treat exported settings files as secrets and only share them through secure internal channels.

## App Modules

### Dashboard

The dashboard is the starting point after connection. It shows clickable totals for computers, policies, profiles, blueprints, packages, and scripts; each opens its module. A total that could not be read shows — rather than 0. It also includes:

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

### Blueprints

Declarative device management blueprints, listed from the platform environment configured under
**Settings → Platform API — Blueprints**. Until those credentials are set the module says so and
offers a button straight to Settings.

- **List** every blueprint with its name, description, last-updated date and the deployment state
  the server reports (for example `Deployed` or `Not Deployed`).
- **Search** across name and description.
- **Inspect** a blueprint to see its overview beside its complete definition as JSON. The definition
  is shown verbatim rather than parsed into fields, because a component's `configuration` may carry
  any Apple payload key. Copy it with the button in the definition pane.
- **Create** with the **+** button. Type or paste the JSON, or load it from a `.json` file — the
  file's contents appear in the editor where you can adjust them before sending. Server-managed
  fields (`id`, `created`, `updated`, `deploymentState`) are stripped, so a definition copied from
  an existing blueprint can be pasted straight in as a starting point.
- **Scope** the blueprint one of three ways: leave the `scope` in your JSON untouched, pick device
  groups from the environment, or send it unscoped. Note that Jamf documents at least one device
  group as required, so an unscoped blueprint may be refused — whatever the server answers is
  reported in full.
- **Edit** an existing blueprint. Its current definition is loaded into the editor, and only the
  keys you leave in the JSON are changed; anything you remove stays as it is on the server.
- **Deploy / Undeploy / Delete** from the row menu, each behind a confirmation. Deploy and undeploy
  are *started* by the server and finish afterwards, so the result is reported as requested rather
  than completed — the deployment state in the list is what confirms the outcome.

Blueprints are created **undeployed**. Creating one does not apply anything to a device; use
**Deploy** when you are satisfied with it.

- **Wrap DDM output.** Paste the JSON the Jamf DDM app produces and a **DDM Declaration** panel
  appears. Give it a declaration type (for example `com.apple.configuration.extensible-sso`) and a
  channel, press **Wrap as Blueprint**, and the editor rewrites itself as a complete blueprint with
  the declaration inside the right component. It rewrites the editor rather than doing it silently
  at save, so you can read exactly what will be sent and adjust it first. If the JSON is already a
  full declaration it names its own type and the panel fills it in for you.

Blueprints built this way can carry component types that Jamf's own blueprint builder does not list
in its Components library — an Extensible SSO declaration created this way appears in Jamf Pro as a
proper "Extensible Sso / Configuration" component.

There is currently no graphical DDM builder in this app — settings are authored in the Jamf DDM app
or by hand, and brought here as JSON.

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

### Installomator

The Installomator module (folder `Modules/Packages/`) is an Installomator policy manager. It does not manage uploaded Jamf package files directly. Instead, it compares:

- Existing Jamf policies that use an Installomator script and a label in parameter 4.
- Available labels from the upstream Installomator `Labels.txt` file on GitHub.

You can:

- View deployed labels, labels that have gone missing upstream, available labels, or all labels.
- Search by app display name or raw Installomator label.
- Group by alphabet or Jamf category.
- Inspect deployed Installomator policies.
- Select available labels and create Jamf policies for them.
- Edit a deployed policy in place, including the label it installs.
- Select deployed policies and remove them from Jamf.
- Read what a label will actually do, via **Explain This Label** on any card's context menu.

A label is shown as **Deployed** when a policy runs an Installomator script with that label in
parameter 4. The script is matched by name or by ID, so a script that has been renamed is still
recognised once you have deployed with it at least once. A label whose app already appears to be
installed by some other policy is shown as **Possibly Deployed**, naming the policy it matched — it
stays selectable, because the match is a hint rather than a certainty.

A deployed policy whose label is **no longer published** by Installomator is shown as **Missing**, in
amber, with "Not in the Installomator label list" on the row. Labels are withdrawn upstream from time
to time, and the Jamf policy created against one outlives it: the policy still runs, but Installomator
no longer recognises the label, so it fails on every Mac it reaches. The **Missing** view lists exactly
these policies. The label list is re-read from GitHub on every refresh, ignoring any cached copy, so
this reflects what Installomator publishes now rather than what it published when the app last ran.
If GitHub cannot be reached the module says so and marks nothing as missing.

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

#### Editing a deployed policy

Select a single deployed row and use **Edit**, or **Edit Package** on the row's context menu. The sheet
reads the policy from Jamf and prefills from it, so what you see is what Jamf currently holds. You can
change:

- The policy name. Renaming also updates the Self Service display name, matching how the app creates
  these policies. A name already used by another policy is flagged before you save, because Jamf
  requires policy names to be unique.
- Whether the policy is enabled.
- The category. The Jamf category and the Self Service category are written together. A policy can be
  moved between categories but not removed from one.
- Self Service options: feature on main page, display in the category, and the icon. An icon can be
  replaced but not cleared.
- The scope — **opt-in**. The current scope is shown read-only until you turn on **Replace the scope**,
  because replacing it overwrites the computers and groups the policy targets. Exclusions and
  limitations are never written, so anything set up in Jamf beyond targets survives the edit.
- The Installomator label (parameter 4) and its overrides (parameters 7 to 11). Changing the label is
  the repair for a **Missing** row: point the policy at a current label instead of deleting and
  recreating it. A label that is not in the upstream list is flagged, and clearing all overrides hands
  the version choice back to the label.

**Only what you change is written.** Each section of the policy is sent only if you edited it, so an
edit to a category cannot disturb a scope somebody built by hand in Jamf. The sheet lists exactly what
will be written, and the same list appears in the confirmation.

Where several policies share one label — one per pinned version — the sheet offers to apply the
**shared** settings to the others as well: category, Self Service options, icon, scope and enabled
state. The policy name and the label and overrides are never applied to them, because those are what
tell the policies apart. Each policy is reported individually afterwards.

#### Removing deployed policies

Deployed rows are selectable, so a policy can be removed without leaving the module. Select one or
more deployed rows and use **Remove from Jamf**, or use **Remove from Jamf** on a single row's
context menu. The **Missing** view plus **Select All** is the quickest way to clear out policies whose
label no longer exists.

Before anything is deleted you are shown how many policies will go, their names, and which instance
they will be deleted from. Deletion:

- Removes the policy from Jamf and from Self Service.
- **Does not** uninstall the application from any Mac.
- Cannot be undone.

Deletions are paced in small batches like every other bulk operation, so a large clean-up will not trip
Jamf's rate limiting. Each policy is reported individually afterwards — a policy that Jamf refused
(already deleted, or a client without the **Delete Policies** privilege) is listed as a failure with the
reason, never counted as a success, and the list stays selected so it can be retried.

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

### Packages (Jamf package library and custom uploads)

The module has three tabs, laid out like the Installomator manager:

- **New** — the upload flow described below.
- **Uploaded** — every package in this Jamf instance, searchable and grouped A–Z or by category, the
  same way the Installomator list is.
- **Deployed** — only the packages a policy actually installs, with the policy named on the row.

Jamf offers no way to ask "which policies use this package", so the deployed state is worked out by
reading every policy — the same throttled scan the Installomator module performs. It runs once, the
first time you open **Uploaded** or **Deployed**, and never for the New tab alone, so opening the
module to upload something stays instant. While it runs, rows read **Checking…** rather than
pretending a package is unused, and the Deployed count shows an ellipsis until the answer is real.
**Refresh** re-reads both the library and the scan.

Some software has no Installomator label — a label may never have existed, or it may have been
withdrawn upstream, which is what the **Missing** state in the Installomator module reports. **Packages**
covers that case: drop a `.pkg`, `.mpkg`, `.dmg` or `.zip` onto the page (or choose it), fill in the
details, and the app uploads it to Jamf and creates the install policy.

It runs three steps and reports each one separately:

1. Creates the **package record** in Jamf — display name, file name, category, priority, restart
   requirement, and optional info and notes. Everything else is created switched off and can be
   changed on the package in Jamf.
2. **Uploads the file** to that record, with a progress bar and a Cancel button.
3. Creates the **install policy** — name, category, Self Service options, icon and scope, exactly as
   the Installomator flow does, created enabled and offered in Self Service. Turn the policy off if
   you only want the package filed in Jamf.

Before uploading, the display name is checked against the packages already in Jamf: package names must
be unique, and a clash is caught before the file is sent rather than after. The policy name is checked
too, but only warns — a rejected policy still leaves the package safely uploaded.

Practical notes:

- The upload is prepared on disk first, so while it runs the Mac needs roughly as much free space
  again as the package is big.
- Nothing is rolled back behind your back. If the upload fails, the results say the record exists with
  no file attached and give its ID; if the policy fails, they say the package uploaded and only the
  policy needs creating. Cancelling is the one exception — the empty record the app just created is
  removed, and the results say whether that succeeded.
- Your API client needs **Create Packages**, **Read Packages** and **Update Packages** on top of the
  policy privileges.
- The upload uses the Jamf Pro API's package upload endpoint. On a Jamf Pro too old to offer it, the
  app says so plainly instead of failing obscurely.

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

Connection settings are stored locally using SwiftUI `@AppStorage`, which is backed by the app's user defaults. The access token is kept in memory by `JamfAPIService` during the running session.

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

- `.jamfconfig` exports are obfuscated, not encrypted.
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
