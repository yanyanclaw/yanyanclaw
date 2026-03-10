---
name: stock-news
description: Show latest news for tracked stocks (0050, 2330, 2327 國巨, 2406 國碩)
user-invokable: true
---

# Stock News

When the user asks about stock news, 新聞, 最新消息, or mentions specific stocks like 台積電新聞, 0050新聞, 國巨新聞, 國碩新聞:

1. Reply to the user with: "查詢中，請稍候..."
2. Then silently execute the command using exec tool (do NOT show the command in your reply)

All stocks:
```
python3 /root/stock-news.py
```

Specific stock:
```
python3 /root/stock-news.py 2330
```

Symbols: 0050, 2330, 2327（國巨）, 2406（國碩）

IMPORTANT: Do NOT show the shell command in your reply. Do NOT use browser. Just say "查詢中，請稍候..." and execute.
