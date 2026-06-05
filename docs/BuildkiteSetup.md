# Buildkite Setup

This fork is configured to run Buildkite in the `hbmartin` organization without depending on Automattic's private Buildkite plugins or queues.

## Prerequisite

Push the local Buildkite changes to `hbmartin/pocket-casts-ios` before testing the pipeline. Buildkite reads `.buildkite/bootstrap.sh` and `.buildkite/pipeline.yml` from the remote repository, so it cannot see unpushed local files.

## Agent Queue

Make sure Buildkite has a macOS queue named exactly:

```text
macos-large
```

The pipeline targets this queue in `.buildkite/pipeline.yml`.

New Buildkite organizations include default queues such as `macos-large`. macOS hosted agents require a Buildkite Pro or Enterprise plan. If you are using a self-hosted Mac instead, create a self-hosted queue named `macos-large` and run your Mac agent with that queue tag.

## Pipeline

Create or edit the Buildkite pipeline with these values:

- Organization: `hbmartin`
- Pipeline slug: `pocket-casts-ios`
- Repository: `git@github.com:hbmartin/pocket-casts-ios.git`
- Default branch: `trunk`

In the Buildkite YAML Steps editor, set exactly:

```yaml
steps:
  - label: ":pipeline: Upload pipeline"
    command: .buildkite/bootstrap.sh
    agents:
      queue: macos-large
```

## GitHub Settings

In the Buildkite pipeline GitHub settings:

- Enable builds for pull requests.
- Enable builds for pushes to `trunk`.
- Enable commit statuses.
- If Buildkite asks you to add a GitHub webhook, use the URL it gives you, content type `application/json`, and events: Pull requests, Pushes, Merge groups, Deployments.

## Environment Variables

For basic CI, no Buildkite environment variables are required.

Optional variables:

- `DANGER_GITHUB_API_TOKEN`: enables Danger comments/checks.
- `ENABLE_DISTRIBUTION_JOBS=true`: shows TestFlight/Firebase distribution jobs. Leave this unset unless Apple signing, App Store Connect, Firebase, Sentry, and GitHub release secrets are configured.
- `BUILDKITE_PIPELINE_SLUG`: only needed if the pipeline slug is not `pocket-casts-ios`.
- `IOS_SIMULATOR_RUNTIME_VERSION`: pins simulator selection to an installed iOS runtime version such as `18.5`; when unset the build step uses the newest available iPhone runtime.

## Optional GitHub Retry Workflow

The GitHub workflow at `.github/workflows/run-danger.yml` can retry the Buildkite Danger step when pull request labels or milestones change.

To enable it, configure the GitHub repository with:

- Repository variable: `ENABLE_BUILDKITE_DANGER_RETRY=true`
- Repository secret: `TRIGGER_BK_BUILD_TOKEN`

Leave the variable unset to keep the workflow disabled.
