# CLAUDE.md

## Project overview

A collection of scripts that automate actions on a Minecraft Java server. The target host is an AWS EC2 instance running **Amazon Linux 2023** (the Amazon Linux AMI). Scripts are meant to be run on that instance, not on the developer's Windows machine.

## Language

- Every file created or edited in this repo must be written in **English**: code, comments, log/echo messages, commit messages, README, and docs.
- Existing Spanish comments or strings should be translated to English when the surrounding code is touched.

## Layout

- `scripts/index.js`: Node.js (ESM) script. Reads player stats from `<MC_DIR>/world/stats` and `usercache.json`, then uploads a consolidated `stats.json` to S3. Configured via `MC_DIR`, `S3_BUCKET`, `AWS_REGION` (see `.env.template`). Meant to run from cron.
- `scripts/install-server.sh`: Installs Corretto 21, downloads the server jar, creates the `minecraft` user, and sets up the `minecraft.service` systemd unit.
- `scripts/reset-world.sh`: Stops the server, backs up the world to `/opt/minecraft/backups`, deletes it, optionally sets a seed, and restarts.
- `scripts/upgrade-mods.sh`: Mod upgrade automation.
- `README.md`: Setup and usage instructions for the stats sync (EC2, NVM, cron, IAM).

Server conventions used by the shell scripts: server files live in `/opt/minecraft/server`, run as user `minecraft`, managed through the `minecraft` systemd service.

## Commands

- Install deps: `pnpm install` (a `pnpm-lock.yaml` is committed; keep it in sync). The README uses `npm install --omit=dev` on the EC2 instance.
- Run the stats script locally: `node --env-file=.env scripts/index.js` (Node 20.6+).
- There are no tests yet. Validate shell scripts with `bash -n <file>` and `shellcheck <file>` when available.

## Best practices

### Shell scripts

- Start with `#!/bin/bash`; prefer `set -euo pipefail` for new scripts (use `set -u` at minimum when a step may legitimately fail).
- Quote all variable expansions (`"$VAR"`), and validate or sanitize user input (see seed sanitizing in `reset-world.sh`).
- Make destructive operations safe: back up before deleting, check the target path is non-empty and expected before `rm -rf`, and stop the service before touching world files.
- Require root explicitly (`id -u` check) when a script needs `sudo`, and print a clear usage message.
- Be idempotent where possible (re-running should not duplicate lines in files such as `server.properties`, or fail if a user/dir already exists).
- Use Amazon Linux 2023 tooling: `dnf` (`yum` is an alias), `systemctl`, `journalctl`. Do not assume `apt`.
- Prefer a graceful shutdown (`systemctl stop minecraft`) over `kill -9`.
- Keep paths in variables at the top of the script instead of repeating literals.
- Log progress with consistent `>>` prefixed messages.

### Node.js

- ESM only (`"type": "module"`); use `node:` prefixes for built-ins.
- Configuration comes from environment variables, never hardcoded. Do not commit real bucket names, regions, or paths as defaults that leak private infrastructure.
- Never put AWS credentials in code, `.env`, or crontab. Use the EC2 instance profile (IAM role) with least privilege (`s3:PutObject` on the specific key).
- Fail loudly: log errors and exit non-zero so cron/monitoring can detect failures.
- Keep dependencies minimal; add them with `pnpm add` and commit the lockfile.

### Security and secrets

- `.env` is git-ignored; only `.env.template` with placeholder values is committed.
- Do not commit server worlds, backups, `server.properties` secrets (e.g. RCON password), or IP addresses.
- Treat downloaded jars/mods as untrusted: use official sources over HTTPS and verify checksums when the source provides them.

### Git and docs

- Make small, focused commits with descriptive messages. Existing history uses a `feat:` prefix style.
- Update `README.md` whenever a script's behavior, requirements, or configuration changes.
- Test changes on a throwaway EC2 instance (or a copy of the world) before running destructive scripts on the production server.
