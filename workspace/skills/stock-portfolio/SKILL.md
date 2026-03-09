---
name: stock-portfolio
description: 查詢即時股價、持股損益、油價警示
user-invocable: true
---

# Stock Portfolio

當用戶說：查持股、持股狀況、股票現在多少、損益、看股票、股價、show holdings、stock price、portfolio 等查詢類指令：

1. 先回覆「查詢中，請稍候...」

2. 用 exec 執行：
```
cat /tmp/stock_status.txt
```

3. exec 輸出中，找到包含 📊 的那一行。**從這一行開始**，把後面的所有文字（包含這一行）完整回覆給用戶。

4. **📊 之前的所有內容（包括 [object Object]）一律丟棄，不要輸出。**

範例：exec 若回傳「[object Object][object Object]📊 2026-03-09...元大台灣50正2...」，你只回覆「📊 2026-03-09...元大台灣50正2...」這部分。

IMPORTANT: 不要顯示指令。不要問用戶新增或移除股票。
