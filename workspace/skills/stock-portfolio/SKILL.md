---
name: stock-portfolio
description: 查詢持股損益、股價、投資組合狀態
user-invokable: true
---

# Stock Portfolio

當用戶說：查持股、持股狀況、股票現在多少、損益、看股票、股價、show holdings、stock price、portfolio 等查詢類指令：

1. 先回覆「查詢中，請稍候...」

2. 用 exec 執行：
```
python3 /root/show-portfolio.py
```

3. 將 exec 的輸出**完整原樣**回覆給用戶，不要修改、不要重新排版。

IMPORTANT: 不要顯示 exec 指令。不要問用戶新增或移除股票。不要自己編造股價資料。
