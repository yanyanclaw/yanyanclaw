#!/bin/bash

STATE_FILE="/root/.ptt-seen-aids"
BOT_TOKEN="8723576581:AAFAT6Oxr4oLZxL6ievMgK77fURnFLXT2j0"
CHAT_ID="707551310"

# Create state file if not exists
touch "$STATE_FILE"

# Fetch PTT Stock page and extract [標的] articles
RAW=$(curl -s "https://www.pttweb.cc/bbs/Stock/page" | python3 -c "
import sys, re

html = sys.stdin.read()
pattern = r'articleAid:\"(M\.[0-9A-Z.]+)\"[^}]*?title:\"([^\"]*\[標的\][^\"]*)\"|title:\"([^\"]*\[標的\][^\"]*)\"[^}]*?articleAid:\"(M\.[0-9A-Z.]+)\"'
matches = re.findall(pattern, html)
for m in matches:
    aid = m[0] or m[3]
    title = m[1] or m[2]
    print(aid + '|' + title)
" 2>/dev/null)

if [ -z "$RAW" ]; then
    echo "No [標的] posts found."
    exit 0
fi

# Filter out already-seen articles
NEW_AIDS=()
NEW_LINES=""
while IFS='|' read -r aid title; do
    [ -z "$aid" ] && continue
    if ! grep -qF "$aid" "$STATE_FILE"; then
        NEW_AIDS+=("$aid")
        NEW_LINES="${NEW_LINES}${aid}|${title}\n"
    fi
done <<< "$RAW"

if [ ${#NEW_AIDS[@]} -eq 0 ]; then
    echo "No new [標的] posts."
    exit 0
fi

echo "Found ${#NEW_AIDS[@]} new [標的] posts, sending..."

# Build message
MESSAGE="📈 PTT Stock 標的文

"
while IFS='|' read -r aid title; do
    [ -z "$aid" ] && continue
    url="https://www.pttweb.cc/bbs/Stock/${aid}"
    MESSAGE="${MESSAGE}• ${title}
  🔗 ${url}

"
done <<< "$(printf '%b' "$NEW_LINES")"

# Send to Telegram
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  --data-urlencode "text=${MESSAGE}" \
  -d disable_web_page_preview=true \
  > /dev/null

# Mark as seen
for aid in "${NEW_AIDS[@]}"; do
    echo "$aid" >> "$STATE_FILE"
done

# Keep only last 500 entries
tail -500 "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

echo "Done."
