# EC2 Minecraft Scripts

A collection of scripts to install, maintain, and monitor a Minecraft Java server hosted on an AWS EC2 instance running **Amazon Linux 2023**.

## Scripts

| Script | Purpose | Run as |
| --- | --- | --- |
| [`scripts/install-server.sh`](#install-the-server) | Installs Java 21 and a vanilla Minecraft server as a `systemd` service | `sudo` |
| [`scripts/reset-world.sh`](#reset-the-world) | Backs up and regenerates the world, optionally with a given seed | `sudo` |
| [`scripts/upgrade-mods.sh`](#upgrade-to-fabric-and-install-mods) | Converts the vanilla server to Fabric and downloads mods from Modrinth | `sudo` |
| [`scripts/auto-shutdown.sh`](#auto-shutdown-when-the-server-is-idle) | Stops the server and powers off the instance after 30 minutes without players | `root` (cron) |
| [`scripts/index.js`](#sync-player-stats-to-s3) | Uploads player statistics to an S3 bucket as `stats.json` | `ec2-user` (cron) |

## Requirements

- An Amazon Linux 2023 EC2 instance with `sudo` access. The server defaults to 3 GB of RAM (`-Xmx3G`), so use an instance with at least 4 GB.
- A security group rule that allows inbound TCP traffic on port `25565`.
- Git, to clone this repository.
- For the stats sync only: Node.js, an S3 bucket, and an IAM role attached to the instance.

## Getting started

Clone the repository on the instance:

```bash
sudo dnf install -y git
cd /home/ec2-user
git clone https://github.com/angelverduzco/ec2-minecraft-scripts.git
cd ec2-minecraft-scripts
```

The shell scripts are executable, so run them directly (for example `sudo ./scripts/reset-world.sh`) instead of using `sudo bash <script>`. If a script is not executable after cloning, run `chmod +x scripts/*.sh`.

Server layout used by the shell scripts:

| Item | Value |
| --- | --- |
| Server directory | `/opt/minecraft/server` |
| Backups directory | `/opt/minecraft/backups` |
| System user | `minecraft` |
| Service | `minecraft.service` |

## Install the server

`scripts/install-server.sh` installs Amazon Corretto 21, creates the `minecraft` user, downloads the server jar, accepts the EULA, and registers and starts the `minecraft` service so it also starts on boot.

1. Open `scripts/install-server.sh` and set `MINECRAFTSERVERURL` to the server jar URL for the version you want (from the [official Minecraft download page](https://www.minecraft.net/en-us/download/server)). Do not add spaces around the `=`.
2. Run it:

   ```bash
   sudo ./scripts/install-server.sh
   ```

   The script waits about 40 seconds while the server generates its files, so it takes a minute to finish.

By running it you accept the [Minecraft EULA](https://aka.ms/MinecraftEULA).

Useful commands once the server is installed:

```bash
sudo systemctl status minecraft      # service status
sudo systemctl restart minecraft     # restart the server
sudo journalctl -u minecraft -f      # follow the server log
```

## Reset the world

`scripts/reset-world.sh` stops the server, saves a compressed backup of the current world to `/opt/minecraft/backups`, deletes it, sets the seed in `server.properties`, and starts the server again so it generates a new world.

```bash
sudo ./scripts/reset-world.sh                          # new world with a random seed
sudo ./scripts/reset-world.sh 123456789                # new world with a specific seed
sudo ./scripts/reset-world.sh "-4172144997902289642"   # quote negative seeds
sudo ./scripts/reset-world.sh --same-seed              # new world reusing the current seed (alias: -s)
```

| Option | Description |
| --- | --- |
| *(none)* | Generates the new world with a random seed. |
| `SEED` | Uses the given seed. Quote negative seeds. |
| `-s`, `--same-seed` | Regenerates the world reusing the current world's seed. Cannot be combined with `SEED`. |
| `-h`, `--help` | Prints the usage message and exits. |

The seed may only contain letters, digits, spaces, hyphens, and underscores; any other character is removed. The backup is named `<level-name>_<YYYYMMDD_HHMMSS>.tar.gz`.

### Reuse the current seed

Use `--same-seed` to get a fresh world (new chunks, no player-made changes) with the same terrain as the current one:

```bash
sudo ./scripts/reset-world.sh --same-seed
```

The script finds the current seed before stopping the server:

1. It reads `level-seed=` from `server.properties`.
2. If that value is empty (the world was created with a random seed), it reads the seed from `<level-name>/level.dat` using `python3`.

It then prints `>> Reusing current seed: <seed>`, backs up and deletes the world, writes the seed to `server.properties`, and restarts the server. If the seed cannot be determined, the script exits with an error **without stopping the server or touching the world**. In that case, run `/seed` in game and pass it explicitly:

```bash
sudo ./scripts/reset-world.sh "<seed>"
```

After the server starts, run `/seed` in game to confirm it matches the previous one. Note that the seed stays set in `server.properties`, so later resets without arguments will overwrite it with an empty value (random seed).

## Upgrade to Fabric and install mods

`scripts/upgrade-mods.sh` converts an already installed vanilla server to [Fabric](https://fabricmc.net/) and downloads the mods listed in the script, plus their required dependencies, from [Modrinth](https://modrinth.com/). The Fabric jar replaces `server.jar`, so the `start` script and the `systemd` service do not change. The original jar is kept as `server.vanilla.jar.bak`.

Edit the configuration block at the top of the script before running it:

| Variable | Purpose |
| --- | --- |
| `MC_VERSION` | Minecraft version to use. It must match your current world unless you wipe it. |
| `SEED` | New world seed. Leave empty to keep the current one. |
| `WIPE_WORLD` | `"yes"` backs up and deletes the world (needed for a new seed or terrain mods). Default is `"no"`. |
| `MODS` | List of mod names to look up on Modrinth. Mods without a Fabric build for `MC_VERSION` are skipped with a warning. |

```bash
sudo ./scripts/upgrade-mods.sh
```

Clients need the same mods and the Fabric loader to join a modded server. Back up the world before running this script, and review the output for skipped mods.

## Auto-shutdown when the server is idle

An EC2 instance is billed for compute while it is `running`, even if nobody is playing. `scripts/auto-shutdown.sh` checks every 10 minutes for established TCP connections on port `25565`. After 3 consecutive checks with no players (30 minutes), it stops `minecraft.service` gracefully so the world is saved, and then powers off the instance (`shutdown -h now`). The instance ends in the `stopped` state. Start it again from the EC2 console when you want to play.

### Requirements

- `cron`. Amazon Linux 2023 does not include it by default:

  ```bash
  sudo dnf install -y cronie
  sudo systemctl enable --now crond
  sudo systemctl status crond
  ```

- The `ss` command (from `iproute`), which is preinstalled on Amazon Linux 2023.
- Root privileges: the script runs from root's crontab because it stops a service and powers off the machine.

### Install

Copy the script to `/usr/local/bin` with root-only permissions:

```bash
cd /home/ec2-user/ec2-minecraft-scripts
sudo install -m 700 -o root -g root scripts/auto-shutdown.sh /usr/local/bin/mc-auto-shutdown.sh
```

Schedule it in root's crontab. Run `sudo crontab -e` and add this line (in `vi`, press `i` to insert, then `Esc`, `:wq`, `Enter` to save):

```cron
*/10 * * * * /usr/local/bin/mc-auto-shutdown.sh
```

Or add it without opening an editor (safe to run more than once):

```bash
(sudo crontab -l 2>/dev/null | grep -v mc-auto-shutdown; echo '*/10 * * * * /usr/local/bin/mc-auto-shutdown.sh') | sudo crontab -
```

Verify the job is registered:

```bash
sudo crontab -l
```

### Configure

The variables are at the top of the script. After editing `scripts/auto-shutdown.sh`, install it again with the `install` command above.

| Variable | Default | Purpose |
| --- | --- | --- |
| `PORT` | `25565` | Minecraft server port to monitor |
| `SERVICE_NAME` | `minecraft.service` | Service stopped before powering off |
| `COUNTER_FILE` | `/tmp/mc_idle_count` | Idle check counter (in `/tmp`, so it resets on reboot) |
| `MAX_CHECKS` | `3` | Consecutive idle checks before shutting down |
| `CHECK_INTERVAL_MIN` | `10` | Cron interval in minutes (only used in the log message) |

The idle time before shutdown is `MAX_CHECKS` × the cron interval. If you change the schedule (for example to `*/5 * * * *`), update `CHECK_INTERVAL_MIN` to match and adjust `MAX_CHECKS` to get the timeout you want.

### Test it

Before relying on the 30-minute timer, try a 2-minute version:

1. Edit the script to set `MAX_CHECKS=2` and `CHECK_INTERVAL_MIN=1`, install it again, and change the cron schedule to `* * * * *`.
2. Make sure nobody is connected, then watch the counter:

   ```bash
   watch -n 5 "cat /tmp/mc_idle_count 2>/dev/null || echo 'Waiting for the first check...'"
   ```

3. After about 2 minutes the counter reaches `2`, the server stops, your SSH session disconnects, and the instance goes from `running` to `stopped` in the EC2 console.
4. Start the instance, **connect via SSH within 2 minutes** (or the test timer shuts it down again), and restore `MAX_CHECKS=3`, `CHECK_INTERVAL_MIN=10`, and `*/10 * * * *`.

To confirm a shutdown was triggered by the script, search the system log:

```bash
sudo journalctl | grep "Minecraft Auto-Shutdown"
```

### Notes

- The public IPv4 address changes every time the instance is stopped and started, unless you attach an [Elastic IP](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html).
- The idle timer starts counting as soon as the cron job runs. After starting the instance, connect before the idle checks add up to the timeout, or the instance shuts down again.
- To disable the feature temporarily, remove the line from root's crontab (`sudo crontab -e`).

## Sync player stats to S3

`scripts/index.js` reads the player statistics from the server, combines them with the player names in `usercache.json`, and uploads the result to an S3 bucket as `stats.json`.

For each JSON file in `<MC_DIR>/world/stats`, it collects every stat category and metric (with the `minecraft:` prefix removed). The uploaded JSON has this shape:

```json
{
  "updatedAt": "2026-01-01T12:00:00.000Z",
  "availableStats": { "custom": ["deaths", "jump", "play_time"] },
  "players": [
    { "uuid": "00000000-0000-0000-0000-000000000000", "name": "Steve", "stats": { "custom": { "deaths": 3 } } }
  ]
}
```

Players missing from `usercache.json` are named `Unknown`.

### Install Node.js and dependencies

Install Node.js with [NVM, following AWS's instructions](https://docs.aws.amazon.com/sdk-for-javascript/v3/developer-guide/setting-up-node-on-ec2-instance.html), then install the dependencies from the repository directory:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install --lts
cd /home/ec2-user/ec2-minecraft-scripts
npm install --omit=dev
```

NVM installs Node.js under `/home/ec2-user/.nvm/versions/node/`. Find the exact executable with `nvm which current` (for example `/home/ec2-user/.nvm/versions/node/vXX.XX.X/bin/node`). In the commands below, replace `vXX.XX.X` with the version installed on your instance.

If `node` or `npm` fails with `error while loading shared libraries: libatomic.so.1`, install the missing library:

```bash
sudo dnf install -y libatomic
```

### Configure

The script uses these environment variables:

| Variable | Purpose |
| --- | --- |
| `MC_DIR` | Minecraft server directory containing `usercache.json` and `world/stats` (for example `/opt/minecraft/server`) |
| `S3_BUCKET` | Name of the destination S3 bucket |
| `AWS_REGION` | AWS region of the S3 bucket |

Attach an IAM role to the instance that allows `s3:PutObject` on `arn:aws:s3:::YOUR_BUCKET_NAME/stats.json`. The AWS SDK uses the instance role automatically. **Never put AWS access keys in the script, a `.env` file, or the crontab.**

Keep the settings in a `.env` file based on `.env.template`:

```bash
cd /home/ec2-user/ec2-minecraft-scripts
cp .env.template .env
nano .env
```

### Run once manually

With Node.js 20.6.0 or later:

```bash
/home/ec2-user/.nvm/versions/node/vXX.XX.X/bin/node \
  --env-file=/home/ec2-user/ec2-minecraft-scripts/.env \
  /home/ec2-user/ec2-minecraft-scripts/scripts/index.js
```

With an older version, load the variables from the shell first:

```bash
cd /home/ec2-user/ec2-minecraft-scripts
set -a; . ./.env; set +a
/home/ec2-user/.nvm/versions/node/vXX.XX.X/bin/node ./scripts/index.js
```

On success, `stats.json` is uploaded or replaced at the root of the bucket. Errors are printed to the output and the script exits with a non-zero code.

### Run automatically with cron

Open the `ec2-user` crontab with `crontab -e` and add a line like this to sync every 15 minutes:

```cron
*/15 * * * * /home/ec2-user/.nvm/versions/node/vXX.XX.X/bin/node --env-file=/home/ec2-user/ec2-minecraft-scripts/.env /home/ec2-user/ec2-minecraft-scripts/scripts/index.js >> /home/ec2-user/ec2-minecraft-scripts/sync.log 2>&1
```

For Node.js older than 20.6.0, source the `.env` file in the command instead:

```cron
*/15 * * * * set -a; . /home/ec2-user/ec2-minecraft-scripts/.env && set +a && /home/ec2-user/.nvm/versions/node/vXX.XX.X/bin/node /home/ec2-user/ec2-minecraft-scripts/scripts/index.js >> /home/ec2-user/ec2-minecraft-scripts/sync.log 2>&1
```

Cron runs with a limited environment, so use absolute paths everywhere. The script runs once and exits; check `sync.log` if a scheduled run fails. On Amazon Linux 2023, make sure the cron service is running:

```bash
sudo systemctl enable --now crond
```

## Updating the scripts

```bash
cd /home/ec2-user/ec2-minecraft-scripts
git pull
npm install --omit=dev
```

The next cron run uses the updated stats script. No Minecraft server restart is required.

## Safety notes

- `reset-world.sh` and `upgrade-mods.sh` (with `WIPE_WORLD="yes"`) delete the current world. Both save a backup first, but confirm it exists before relying on it, and keep copies off the instance (for example in S3).
- `auto-shutdown.sh` powers off the machine. Do not run it by hand while you are working on the server, and remove its cron entry if you need the instance to stay up (for example during maintenance).
- Try changes on a throwaway instance or a copy of the world before running them on the production server.
- Only download server jars and mods from official sources over HTTPS.

## Contributing

Project conventions and best practices are described in [`CLAUDE.md`](CLAUDE.md). All files must be written in English, and this README should be updated whenever a script's behavior or configuration changes.
