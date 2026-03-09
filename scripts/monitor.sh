#!/bin/bash
# OpenClaw machine monitor
# Usage:
#   monitor.sh          — print status to stdout
#   monitor.sh --report — also send to Telegram

BOT_TOKEN="8723576581:AAFAT6Oxr4oLZxL6ievMgK77fURnFLXT2j0"
CHAT_ID="707551310"
BASELINE_FILE="/root/.net-baseline"
INTERFACE="eth0"

# ── helpers ─────────────────────────────────────────────────────────────────

bytes_to_human() {
    local b=$1
    if   [ "$b" -ge 1073741824 ]; then printf "%.1f GB" "$(echo "scale=1; $b/1073741824" | bc)"
    elif [ "$b" -ge 1048576    ]; then printf "%.1f MB" "$(echo "scale=1; $b/1048576" | bc)"
    elif [ "$b" -ge 1024       ]; then printf "%.1f KB" "$(echo "scale=1; $b/1024" | bc)"
    else printf "%d B" "$b"
    fi
}

net_bytes() {
    # Returns "rx tx" bytes for $INTERFACE from /proc/net/dev
    awk -v iface="${INTERFACE}:" '$1==iface {print $2, $10}' /proc/net/dev
}

today() { date '+%Y-%m-%d'; }

# ── network traffic ──────────────────────────────────────────────────────────

read CUR_RX CUR_TX <<< "$(net_bytes)"
BASELINE_DATE=$([ -f "$BASELINE_FILE" ] && awk 'NR==1{print $1}' "$BASELINE_FILE" || echo "")
BASELINE_RX=$([ -f "$BASELINE_FILE" ]   && awk 'NR==1{print $2}' "$BASELINE_FILE" || echo "0")
BASELINE_TX=$([ -f "$BASELINE_FILE" ]   && awk 'NR==1{print $3}' "$BASELINE_FILE" || echo "0")

# Reset baseline at start of each day
if [ "$BASELINE_DATE" != "$(today)" ]; then
    echo "$(today) $CUR_RX $CUR_TX" > "$BASELINE_FILE"
    BASELINE_RX=$CUR_RX
    BASELINE_TX=$CUR_TX
fi

TODAY_RX=$(( CUR_RX - BASELINE_RX ))
TODAY_TX=$(( CUR_TX - BASELINE_TX ))
TOTAL_RX=$(bytes_to_human "$TODAY_RX")
TOTAL_TX=$(bytes_to_human "$TODAY_TX")

# ── system health ────────────────────────────────────────────────────────────

LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
UPTIME=$(uptime -p)

read MEM_TOTAL MEM_AVAIL <<< "$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print t, a}' /proc/meminfo)"
MEM_USED=$(( (MEM_TOTAL - MEM_AVAIL) / 1024 ))
MEM_TOTAL_MB=$(( MEM_TOTAL / 1024 ))
MEM_PCT=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))

DISK=$(df -h / | awk 'NR==2{print $3"/"$2, "("$5")"}')

# ── openclaw gateway ─────────────────────────────────────────────────────────

GW_PID=$(pgrep -f openclaw-gateway | head -1)
if [ -n "$GW_PID" ]; then
    GW_MEM=$(ps -p "$GW_PID" -o rss= 2>/dev/null | awk '{printf "%.0f MB", $1/1024}')
    GW_UPTIME=$(ps -p "$GW_PID" -o etime= 2>/dev/null | tr -d ' ')
    GW_STATUS="✅ running (PID $GW_PID, RAM ${GW_MEM}, up ${GW_UPTIME})"
else
    GW_STATUS="❌ NOT running"
fi

# ── ollama connection ─────────────────────────────────────────────────────────

OLLAMA_RESP=$(curl -s --max-time 5 http://127.0.0.1:11434/api/tags 2>/dev/null)
if [ -n "$OLLAMA_RESP" ]; then
    MODEL_COUNT=$(echo "$OLLAMA_RESP" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['models']))" 2>/dev/null || echo "?")
    MODELS=$(echo "$OLLAMA_RESP" | python3 -c "import json,sys; print(', '.join(m['name'] for m in json.load(sys.stdin)['models']))" 2>/dev/null || echo "?")
    OLLAMA_STATUS="✅ connected ($MODEL_COUNT models)"

    # Quick inference test — send a tiny prompt, check for response
    TEST=$(curl -s --max-time 30 http://127.0.0.1:11434/api/generate \
        -d '{"model":"qwen2.5:14b","prompt":"reply ok","stream":false}' \
        2>/dev/null | python3 -c "import json,sys; print('ok' if json.load(sys.stdin).get('response') else 'empty')" 2>/dev/null || echo "timeout")
    if [ "$TEST" = "ok" ]; then
        OLLAMA_STATUS="✅ connected + inference ok ($MODEL_COUNT models)"
    else
        OLLAMA_STATUS="⚠️  connected but inference $TEST ($MODEL_COUNT models)"
    fi
else
    OLLAMA_STATUS="❌ unreachable (tunnel down?)"
    MODELS="—"
fi

# ── cron jobs ─────────────────────────────────────────────────────────────────

CRON_JOBS=$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | wc -l)
CRON_LIST=$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | sed 's|/root/||g')

# ── recent log tails ──────────────────────────────────────────────────────────

NEWS_LOG=$(tail -3 /tmp/news-digest.log 2>/dev/null | tr '\n' ' ' | cut -c1-80)
PTT_LOG=$(tail -3 /tmp/ptt-digest.log 2>/dev/null | tr '\n' ' ' | cut -c1-80)

# ── compose report ───────────────────────────────────────────────────────────

DATE_STR=$(date '+%Y-%m-%d %H:%M')

REPORT="🖥️ OpenClaw 狀態報告  $DATE_STR

📡 今日網路 ($INTERFACE)
  ↓ 下行：$TOTAL_RX
  ↑ 上行：$TOTAL_TX

💻 系統
  負載：$LOAD  ($UPTIME)
  記憶體：${MEM_USED}MB / ${MEM_TOTAL_MB}MB ($MEM_PCT%)
  磁碟 /：$DISK

🤖 OpenClaw Gateway
  $GW_STATUS

🧠 Ollama (11434)
  $OLLAMA_STATUS
  模型：$MODELS

⏰ Cron 任務 ($CRON_JOBS 個)
$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | awk '{printf "  %s\n", $0}')

📋 最近 news-digest：$NEWS_LOG
📋 最近 ptt-digest：$PTT_LOG"

echo "$REPORT"

# Send to Telegram if --report flag passed
if [ "${1}" = "--report" ]; then
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode "text=${REPORT}" \
        -d disable_web_page_preview=true \
        > /dev/null
    echo "Sent to Telegram."
fi
