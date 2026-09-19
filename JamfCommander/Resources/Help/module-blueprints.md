# Blueprints

Declarative device management blueprints — Apple’s successor to the profile, applied by the Mac
itself rather than pushed as a payload.

Blueprints are the one module that does **not** talk to your Jamf Pro instance. They are served by
Jamf’s Platform API Gateway, which is a different host with its own credentials. Until those are
filled in, this module says so and offers a button straight to Settings. See *Creating the Blueprints
integration*.

## What you can do

- **List** every blueprint with its name, description, last-updated date, and the deployment state
  the server reports.
- **Search** across name and description.
- **Inspect** one — an overview beside its complete definition as JSON. The definition is shown
  verbatim rather than parsed into fields, because a component’s `configuration` may carry any Apple
  payload key, and a field-by-field view would quietly drop the ones it did not recognise.
- **Create** with **+**. Type or paste the JSON, or load it from a `.json` file. Server-managed
  fields are stripped, so a definition copied from an existing blueprint can be pasted straight in as
  a starting point.
- **Scope** it three ways: leave the `scope` in your JSON alone, pick device groups from the
  environment, or send it unscoped.
- **Edit** an existing blueprint — its current definition is loaded into the editor.
- **Deploy, undeploy and delete** from the row menu, each behind a confirmation.

## Creating a blueprint does not apply anything

Blueprints are created **undeployed**. Nothing reaches a Mac until you choose **Deploy**, which is
deliberate: it gives you a chance to read the definition back before it is live.

## Deploy and undeploy are reported as *requested*

The server answers a deploy or undeploy by accepting the job, not by finishing it — the work
completes afterwards. So the app reports these as requested rather than completed, and never claims a
deployment succeeded on the strength of the response.

**The deployment state in the list is what confirms the outcome.** Refresh and read it.

## Editing changes only the keys you leave in

An edit sends a merge: any key you remove from the JSON is **left as it is on the server**, not
deleted. If you want to clear something, set it explicitly rather than deleting the line.

## Bringing settings in from the Jamf DDM app

There is no graphical DDM builder here — settings are authored in the Jamf DDM app, or by hand, and
brought in as JSON.

Paste what the DDM app produces and a **DDM Declaration** panel appears. Give it a declaration type
and a channel, press **Wrap as Blueprint**, and the editor rewrites itself as a complete blueprint
with the declaration inside the right component. It rewrites the editor rather than doing it silently
at save, so you can read exactly what will be sent.

Blueprints built this way can carry component types that Jamf’s own blueprint builder does not list.

> **Note:** Jamf documents at least one device group as required on a blueprint’s scope, so an
> unscoped blueprint may be refused. Whatever the server answers is reported in full rather than
> translated into a guess.
