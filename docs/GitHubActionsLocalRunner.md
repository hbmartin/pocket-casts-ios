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
- Ruby `3.4.9`, preferably through `rbenv`.
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

## Secure Local Mac Setup

A self-hosted runner is not an isolated GitHub-hosted VM. Jobs run as real
processes on the Mac, can read files available to the runner user, can mutate the
runner user's home directory, and can persist changes in caches or shell startup
files unless the host is cleaned. Treat the runner Mac as build infrastructure,
not as a normal personal workstation.

GitHub's own guidance recommends avoiding self-hosted runners for public
repositories because pull requests can run dangerous code on the runner if the
workflows allow it. This fork keeps the runner usable by narrowing what reaches
the Mac:

- Register the runner at the repository level, not at the organization level.
- Keep the custom `pocket-casts-ios` label and only use it in workflows that are
  intended to run on this Mac.
- Keep fork PR jobs skipped unless a maintainer manually dispatches the workflow
  after reviewing the code.
- Keep release lanes manual and separate from public PR execution.
- Avoid storing release credentials in GitHub repository secrets when the local
  Fastlane setup already keeps them on the Mac.

### Recommended Host Model

Use a dedicated Mac or a dedicated macOS user. A dedicated Mac is best for
release work because the runner needs access to signing material, App Store
Connect credentials, and local Fastlane configuration. If sharing a Mac, use a
separate non-admin account such as `github-runner` or `pocketcasts-runner`.
Create it through System Settings or with `sysadminctl`, set a strong unique
password, and do not grant administrator rights:

```bash
sudo sysadminctl -addUser github-runner -fullName "GitHub Runner" -shell /bin/zsh -password -
sudo createhomedir -c -u github-runner
```

Then log in as that user for Xcode setup, simulator runtime installation, Ruby,
Bundler, Homebrew, and runner registration. Do not run the runner service as
`root`. Use `sudo` only for one-time service installation commands that require
it.

Recommended local layout:

```text
/Users/github-runner/actions-runner/pocket-casts-ios
/Users/github-runner/.configure/pocketcasts-ios
/Users/github-runner/.a8c-apps/pocket-casts-ios.env
/Users/github-runner/.bundle
/Users/github-runner/.gem
```

Lock down the runner and secret directories so other local accounts cannot read
them:

```bash
chmod 700 /Users/github-runner
chmod -R go-rwx /Users/github-runner/actions-runner
chmod -R go-rwx /Users/github-runner/.configure
chmod -R go-rwx /Users/github-runner/.a8c-apps
```

If the Mac is used interactively, keep the runner account separate from the daily
driver account. Do not browse the web, install untrusted developer tools, or run
ad hoc scripts while logged in as the runner user.

### macOS Baseline

Before registering the runner:

- Enable FileVault for the startup disk.
- Enable automatic macOS security updates.
- Keep Xcode, Command Line Tools, Homebrew, Ruby, Bundler, Tailscale, and
  `cloudflared` current.
- Enable the macOS application firewall and leave inbound services disabled
  unless they are explicitly needed.
- Disable Remote Login, Screen Sharing, Remote Management, file sharing, AirDrop,
  printer sharing, and Bluetooth sharing unless there is a documented use.
- Require a password immediately after sleep or screen saver.
- Keep the Mac on stable power and network. CI jobs are long enough that display
  sleep, system sleep, or network sleep can interrupt a job.
- Use encrypted backups if backing up the runner account. Do not back up signing
  keys or release env files to an unencrypted disk or consumer cloud sync folder.

For a laptop runner, configure power settings so AC power keeps the system awake
while CI is expected to run:

```bash
sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 1
```

Avoid weakening security globally to make CI pass. If a build needs keychain,
simulator, or Xcode permissions, grant the narrow permission to the runner user
and document it here.

### Network Exposure

The GitHub Actions runner does not require inbound connectivity from the
internet. The runner connects outbound to GitHub over HTTPS, receives jobs, and
downloads runner updates through that outbound connection. Do not port-forward
SSH, VNC, Screen Sharing, or a local web UI from the home router to the Mac.

Minimum network posture:

- Allow outbound HTTPS from the runner to GitHub and to the package/update
  services used by the workflow: Apple, Homebrew, RubyGems, SwiftPM package
  hosts, Semgrep, and any release tooling endpoints.
- Block unsolicited inbound traffic at the router and on macOS.
- Prefer private remote access through a tailnet or Cloudflare Access instead of
  opening public ports.
- Keep the runner Mac on a trusted VLAN or network segment if available.
- Do not use the runner as a general-purpose subnet router, exit node, or public
  tunnel host unless that is intentionally part of the setup.

If outbound traffic is allowlisted, leave room for GitHub runner auto-updates.
Disabling or blocking runner updates requires active maintenance; GitHub can stop
queueing jobs to an out-of-date runner, especially for security updates.

### Secrets And Signing Material

Public CI should not need signing credentials. The workflows run
`make external_contributor` before build, test, and static check jobs so normal
CI can build with signing disabled or with placeholder contributor setup.

Release jobs are different. They need Fastlane, App Store Connect, code signing,
Slack, Bitdrift, and GitHub release permissions. Keep those credentials scoped
and inspectable:

- Prefer local env files or Keychain items under the runner account for release
  credentials.
- Do not put secrets inside the repository checkout, `_work`, `Downloads`, shell
  history, or any folder synced by iCloud Drive, Dropbox, Google Drive, or
  similar tools.
- Keep env files at `chmod 600` and parent directories at `chmod 700`.
- Avoid echoing environment variables in shell scripts. GitHub masking only
  protects values it knows about.
- Use a dedicated `POCKET_CASTS_RELEASE_GITHUB_TOKEN` with only the permissions
  needed by the release lanes.
- Rotate App Store Connect keys, GitHub tokens, Slack webhooks, Bitdrift keys,
  and signing credentials after any suspicious runner job.

The ideal split is two runner identities:

- `pocket-casts-ios-ci`: no signing secrets, eligible for normal build, test,
  static check, and reviewed manual fork-PR jobs.
- `pocket-casts-ios-release`: has signing and release credentials, eligible only
  for manual release workflows.

If both labels run on the same physical Mac, the security boundary is weaker
because jobs still share the same OS, caches, and sometimes the same user. Use
separate macOS users at minimum, and separate Macs if release credentials are
high value.

### Runner Service Hygiene

Install the runner service under the account that owns the Xcode, Ruby, Bundler,
and Fastlane setup. After installing, check the service owner and logs:

```bash
sudo ./svc.sh status
ps aux | grep '[R]unner.Listener'
```

Operational practices:

- Keep one runner process per runner directory.
- Do not reuse the same runner directory for multiple repositories.
- Do not install random shell aliases, prompt hooks, or path-mutating scripts in
  the runner account.
- Review `~/.zshrc`, `~/.zprofile`, `~/.bash_profile`, and LaunchAgents for
  unexpected commands.
- Periodically remove stale work directories and derived data after confirming no
  job is running.
- Prefer deterministic workflow cleanup steps over manually deleting files during
  a job.

Useful cleanup commands when the runner is idle:

```bash
rm -rf /Users/github-runner/actions-runner/pocket-casts-ios/_work/*
rm -rf /tmp/pocketcasts-sim-deriveddata
xcrun simctl shutdown all
```

Do not clean while a job is running. Check GitHub's runner page or
`svc.sh status` first.

### Workflow Guardrails

Keep these rules in place when changing workflows:

- Use explicit `permissions:` blocks. Default to `contents: read` for CI and
  grant write permissions only where the lane requires them.
- Do not expose release secrets to `pull_request` jobs.
- Do not use `pull_request_target` for build or test jobs.
- Do not evaluate PR-controlled text directly in shell scripts. Assign it to an
  environment variable first if it must be used.
- Pin third-party actions to trusted versions, and prefer commit SHAs for actions
  that handle secrets.
- Keep manual fork-PR dispatch as a deliberate trust decision.
- Treat reusable workflows and composite actions as executable code with the same
  review bar as shell scripts.

## Remote Access Options

Remote access is optional for the runner. GitHub Actions itself works without a
tailnet, Cloudflare Tunnel, VPN, router port forwarding, or public hostname. Use
remote access only for administration, logs, controlled local web tools, or
recovery when the Mac is away from your desk.

Choose one of these models:

| Model | Best For | Exposure | Notes |
| --- | --- | --- | --- |
| No tunnel | A Mac you can physically access | None beyond outbound CI traffic | Most secure and simplest. |
| Tailscale tailnet | Private SSH/admin access from your own devices | Private to tailnet ACLs | Recommended default for personal or small-team runner admin. |
| Tailscale Serve | Sharing a local web service only inside the tailnet | Private to tailnet ACLs | Useful for local dashboards or logs. |
| Tailscale Funnel | Temporary public sharing | Public internet | Avoid for runner admin; use only for short-lived, non-secret services. |
| Cloudflare Tunnel with Access | Browser-based or SSH access through Cloudflare Zero Trust | Public hostname protected by Access | Good when you already manage a Cloudflare domain and identity policies. |

Do not expose the runner listener, the repository checkout, DerivedData, Fastlane
logs, or any file browser over a public tunnel.

### Option A: Private Tailnet Access With Tailscale

Use Tailscale when you want the runner Mac reachable only from devices and users
in your tailnet. This is the preferred remote administration path because it does
not require router port forwarding or a public DNS hostname.

Setup outline:

1. Install Tailscale on the Mac.
2. Sign in using the runner owner's tailnet account.
3. Rename the device in the Tailscale admin console to something stable, for
   example `pocket-casts-runner`.
4. Disable key expiry only if you have another process for reviewing and removing
   stale devices.
5. Do not enable exit node, subnet router, or app connector features for this Mac
   unless you have a specific need.
6. Use Tailscale SSH or bind normal SSH access to the Tailscale network only.
7. Restrict access with tailnet policy grants and SSH rules.

Example tailnet policy fragment using grants. If you use this exact shape, tag
the Mac as `tag:github-runner`; otherwise replace that destination with the
runner's actual tailnet device name or another narrow selector.

```json
{
  "groups": {
    "group:runner-admins": ["you@example.com"]
  },
  "tagOwners": {
    "tag:github-runner": ["group:runner-admins"]
  },
  "grants": [
    {
      "src": ["group:runner-admins"],
      "dst": ["tag:github-runner"],
      "ip": ["tcp:22"]
    }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["group:runner-admins"],
      "dst": ["tag:github-runner"],
      "users": ["github-runner"]
    }
  ]
}
```

Use `action: "check"` for human administration so Tailscale requires a fresh
identity check before SSH. Keep `users` to the dedicated runner account rather
than `root` or `autogroup:nonroot`.

Enable Tailscale SSH on the Mac only after the policy is ready:

```bash
sudo tailscale set --ssh=true
```

Then connect from an approved device:

```bash
ssh github-runner@pocket-casts-runner
```

If using normal macOS Remote Login instead of Tailscale SSH, keep Remote Login
limited to the runner admin users and rely on the tailnet ACL for network reach.
Do not add router port forwarding for TCP 22.

For temporary local web tools, use Tailscale Serve so the service is available
only inside the tailnet:

```bash
tailscale serve 3000
tailscale serve status
tailscale serve reset
```

Use Serve for things like a temporary static log viewer or local dashboard. Do
not serve the repository root, `~/.ssh`, `~/.configure`, `~/.a8c-apps`, Fastlane
logs with secrets, or DerivedData.

Avoid Tailscale Funnel for this runner. Funnel publishes a local service to the
broader internet. If it is ever used, make it temporary, expose only a harmless
service, verify the exact URL, and run:

```bash
tailscale funnel status
tailscale funnel reset
```

after the maintenance window.

### Option B: Cloudflare Tunnel With Cloudflare Access

Use Cloudflare Tunnel when you already have a Cloudflare-managed domain and want
remote access through Cloudflare Zero Trust policies. A tunnel still lets the Mac
keep inbound firewall ports closed because `cloudflared` creates outbound-only
connections to Cloudflare.

Recommended Cloudflare model:

1. Create the Access application first.
2. Add identity-based Allow policies for the specific admins who may reach the
   runner.
3. Require MFA and, if available, device posture checks.
4. Create the tunnel.
5. Route only the specific hostname and service that should be reachable.
6. Enable Access protection for the tunnel route.
7. Leave the final tunnel ingress rule as `http_status:404`.

Install and authenticate `cloudflared`:

```bash
brew install cloudflared
cloudflared tunnel login
cloudflared tunnel create pocket-casts-runner
```

Example `~/.cloudflared/config.yml` for a protected local web tool:

```yaml
tunnel: <TUNNEL_UUID>
credentials-file: /Users/github-runner/.cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: runner-admin.example.com
    service: http://127.0.0.1:3000
  - service: http_status:404
```

Example for SSH through Access:

```yaml
tunnel: <TUNNEL_UUID>
credentials-file: /Users/github-runner/.cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: runner-ssh.example.com
    service: ssh://127.0.0.1:22
  - service: http_status:404
```

This tunnel route only connects Cloudflare to the Mac's local SSH service. The
admin machine still needs the Cloudflare Access client flow, WARP routing, or the
Cloudflare SSH configuration that matches the Access application. Do not treat
the public hostname as normal open SSH.

Install `cloudflared` as a macOS service only after the Access policy and tunnel
route are correct:

```bash
cloudflared service install
```

That installs a launch agent for the current user and uses
`~/.cloudflared/config.yml`. If you install with `sudo`, Cloudflare uses a launch
daemon and expects configuration under `/etc/cloudflared`; do that only if you
intentionally want the tunnel running before any user logs in.

Cloudflare Access policy guidance:

- Do not use a `Bypass` policy for runner admin hostnames.
- Avoid broad selectors like "everyone", "any valid email", or a whole email
  domain unless that is truly the intended admin group.
- Use short session durations for runner admin applications.
- Use service tokens only for automation. Human admin access should use a human
  identity provider with MFA.
- If a service token is needed, set an expiration alert and delete the token to
  revoke it. Refreshing sessions alone does not revoke a still-valid service
  token.
- Validate that direct origin access fails. The local service should not be
  reachable except through `localhost`, the tailnet, or the Access-protected
  tunnel.

Do not publish the runner account's home directory, the repository checkout, or a
generic file browser. If you need logs, publish a narrow log viewer that redacts
secrets and reads only a dedicated log directory.

## Maintenance And Incident Response

Review the runner monthly or after any workflow/security change:

- Confirm the runner is still registered only to this repository.
- Confirm labels match the workflows that should use the Mac.
- Confirm fork PRs still skip before runner assignment.
- Confirm no release secrets are available to public CI jobs.
- Confirm `svc.sh status` reports one expected runner service.
- Confirm Tailscale or Cloudflare policy still names only expected admins.
- Confirm no router port forwards point at the runner.
- Confirm local secret files are not world-readable.
- Confirm the runner account has no unexpected LaunchAgents, shell profile
  commands, SSH keys, or cron jobs.
- Confirm runner, macOS, Xcode, Tailscale, and `cloudflared` updates are current.

If a malicious or suspicious job may have run:

1. Stop the runner service:

   ```bash
   sudo ./svc.sh stop
   ```

2. Remove the runner from GitHub repository settings so it cannot receive more
   jobs.
3. Disconnect Tailscale or stop `cloudflared` if remote access may be involved.
4. Preserve runner logs if investigation is needed.
5. Rotate local and GitHub-held credentials: GitHub release token, App Store
   Connect API keys, signing certificates/profiles, Slack webhook, Bitdrift key,
   Tailscale keys, Cloudflare service tokens, and any Fastlane secrets.
6. Rebuild the runner from a known-good macOS account or clean OS install. Do not
   trust caches, shell profiles, Homebrew packages, Ruby gems, or DerivedData
   from the compromised account.
7. Register a new runner token and reapply labels only after the host is clean.

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

## References

- [GitHub Actions secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub self-hosted runner setup](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)
- [GitHub self-hosted runner reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)
- [Tailscale Funnel](https://tailscale.com/docs/features/tailscale-funnel)
- [Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh)
- [Tailscale grants syntax](https://tailscale.com/docs/reference/syntax/grants)
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Cloudflare Access self-hosted applications](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/)
- [Cloudflare Tunnel as a macOS service](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/as-a-service/macos/)
- [Cloudflare Access service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/)
