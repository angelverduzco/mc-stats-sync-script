# Minecraft Server Stats Sync

This script reads player statistics from a Minecraft server, combines them with player names from `usercache.json`, and uploads the result to an AWS S3 bucket as `stats.json`.

For each JSON file in `world/stats`, the script collects the player's UUID, name, play time in ticks, deaths, mob kills, and jumps. The uploaded JSON includes an `updatedAt` timestamp and a `players` array.

## Requirements

- An Amazon Linux 2023 EC2 instance with access to the Minecraft server files
- Node.js and Git
- An S3 bucket
- AWS credentials available to the process. On EC2, the recommended option is an instance profile (IAM role) with permission to write `stats.json` to the bucket. Do not put AWS access keys in the script or crontab.

## Configure and install on EC2

Install Node.js and Git if needed, then clone the repository. The example uses `/home/ec2-user/mc-stats-sync` as the installation directory:

```bash
sudo dnf install -y nodejs git
cd /home/ec2-user
git clone https://github.com/angelverduzco/mc-stats-sync-script.git mc-stats-sync
cd /home/ec2-user/mc-stats-sync
npm install --omit=dev
```

The script uses these environment variables:

| Variable | Purpose |
| --- | --- |
| `MC_DIR` | Minecraft server directory containing `usercache.json` and `world/stats` |
| `S3_BUCKET` | Name of the destination S3 bucket |
| `AWS_REGION` | AWS region for the S3 bucket |

Set `MC_DIR` to the actual server directory. For example, if `usercache.json` is at `/home/ec2-user/minecraft/usercache.json`, use `/home/ec2-user/minecraft`. The script reads statistics from `<MC_DIR>/world/stats`.

Ensure the EC2 instance's IAM role allows `s3:PutObject` for `arn:aws:s3:::YOUR_BUCKET_NAME/stats.json`. The AWS SDK uses the instance role automatically; no credentials need to be added to the command.

### Use a `.env` file

You can keep these settings in a `.env` file in the project directory. Node.js 20.6.0 and later can load it with the `--env-file` option; for older versions, source the file in the shell before starting Node.js. Do not put AWS access keys in this file.

Create `/home/ec2-user/mc-stats-sync/.env` with your configuration:

```bash
MC_DIR="/home/ec2-user/minecraft"
S3_BUCKET="YOUR_BUCKET_NAME"
AWS_REGION="us-east-2"
```

With Node.js 20.6.0 or later, run the script manually with:

```bash
/usr/bin/node --env-file=/home/ec2-user/mc-stats-sync/.env /home/ec2-user/mc-stats-sync/index.js
```

For older Node.js versions, load the variables from the shell first:

```bash
cd /home/ec2-user/mc-stats-sync
set -a
. ./.env
set +a
/usr/bin/node ./index.js
```

## Run once manually

Alternatively, set the variables inline to verify the paths, bucket, and AWS permissions:

```bash
S3_BUCKET="YOUR_BUCKET_NAME" \
MC_DIR="/home/ec2-user/minecraft" \
AWS_REGION="us-east-2" \
/usr/bin/node /home/ec2-user/mc-stats-sync/index.js
```

Replace the example bucket, server directory, and region as needed. Find the Node.js executable path with `which node` and use that absolute path when configuring cron. On success, the script uploads or replaces `stats.json` at the root of the bucket. Errors are written to the command output and cause a non-zero exit.

## Run automatically with cron

To sync every 15 minutes, edit the `ec2-user` crontab:

```bash
crontab -e
```

Add a line like this, adjusting the bucket, server directory, region, Node.js path, and repository path to match your instance:

```cron
*/15 * * * * S3_BUCKET="YOUR_BUCKET_NAME" MC_DIR="/home/ec2-user/minecraft" AWS_REGION="us-east-2" /usr/bin/node /home/ec2-user/mc-stats-sync/index.js >> /home/ec2-user/mc-stats-sync/sync.log 2>&1
```

For Node.js 20.6.0 or later, use the built-in `--env-file` option:

```cron
*/15 * * * * /usr/bin/node --env-file=/home/ec2-user/mc-stats-sync/.env /home/ec2-user/mc-stats-sync/index.js >> /home/ec2-user/mc-stats-sync/sync.log 2>&1
```

Check the installed version with `/usr/bin/node --version`. For older Node.js versions, source the `.env` file in the cron command instead:

```cron
*/15 * * * * set -a; . /home/ec2-user/mc-stats-sync/.env && set +a && /usr/bin/node /home/ec2-user/mc-stats-sync/index.js >> /home/ec2-user/mc-stats-sync/sync.log 2>&1
```

Cron runs with a limited environment, so use absolute paths for Node.js, the script, the `.env` file, and the log file. On Amazon Linux 2023, the cron service is `crond`; if it is not already enabled, start it with:

```bash
sudo systemctl enable --now crond
```

The script runs once and exits; cron starts a new run at each scheduled interval. Check `sync.log` if a scheduled run fails.

## Update the script

After making and pushing changes to the repository, update the EC2 checkout:

```bash
cd /home/ec2-user/mc-stats-sync
git pull
npm install --omit=dev
```

The next cron run uses the updated code. No Minecraft server restart is required.
