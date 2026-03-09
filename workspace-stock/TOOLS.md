# 工具說明 - 股票管理人

## 資料位置

- 持股清單：/root/.openclaw/stock_data/holdings.json
- 每日價格：/root/.openclaw/stock_data/prices/YYYY-MM-DD.json
- 每日新聞：/root/.openclaw/stock_data/news/YYYY-MM-DD.json

## 查看持股

exec: cat /root/.openclaw/stock_data/holdings.json

## 新增持股

先讀現有持股，再重寫 JSON（加入新代號）：

exec: cat /root/.openclaw/stock_data/holdings.json

然後用 heredoc 寫回：

exec:
cat > /root/.openclaw/stock_data/holdings.json << 'JSONEOF'
{stocks: [既有代號, 新代號]}
JSONEOF

## 移除持股

同上，讀取後重寫，去掉指定代號。

## 更新股價和新聞（手動觸發）

exec: python3 /root/stock-update.py

## 查看今天股價

exec: cat /root/.openclaw/stock_data/prices/今天日期.json

## 查看今天新聞

exec: cat /root/.openclaw/stock_data/news/今天日期.json

## 股票代號規則

- 台股：輸入數字（如 2330、00878），腳本自動加 .TW
- 美股：輸入英文（如 AAPL、NVDA）
