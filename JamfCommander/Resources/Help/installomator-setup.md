# Before using Installomator

The Installomator module does not upload package files. It manages **Installomator install
policies** — so your Jamf environment must already contain the Installomator script. Without it, the
deployment sheet has nothing to select and no policies can be created.

1. Download the current Installomator release from `github.com/Installomator/Installomator`.
2. In Jamf Pro, go to **Settings → Computer management → Scripts** and choose **New**.
3. Name it so that the name contains “Installomator” — the app pre-selects a script whose name
   matches, which saves choosing it every time.
4. Paste the contents of `Installomator.sh` into the **Script** tab.
5. On the **Options** tab, set the parameter labels so the values are readable later: parameter 4
   “Label”, 5 “Option”, 6 “Option”, and 7 to 11 “Override”.

```figure
script-parameters
```

## What the app passes

When it creates a policy, the app fills in:

- **Parameter 4** — the Installomator label, for example `googlechrome`
- **Parameter 5** — `DEBUG=0`
- **Parameter 6** — `NOTIFY=silent`
- **Parameters 7 to 11** — optional version-pinning overrides

> **Note:** The script may be named anything you like. If it is not called “Installomator”, pick it
> once in the deployment sheet and the app remembers it — after that, policies using it are
> recognised as Installomator deployments, even if the script is later renamed.

## Network access

The Installomator module needs outbound access to `raw.githubusercontent.com`. That is where the
upstream label list and the per-label explanations are read from — the labels come from the
Installomator project, not from Jamf. If GitHub is unreachable the module says so, and marks nothing
as missing; nothing else in the app is affected.
