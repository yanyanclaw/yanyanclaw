#!/bin/bash

# Scan for new articles
blogwatcher scan > /dev/null 2>&1

# Get unread articles
ARTICLES=$(blogwatcher articles 2>&1)

# Check if there are any unread articles
if echo "$ARTICLES" | grep -q "No unread"; then
    echo "No unread articles."
    exit 0
fi

# Check count
UNREAD_COUNT=$(echo "$ARTICLES" | grep "Unread articles" | grep -o '[0-9]*' | head -1)
if [ -z "$UNREAD_COUNT" ] || [ "$UNREAD_COUNT" = "0" ]; then
    echo "No unread articles."
    exit 0
fi

echo "Found $UNREAD_COUNT unread articles, sending digest..."

BOT_TOKEN="8723576581:AAFAT6Oxr4oLZxL6ievMgK77fURnFLXT2j0"
CHAT_ID="707551310"

PROMPT="以下是今日新聞列表，請用繁體中文彙整，每則格式如下：

• 標題 — 一句話摘要
  🔗 URL

$ARTICLES

注意：URL 必須來自原始資料，不可省略，單獨放在第二行。只輸出彙整結果，不需要說明。"

# 讓 AI 生成摘要（不 deliver，只取輸出）
SUMMARY=$(openclaw agent --agent main --message "$PROMPT" --timeout 120000 2>&1)

# 透過 Telegram Bot API 傳送，關閉連結預覽
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="${SUMMARY}" \
  -d disable_web_page_preview=true \
  > /dev/null

echo "y" | blogwatcher read-all
echo "Done."
