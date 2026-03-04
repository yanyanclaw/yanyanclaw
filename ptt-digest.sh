#!/bin/bash
# PTT Stock [標的] daily digest
# Runs at 08:30 Taiwan time (00:30 UTC)
# Fetches threads (main + replies), Google News, then AI analysis via OpenClaw.

STATE_FILE="/root/.ptt-seen-aids"
BOT_TOKEN="8723576581:AAFAT6Oxr4oLZxL6ievMgK77fURnFLXT2j0"
CHAT_ID="707551310"
RAW_JSON_FILE="/tmp/ptt-raw.json"

touch "$STATE_FILE"

echo "[ptt-digest] Fetching PTT Stock [標的] threads..."
python3 /root/ptt-fetch.py > "$RAW_JSON_FILE" 2>/tmp/ptt-fetch.stderr

if [ ! -s "$RAW_JSON_FILE" ] || [ "$(cat "$RAW_JSON_FILE")" = "[]" ]; then
    echo "[ptt-digest] No threads fetched."
    cat /tmp/ptt-fetch.stderr
    exit 0
fi

# Count new threads (AIDs not yet in state file)
NEW_COUNT=$(python3 -c "
import json
with open('$RAW_JSON_FILE') as f:
    data = json.load(f)
with open('$STATE_FILE') as f:
    seen = set(l.strip() for l in f if l.strip())
print(sum(1 for t in data if t['main_aid'] not in seen))
")

if [ "$NEW_COUNT" = "0" ]; then
    echo "[ptt-digest] No new [標的] threads today."
    exit 0
fi

echo "[ptt-digest] $NEW_COUNT new thread(s). Building AI prompt..."

PROMPT=$(python3 -c "
import json
with open('$RAW_JSON_FILE') as f:
    raw = json.load(f)
with open('$STATE_FILE') as f:
    seen = set(l.strip() for l in f if l.strip())

data = [t for t in raw if t['main_aid'] not in seen]

lines = [
    '你是資深台股/美股投資人，熟悉 PTT 股票板文化。',
    '',
    '【PTT [標的]文章格式說明】',
    '標的：股票代號或期貨名稱',
    '分類：多 / 空 / 當沖 / 存股 等',
    '分析/正文：作者的技術面、基本面、籌碼面分析',
    '進退場機制：停損/停利點位',
    '',
    '【評分標準】',
    '★★★ 值得參考：有明確股票代號、具體進退場點位、有實質分析（技術/基本/籌碼面）',
    '★★  普通：有分析方向但細節不足，或缺少明確停損點',
    '★   無參考價值：過於模糊、純情緒喊多空、無任何分析依據',
    '',
    '【每篇輸出格式】（直接輸出，不要加前言或說明）',
    '━━━━━━━━━━━━━━━━',
    '標的名稱 · 方向（多▲ / 空▼ / 觀望◆）',
    '機會：（1句，具體說明）',
    '風險：（1句，具體說明）',
    '新聞：（摘要1句，若無相關填「無」）',
    '評價：★★★ / ★★ / ★　理由：（10字內）',
    '🔗 連結',
    '━━━━━━━━━━━━━━━━',
    '',
    '全部分析完後輸出：',
    '【今日市場觀察】（2句，整體方向與今日重點標的）',
    '',
    '=== 待分析文章 ===',
    '',
]

for i, t in enumerate(data, 1):
    lines.append(f\"【文章 {i}】回文數：{t['reply_count']}\")
    lines.append(f\"標題：{t['base_title']}\")
    lines.append(f\"連結：{t['main_url']}\")
    lines.append('')
    lines.append('主文：')
    lines.append(t['main_content'] if t['main_content'] else '（無法取得）')
    if t['replies']:
        lines.append('')
        for j, r in enumerate(t['replies'], 1):
            lines.append(f\"回文{j}：\")
            lines.append(r['content'] if r['content'] else '（無內容）')
    if t['news']:
        lines.append('')
        lines.append('相關新聞：')
        for n in t['news'][:3]:
            lines.append(f\"  ・{n['title']}\")
    lines.append('')
    lines.append('---')

print('\n'.join(lines))
")

echo "[ptt-digest] Running AI analysis (timeout 3 min)..."
ANALYSIS=$(openclaw agent --message "$PROMPT" --timeout 180000 2>&1)

# Fallback if AI returned nothing
if [ -z "$ANALYSIS" ]; then
    echo "[ptt-digest] AI returned empty, using fallback format..."
    ANALYSIS=$(python3 -c "
import json
with open('$RAW_JSON_FILE') as f:
    raw = json.load(f)
with open('$STATE_FILE') as f:
    seen = set(l.strip() for l in f if l.strip())
data = [t for t in raw if t['main_aid'] not in seen]
lines = ['📈 PTT Stock 今日標的（AI 分析失敗，原始列表）', '']
for t in data:
    lines.append(f\"• [{t['ticker']}] {t['base_title']}\")
    lines.append(f\"  🔗 {t['main_url']}\")
    if t['news']:
        lines.append(f\"  📰 {t['news'][0]['title']}\")
    lines.append('')
print('\n'.join(lines))
")
fi

# Send to Telegram (split at 4000 chars if needed)
send_msg() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        --data-urlencode "text=$1" \
        -d disable_web_page_preview=true \
        > /dev/null
}

MSG_LEN=${#ANALYSIS}
if [ "$MSG_LEN" -le 4096 ]; then
    send_msg "$ANALYSIS"
else
    send_msg "${ANALYSIS:0:4000}
⬇️ (續下一則)"
    send_msg "⬆️ (續)
${ANALYSIS:4000:4000}"
fi

# Mark all new AIDs as seen
python3 -c "
import json
with open('$RAW_JSON_FILE') as f:
    raw = json.load(f)
with open('$STATE_FILE') as f:
    seen = set(l.strip() for l in f if l.strip())
new_aids = [t['main_aid'] for t in raw if t['main_aid'] not in seen]
with open('$STATE_FILE', 'a') as f:
    for aid in new_aids:
        f.write(aid + '\n')
print(f'Marked {len(new_aids)} AID(s) as seen.')
"

tail -500 "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

echo "[ptt-digest] Done."
