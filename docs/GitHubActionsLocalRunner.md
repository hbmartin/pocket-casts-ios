# GitHub Actions Local Mac Runner

This fork runs its iOS CI on a repo-level GitHub Actions self-hosted macOS runner.

## Runner Registration

Create the runner from:

```text
GitHub repository > Settings > Actions > Runners > New self-hosted runner
```

Install it on the Mac that should build Pocket Casts, then add the repo-specific label:

```bash
./config.sh --url https://github.com/hbmartin/pocket-casts-ios --token <TOKEN> --labels pocket-casts-ios
```

The workflows target:

```yaml
runs-on: [self-hosted, macOS, pocket-casts-ios]
```

GitHub automatically provides the `self-hosted` and `macOS` labels. The custom
`pocket-casts-ios` label prevents unrelated self-hosted runners from picking up
this repo's iOS jobs.

Install and start the runner service under the macOS user that has access to
Xcode, simulators, Ruby, and any local Fastlane secrets:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

Keep the Mac awake while jobs are expected to run. CI builds can be long enough
that display sleep, system sleep, or network sleep can interrupt a job.

## Required Local Tools

The runner needs:

- Xcode compatible with `.xcode-version` or another Swift 6 capable Xcode.
- An installed iPhone simulator runtime. Set repository variable `IOS_SIMULATOR_RUNTIME_VERSION` to pin one, for example `18.5`.
- Ruby `3.2.2`, preferably through `rbenv`.
- Bundler and Homebrew.
- Semgrep. CI can install it with Homebrew if it is missing.

Basic CI does not need Apple signing secrets. The workflow runs
`make external_contributor` before build, test, and static check jobs.

## Public Repository Safety

This repository is public, so automatic Mac-runner jobs are restricted to pushes
and pull requests whose source branch is in this same repository. Pull requests
from forks are skipped before a runner is assigned.

To run CI for a reviewed fork PR, use the `iOS CI` workflow's manual dispatch and
enter the PR number. That intentionally checks out `refs/pull/<number>/head` on
the local Mac, so only do this after reviewing the PR code enough to trust it on
the runner.

Do not switch the workflows to `pull_request_target` for build jobs. That event
can expose write tokens and secrets to code from pull requests if used
incorrectly.

## Release Workflows

Release automation runs through `.github/workflows/release-fastlane.yml` on the
same Mac runner. The workflow supports these manual tasks:

- `code_freeze`
- `new_hotfix_release`
- `new_beta_release`
- `finalize_hotfix_release`
- `finalize_release`
- `publish_release`
- `release_build`

Release jobs require the existing local Fastlane/App Store setup on the runner,
including files under `~/.configure/pocketcasts-ios` and
`~/.a8c-apps/pocket-casts-ios.env` when those are how the Mac is configured.

Configure repository or environment secret `POCKET_CASTS_RELEASE_GITHUB_TOKEN`
with a token that has the permissions needed by the release lanes:

- Actions workflow dispatch.
- Contents and release writes.
- Pull request and issue writes.
- Branch protection administration if the lane edits protection rules.

Fastlane receives this value as `GITHUB_TOKEN`.

Release builds also need the normal release environment used by Fastlane,
including App Store Connect API values, code signing access, `SLACK_WEBHOOK`, and
`BITDRIFT_API_KEY`.
