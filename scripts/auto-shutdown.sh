#!/bin/bash
# Stops the Minecraft server and powers off the EC2 instance when nobody is connected.
# Meant to run from root's crontab every CHECK_INTERVAL_MIN minutes:
#   */10 * * * * /usr/local/bin/mc-auto-shutdown.sh
# Idle time before shutdown = MAX_CHECKS x cron interval (3 x 10 min = 30 minutes).
# To test quickly, set MAX_CHECKS=2 and CHECK_INTERVAL_MIN=1, and run the job every minute.

# Cron has a minimal environment, so define PATH explicitly
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set -u

PORT=25565
SERVICE_NAME="minecraft.service"
COUNTER_FILE="/tmp/mc_idle_count"   # lives in /tmp, so it resets on reboot
MAX_CHECKS=3                        # consecutive idle checks before shutting down
CHECK_INTERVAL_MIN=10               # must match the cron interval (used for logging only)

if [ "$(id -u)" -ne 0 ]; then echo "Run as root (sudo or root's crontab)"; exit 1; fi

# Count established TCP connections on the Minecraft server port
ACTIVE_PLAYERS=$(ss -Htn state established "( sport = :$PORT )" | wc -l)

if [ "$ACTIVE_PLAYERS" -eq 0 ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"

  if [ "$COUNT" -ge "$MAX_CHECKS" ]; then
    rm -f "$COUNTER_FILE"
    logger "Minecraft Auto-Shutdown: No players for $((MAX_CHECKS * CHECK_INTERVAL_MIN)) minutes. Stopping server and EC2 instance."
    # Graceful stop first so the world is saved before powering off
    systemctl stop "$SERVICE_NAME"
    shutdown -h now
  fi
else
  # Reset the counter if at least one player is connected
  echo 0 > "$COUNTER_FILE"
fi
