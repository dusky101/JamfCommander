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

Important: `.jamfconfig` files are Base64 encoded for light obfuscation, not encrypted. Treat exported settings files as secrets and only share them through secure internal channels.

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

When adding selected labels to Jamf, the deployment sheet lets you choose:

- Target category.
- Installomator script.
- Policy name template, such as `Install {appName}`.
- Self Service options.
- Scope: all computers, specific computers, or computer groups.

Created policies use the selected Installomator script and pass the label in script parameter 4.

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
7. Choose Self Service and scope options.
8. Confirm deployment.

The app creates Jamf policies that call the selected script and use the selected Installomator label as parameter 4.

## Known Limitations

- `.jamfconfig` exports are obfuscated, not encrypted.
- The app assumes the Jamf API client has the required privileges for the selected action.
- Some inspectors expose raw source views, but not every visible editor control currently writes changes back to Jamf.
- Installomator label discovery depends on GitHub availability.
- Large Jamf tenants may take time to hydrate policy and profile details because detailed exports and dashboards fetch additional data in batches.

## Contributing

When contributing, keep changes scoped to the relevant module or service. Prefer SwiftUI patterns, async/await, and strongly typed models for Jamf responses. Avoid storing secrets in source control, sample files, or screenshots.

## Disclaimer

Jamf Commander is an administrative tool that can modify production Jamf Pro data. Test against a non-production Jamf tenant before using bulk actions in production.
