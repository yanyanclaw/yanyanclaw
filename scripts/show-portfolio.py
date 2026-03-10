#!/usr/bin/env python3
"""
Read stock_data.json and output a formatted portfolio report.
Designed for openclaw exec: agent just calls this script,
output is the complete formatted report ready to send to user.
"""

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
DATA_FILE = os.path.join(SCRIPT_DIR, "..", "stock", "stock_data", "stock_data.json")


def fmt_num(n, decimals=0):
    """Format number with thousands separator."""
    if n is None:
        return "N/A"
    if decimals == 0:
        return f"{int(n):,}"
    return f"{n:,.{decimals}f}"


def arrow(pct):
    return "▲" if pct >= 0 else "▼"


def main():
    if not os.path.exists(DATA_FILE):
        print("❌ stock_data.json not found")
        sys.exit(1)

    with open(DATA_FILE) as f:
        d = json.load(f)

    lines = []
    lines.append(f"📊 持股報告  {d['updated_at']}")
    lines.append(f"狀態：{d.get('market_status', '')}")

    taiex = d.get("taiex", {})
    otc = d.get("otc", {})
    lines.append(
        f"加權 {fmt_num(taiex.get('current'), 2)} "
        f"({arrow(taiex.get('change_pct', 0))}{taiex.get('change_pct', 0)}%) "
        f"｜ 櫃買 {fmt_num(otc.get('current'), 2)} "
        f"({arrow(otc.get('change_pct', 0))}{otc.get('change_pct', 0)}%)"
    )
    lines.append("")

    # TW stocks
    lines.append("🇹🇼 台股")
    for s in d.get("tw_stocks", []):
        a = arrow(s["daily_chg_pct"])
        lines.append(
            f"  {s['code']} {s['name']} | "
            f"{fmt_num(s['current_price'], 2)} ({a}{s['daily_chg_pct']}%) | "
            f"損益 {fmt_num(s['pnl'])} ({s['pnl_pct']}%) | "
            f"市值 {fmt_num(s['value'])}"
        )
    lines.append("")

    # US stocks
    lines.append("🇺🇸 美股")
    for s in d.get("us_stocks", []):
        a = arrow(s["daily_chg_pct"])
        lines.append(
            f"  {s['code']} {s['name']} | "
            f"${fmt_num(s['current_price'], 2)} ({a}{s['daily_chg_pct']}%) | "
            f"損益 ${fmt_num(s.get('pnl_usd', 0))} ({s['pnl_pct']}%) | "
            f"市值 ${fmt_num(s.get('value_usd', 0))}"
        )
    lines.append("")

    # Summary
    sm = d.get("summary", {})
    lines.append("💰 總覽")
    lines.append(f"  總成本：{fmt_num(sm.get('total_cost_twd'))} TWD")
    lines.append(f"  總市值：{fmt_num(sm.get('total_value_twd'))} TWD")
    lines.append(
        f"  台幣現金：{fmt_num(sm.get('cash_tw'))} | "
        f"美元現金(折台幣)：{fmt_num(sm.get('cash_us_twd'))}"
    )
    lines.append(
        f"  總資產：{fmt_num(sm.get('total_assets_twd'))} TWD | "
        f"股票損益：{fmt_num(sm.get('stock_pnl_twd'))} ({sm.get('stock_pnl_pct', 0)}%)"
    )

    # Alerts
    alerts = d.get("alerts", [])
    if alerts:
        lines.append("")
        lines.append("⚠️ 警示")
        for a in alerts:
            lines.append(f"  {a}")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
