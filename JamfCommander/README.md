# Jamf Commander

Jamf Commander is a macOS SwiftUI app for Jamf Pro administrators who need a faster way to inspect, organise, clone, export, and deploy common Jamf objects. It connects to a Jamf Pro tenant with OAuth client credentials and provides focused modules for computers, configuration profiles, policies, scripts, categories, exports, and Installomator-based package deployment.

The app uses both the Jamf Pro API and the Jamf Classic API because Jamf exposes different object details and mutation endpoints through each API family.

## What You Can Do

- View fleet totals for computers, policies, configuration profiles, and scripts.
- Manage Jamf categories from the dashboard.
- Browse computers, filter by managed status, inspect hardware, OS, security, user, profile, script, and policy information.
- Connect Apple Business Manager to add purchase date, warranty end and a calculated lifecycle date to every Mac, filter to devices out of warranty, and see which Macs Apple has assigned to Jamf that Jamf has never enrolled.
- Browse configuration profiles by category, inspect scope and raw source, move profiles between categories, update profile scope, clone profiles, delete profiles, and export profile data.
- Browse policies by category, inspect scope and raw source, move policies between categories, clone policies, delete policies, and export policy data.
- Browse scripts by category, inspect script metadata, parameters, and script source, and export script data.
- Compare deployed Installomator policies against the upstream Installomator label list.
- Create Jamf Self Service policies for selected Installomator labels.
- Export computers, policies, profiles, scripts, deployed Installomator apps, or all supported data to CSV/ZIP files.
- See the number of Installomator apps deployed alongside the other fleet totals on the dashboard.
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

### Apple Business Manager

Optional. Connecting Apple Business Manager adds purchase date, warranty and lifecycle information to the Computers module, none of which Jamf Pro holds without a GSX connection.

Create an API account in Apple Business Manager under Preferences → API. It gives you a Client ID, a Key ID, and a one-time private key download. Enter these on the **Apple Business Manager** tab of the settings screen and import the key file — the app accepts the key exactly as Apple issues it, with no conversion needed.

**Test Connection** proves the whole chain and lists the MDM servers in your organisation with their identifiers. Copy the identifier of the server Jamf Pro uses into the **MDM Server ID** field. Only devices assigned to that server are fetched, so iPhones and iPads in your organisation are never downloaded.

**Lifecycle** is not a value Apple Business Manager holds. It is calculated as the purchase date plus the number of years set here, defaulting to four.

**Refresh Apple Business Manager Data** fetches the fleet and caches it for seven days. Apple has no bulk warranty endpoint, so every device costs its own requests — the refresh shows a progress bar and reports what it found, including how many devices are out of warranty and how many have a purchase date that had to be inferred. The cache survives quitting the app, and the Computers views read from it rather than the network.

Once data has been fetched, the Computers module gains three sortable columns — **Purchased**, **Warranty Ends** and **Lifecycle** — and an **Out of Warranty** filter. Right-click the table header to hide or reorder columns. Opening a computer shows an **Apple Business Manager** section with the purchase date and where it came from, warranty end with days remaining, the lifecycle date, order number, purchase source, and Apple's own model, capacity and colour.

The CSV export from the Computers module carries the same data joined together: the Jamf columns as before, plus Apple's model, capacity and colour, the purchase date and the source it was derived from, order number, warranty start and end, warranty status, the calculated lifecycle date, and the dates the device was added to or released from Apple Business Manager. Dates are written as `YYYY-MM-DD` so they sort correctly in Excel. These columns are omitted entirely if you are not using Apple Business Manager.

Warranty status distinguishes three things that look alike but are not: `NO_RECORD` means Apple holds no cover for the device, `UNAVAILABLE` means the warranty could not be fetched, and `NOT_IN_ABM` means Apple Business Manager has no record of the Mac at all.

A Mac that Jamf manages but Apple Business Manager has no record of still appears in the list, marked "Not in Apple Business Manager". That is deliberate: it is an asset management gap worth investigating, and it is a different thing from a Mac Apple simply holds no warranty record for.

Purchase dates are not all equally trustworthy. For devices bought through Apple or a reseller the order date is used directly. For devices added by hand through Apple Configurator, the order date records when someone added the device rather than when it was bought, so the warranty start date is used instead and the source is shown alongside it.

Two things to be aware of:

- An Apple Business Manager API account has **no read-only option**. The key you import can read your organisation's devices and also change them. Jamf Commander only ever reads, but store and share the key accordingly.
- The private key is kept in your Keychain and is **never** written to an exported settings file. Colleagues who want Apple Business Manager data need their own key.

## App Modules

### Dashboard

The dashboard is the starting point after connection. It shows clickable totals for computers, policies, profiles, and scripts. It also includes:

- Category manager for creating, renaming, and deleting categories.
- Device status summary based on recent computer inventory records.
- Export All action that writes a ZIP archive containing CSV files for computers, policies, profiles, and scripts.

### Computers

The Computers module uses Jamf Pro computer inventory records. You can:

- Search devices by name or serial number.
- Filter to all devices, managed devices only, or devices out of warranty.
- Sort by purchase date, warranty end or lifecycle date, and hide or reorder columns from the header's context menu.
- Export the visible computer data to CSV.
- Inspect a computer record.
- Copy a device serial number from the context menu.

The computer inspector includes tabs for:

- Hardware, OS, FileVault, IP address, last contact, and remote management status.
- Purchase, warranty and lifecycle data from Apple Business Manager, when configured.
- Installed configuration profiles.
- Available Jamf scripts.
- Policies.
- User and location data.

The Apple Business Manager columns, filter and inspector section are hidden entirely unless Apple Business Manager is configured. See the [Apple Business Manager](#apple-business-manager) section for setup.

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
- Packages CSV — the Installomator apps deployed in this tenant, with policy ID and name, label, application name, category, enabled state and pinned version
- All supported data as a ZIP archive

Exports use macOS save panels, so you choose the destination at export time.

The Computers CSV includes Apple Business Manager purchase, warranty and lifecycle columns when that data has been fetched, giving one file that answers who has a Mac, what it cost, when its cover ends and when it is due for replacement. Those columns come from the local cache, so an export never waits on Apple.

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
    ABMDeviceModels.swift
    ABMModels.swift
    ComputerFleetRow.swift
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
    ABMAPIService.swift
    ABMAPIService+Fleet.swift
    ABMCache.swift
    ABMClientAssertion.swift
    ABMFleetStore.swift
    ABMLog.swift
    ABMPrivateKey.swift
    CredentialStore.swift
    ExportService.swift
    JamfAPIService.swift
    JamfAPIService+Cloning.swift
    JamfAPIService+Dashboard.swift
    JamfAPIService+Packages.swift
    KeychainStore.swift
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
- `KeychainStore` and `CredentialStore` hold the Jamf and Apple Business Manager credentials in the Keychain; views observe `CredentialStore` rather than reading the Keychain themselves.
- `ABMAPIService` is a second, separate API client for Apple Business Manager, read-only by construction. `ABMPrivateKey` loads the key Apple issues, `ABMClientAssertion` signs the ES256 token request, and `ABMAPIService+Fleet` fetches the fleet scoped to one MDM server.
- `ABMCache` persists the fetched fleet to Application Support; `ABMFleetStore` is what the views read, so no list ever makes a request per row.
- `ComputerFleetRow` joins a Jamf computer to its Apple Business Manager record on serial number, and is the single source of the dates shown in the table, the inspector and the CSV.

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
- Apple Business Manager has no bulk warranty endpoint, so a full refresh makes one request per Mac and takes around a minute for 150 devices. It is cached for seven days rather than fetched on demand.
- Apple Business Manager purchase dates are only as good as what Apple holds. For devices added by hand through Apple Configurator there is no real purchase date, so the warranty start is used and labelled as inferred.
- An Apple Business Manager API account has no read-only option. The key you import can also change your organisation's devices. Jamf Commander only ever reads, but store and share the key accordingly.
- Apple's own API intermittently returns a header that macOS networking rejects, which shows in Xcode's console as `-1005` connection errors during a refresh. Requests are retried automatically and the fetch completes; the messages can be ignored.

## Contributing

When contributing, keep changes scoped to the relevant module or service. Prefer SwiftUI patterns, async/await, and strongly typed models for Jamf responses. Avoid storing secrets in source control, sample files, or screenshots.

## Disclaimer

Jamf Commander is an administrative tool that can modify production Jamf Pro data. Test against a non-production Jamf tenant before using bulk actions in production.
