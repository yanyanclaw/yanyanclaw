#!/bin/bash
# 推送 stock_report.md 到 openclaw 遠端並發 Telegram
set -e

REPORT="/Users/yan/Documents/workspace/openclaw/stock/stock_data/stock_report.md"
SSH_KEY="$HOME/.ssh/id_ed25519_openclaw"
REMOTE="root@64.23.243.221"
REMOTE_PATH="/root/openclaw-repo/stock/stock_data/stock_report.md"
BOT_TOKEN="${OPENCLAW_BOT_TOKEN:?Set OPENCLAW_BOT_TOKEN in ~/.zshrc}"
CHAT_ID="${OPENCLAW_CHAT_ID:-707551310}"

REPORT_DIR="$(dirname "$REPORT")"
REPO_ROOT="/Users/yan/Documents/workspace/openclaw"

if [ ! -f "$REPORT" ]; then
  echo "❌ $REPORT not found"
  exit 1
fi

# 0. Archive previous report as history
PREV_DATE=$(date -v-1d +%Y%m%d 2>/dev/null || date -d "yesterday" +%Y%m%d)
HISTORY_FILE="${REPORT_DIR}/stock_report_${PREV_DATE}.md"
if [ ! -f "$HISTORY_FILE" ]; then
  cp "$REPORT" "$HISTORY_FILE"
  cd "$REPO_ROOT"
  git add "$HISTORY_FILE"
  git commit -m "archive: stock report ${PREV_DATE}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
  echo "📁 Archived as stock_report_${PREV_DATE}.md"
fi

# 1. SCP to remote
echo "📤 Uploading report..."
scp -i "$SSH_KEY" "$REPORT" "$REMOTE:$REMOTE_PATH"

# 2. Send via Telegram Bot API (split if > 4096 chars)
echo "📨 Sending to Telegram..."
CONTENT=$(cat "$REPORT")
LEN=${#CONTENT}

if [ "$LEN" -le 4096 ]; then
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$CONTENT" \
    -d parse_mode="HTML" > /dev/null
else
  # Split into chunks
  echo "$CONTENT" | fold -w 4000 -s | while IFS= read -r chunk; do
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="$CHAT_ID" \
      -d text="$chunk" \
      -d parse_mode="HTML" > /dev/null
    sleep 1
  done
fi

echo "✅ Done"
