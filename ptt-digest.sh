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
    '請分析以下每篇 PTT [標的]文章，逐篇輸出分析報告。',
    '',
    '輸出規則：',
    '- 每篇用 ━━━ 分隔',
    '- 期間從文章內容推斷：短線=1~5日、波段=1~4週、長線=1~3月以上',
    '- 進場/停損/停利：從文章「進退場機制」欄位提取，若未明確寫出則填「作者未說明」',
    '- 評價標準：★★★=有明確進退場點+實質分析、★★=分析方向清楚但細節不足、★=模糊或純情緒',
    '- 不要輸出任何說明、前言或格式說明，直接輸出分析內容',
    '',
    '輸出範例（照此格式，替換為真實內容）：',
    '━━━━━━━━━━━━━━━━',
    '2330 台積電 · 多▲ · 波段',
    '機會：月線支撐有效，外資回補跡象明顯',
    '風險：美科技股若再修正恐帶動台積電下跌',
    '進場：1050元附近分批買入',
    '停損：月線1020元跌破出場',
    '停利：目標1120元，分批減碼',
    '新聞：外資回流台積電，法人看好下季EPS',
    '評價：★★★　理由：有具體點位與技術依據',
    '🔗 https://www.pttweb.cc/bbs/Stock/M.xxxxxxx',
    '━━━━━━━━━━━━━━━━',
    '',
    '全部文章分析完後，另起一行輸出：',
    '【今日市場觀察】（2句：整體方向 + 最值得關注的標的）',
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
ANALYSIS=$(openclaw agent --agent main --message "$PROMPT" --timeout 180000 2>&1)

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
