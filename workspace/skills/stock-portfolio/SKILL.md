---
name: stock-portfolio
description: 查詢持股損益、股價、投資組合狀態
user-invocable: true
---

# Stock Portfolio

當用戶說：查持股、持股狀況、股票現在多少、損益、看股票、股價、show holdings、stock price、portfolio 等查詢類指令：

1. 用 read_file 讀取 `/root/openclaw-repo/stock/stock_data/stock_report.md`
2. 將檔案內容**完整原樣**回覆給用戶，不要修改、不要重新排版、不要摘要。

IMPORTANT: 不要自己編造股價資料。不要問用戶新增或移除股票。
