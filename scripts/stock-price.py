#!/usr/bin/env python3
"""
Stock price fetcher for openclaw agent.
Usage: python3 stock-price.py 2330 AAPL 00878
"""

import sys
import json
from datetime import datetime

def get_price(ticker: str) -> dict:
    try:
        import yfinance as yf
    except ImportError:
        return {"error": "請先安裝 yfinance: pip install yfinance"}

    # 台股：純數字 → 加 .TW；ETF 常見格式如 00878 也適用
    symbol = ticker.strip().upper()
    if symbol.isdigit() or (len(symbol) == 5 and symbol[:4].isdigit()):
        symbol = symbol + ".TW"

    try:
        t = yf.Ticker(symbol)
        info = t.fast_info
        price = info.last_price
        prev_close = info.previous_close

        if price is None:
            return {"ticker": ticker, "error": f"找不到 {symbol} 的資料"}

        change = price - prev_close
        change_pct = (change / prev_close) * 100

        return {
            "ticker": ticker,
            "symbol": symbol,
            "price": round(price, 2),
            "change": round(change, 2),
            "change_pct": round(change_pct, 2),
            "prev_close": round(prev_close, 2),
            "time": datetime.now().strftime("%Y-%m-%d %H:%M"),
        }
    except Exception as e:
        return {"ticker": ticker, "symbol": symbol, "error": str(e)}


def format_result(r: dict) -> str:
    if "error" in r:
        return f"❌ {r['ticker']}: {r['error']}"
    sign = "+" if r["change"] >= 0 else ""
    arrow = "▲" if r["change"] >= 0 else "▼"
    return (
        f"{arrow} {r['ticker']} ({r['symbol']})\n"
        f"  現價：{r['price']}　{sign}{r['change']} ({sign}{r['change_pct']}%)\n"
        f"  昨收：{r['prev_close']}　更新：{r['time']}"
    )


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法：python3 stock-price.py 2330 AAPL 00878")
        sys.exit(1)

    tickers = sys.argv[1:]
    results = [get_price(t) for t in tickers]

    for r in results:
        print(format_result(r))
