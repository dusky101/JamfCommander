# Creating the Blueprints integration

Blueprints need a **second, separate credential**. It is not the API client you made in Jamf Pro, it
is not created in Jamf Pro at all, and no amount of Jamf Pro privileges will make the first one work
here.

If you are not using the Blueprints module, you can skip this page entirely.

## Why it is separate

Blueprints are served by Jamf’s Platform API Gateway rather than by your Jamf Pro instance — a
different host, with its own permission model. Permissions there are **capabilities**, granted to an
**integration** you create in **Jamf Account**, and scoped to a **platform environment** rather than
to a single tenant.

A platform environment is the group of tenants your organisation has across the Jamf platform. Platform
APIs work at that level, which is why the scope level matters below.

## Making it

1. Sign in to **Jamf Account** and choose **Integrations** in the left-hand navigation.
2. Choose **Create integration**, and give it a name — “Commander”, for example — and
   optionally a description.
3. Set the **scope level** to **platform environment**. This is the step that decides whether it
   works: an integration scoped to a single tenant cannot reach the platform APIs.
4. Assign permissions by browsing the **capabilities** and granting only these six:
   `blueprints:read`, `blueprints:create`, `blueprints:update`, `blueprints:delete`,
   `blueprints:deploy`, and `device-groups:read`.
5. Choose **Create integration**. Jamf Account then shows you the **client ID** and **client
   secret**.
6. Copy the **environment ID**: open the integration in Jamf Account and click the environment pill
   in the **Integration details** panel to copy it to the clipboard. It is a UUID, and it looks like
   `cda24521-f23b-4f27-a9ff-32c89fb6feeb`.

Jamf’s own instructions, with screenshots, are at
[https://developer.jamf.com/platform-api/reference/getting-started-with-platform-api](https://developer.jamf.com/platform-api/reference/getting-started-with-platform-api).

> **Warning:** The client secret is shown once. If you lose it you must generate a new one.

## Putting it into Commander

Open **Settings → Jamf Connections** and find **Platform API — Blueprints**.

- **Region** — it must match where your Jamf instances are actually hosted, not where you
  are.
- **Environment ID** — the UUID from step 6 above.
- **Client ID** and **Client Secret** — from step 5 above.

Then press **Test Connection**. It proves all four at once, which is worth doing before you
go looking for a fault in the module.

## Four things that catch people out

### The region is not cosmetic

Access tokens are issued per region and refused by every other one.
Choose the wrong region and every call fails with a **401**, which reads exactly like a bad secret.

### Scope level is the usual cause of a 403

On this API a 403 means one of three things: a
capability you did not grant, an integration scoped to a tenant instead of a platform environment,
or a version segment the gateway did not recognise. It does not mean the blueprint does not exist.

### The integration expires

Jamf integrations are valid for **six months**. Plan the rotation —
when it lapses, Blueprints stops working and nothing else in the app is affected, which makes it a
confusing failure if you have forgotten this page.

### It travels in a `.jamfconfig` file

An export carries these four values along with the Jamf Pro
credentials. Treat that file as the secret it is — see *Sharing your settings*.

> **Note:** Until all four fields are filled in, the Blueprints module says it is not configured and
> offers a button straight to Settings. It does not fail quietly.
