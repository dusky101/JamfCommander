# Creating the API client in Jamf Pro

In Jamf Pro, go to **Settings → System → API roles and clients**.

1. On the **API Roles** tab, choose **New**. Give the role a name such as “Jamf Commander”, then add
   the privileges listed in *Privileges* and save.
2. On the **API Clients** tab, choose **New**. Give the client a display name, assign the role you
   just created, and set an access token lifetime — 30 minutes is ample.
3. Save, then **Enable** the client.
4. Choose **Generate client secret** and copy it immediately.

> **Warning:** The client secret is shown once. If you lose it you must generate a new one, which
> invalidates the old secret.

Copy the Client ID from the same screen, and use your Jamf URL as the instance URL.

Jamf’s own documentation for this screen is at
[https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/API_Roles_and_Clients](https://learn.jamf.com/r/en-US/jamf-pro-documentation-current/API_Roles_and_Clients).

Grant only the privileges you actually intend to use. The role is what Jamf enforces, so a narrower
role is a real safeguard rather than a cosmetic one — an app that cannot delete policies cannot
delete them by accident either.
