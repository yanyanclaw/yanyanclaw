---
name: stock-portfolio
description: 查詢持股損益、股價、投資組合狀態
user-invocable: true
---

# Stock Portfolio

當用戶說：查持股、持股狀況、股票現在多少、損益、看股票、股價、show holdings、stock price、portfolio 等查詢類指令：

1. 先回覆「查詢中，請稍候...」

2. 用 exec 執行：
```
cat /root/openclaw-repo/stock/stock_data/stock_data.json
```

3. 讀取 JSON 後，按以下格式排版回覆：

```
📊 持股報告  {updated_at}
市場：加權 {taiex.current} ({taiex.change_pct}%) ｜ 櫃買 {otc.current} ({otc.change_pct}%)

🇹🇼 台股
{每支股票一行：代號 名稱 | 現價 (日漲跌%) | 損益 損益% | 市值}

🇺🇸 美股
{每支股票一行：代號 名稱 | 現價 (日漲跌%) | 損益 損益% | 市值}

💰 總覽
總成本：{summary.total_cost_twd} | 總市值：{summary.total_value_twd}
台幣現金：{summary.cash_tw} | 美元現金(折台幣)：{summary.cash_us_twd}
總資產：{summary.total_assets_twd} | 股票損益：{summary.stock_pnl_twd} ({summary.stock_pnl_pct}%)
```

排版規則：
- 金額用千分位（例：1,234,567）
- 漲用 ▲ 綠色描述，跌用 ▼ 紅色描述
- 美股損益同時顯示 USD 原始值
- 如果 alerts 陣列不為空，在最後加上「⚠️ 警示」區塊

IMPORTANT: 不要顯示 exec 指令。不要問用戶新增或移除股票。
