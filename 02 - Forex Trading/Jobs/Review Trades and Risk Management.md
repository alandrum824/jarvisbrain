---
status: active
project: forex-trading
type: guide
---
# Review Trades and Risk Management

**The job:** Review and analyze the trades placed by the TWP ORB EA, and help manage risk on the account.

## Boot chain (read these, in order, and you have the skill)
1. This note, end to end.
2. [[Forex Trading]] — the platforms and EA this job covers (MetaTrader 5, TradingView, TWP ORB EA).
3. [[Active Priorities]] — whether risk management is flagged as an open item right now.
4. [[Forex Economic Calendar]] — free no-key feed for checking high-impact USD/EUR news around trade times.

## The procedure
1. Pull the recent trade history from MetaTrader 5 (and chart context from TradingView as needed).
2. Review what TWP ORB did: entries, exits, win/loss, and size relative to account balance.
3. Flag anything that looks like elevated risk — oversized positions, a losing streak, drawdown beyond what's normal for this EA.
4. Cross-reference trade timestamps against [[Forex Economic Calendar]] for Medium/High-impact USD or EUR events — flag any trade opened within ~15-30 min of one as a news-risk factor.
5. Summarize findings plainly: what happened, what's working, what's a risk concern.
6. Recommend concrete risk-management adjustments (position sizing, stop-loss placement, pausing the EA) rather than vague warnings.

## Quality bar
- Conclusions are backed by the actual trade data, not general forex commentary.
- Risk flags are specific and actionable, not hedged.
- Never recommend a change to live trading settings without Adam's explicit confirmation first.

## Lessons (fold corrections in here over time)
-

## Balance log
- 2026-09-27: ~$200 (Adam's figure).
- 2026-09-29 ~2:55 AM PT: **$168** (Adam, MT5) after the manual GBPUSD long stopped out (0.13 lots, entry 1.32571, SL 1.32160; bought at the top of supply at ~25% account risk). Sizing rule going forward: risk 2–3% per trade (~$3.40–$5 at $168). On GBPUSD 0.01 lot ≈ $0.10/pip, so a 30–40 pip stop = 0.01 lot; 0.02 only with a stop under 25 pips.

## 45-day journal from the live account (2026-09-29, via [[MT5 Read-Only Link]])
- **163 closed trades, 53% win rate, net −$785.63.** Deposits since Aug 2: 247.35 + 299.82 + 333.97 + 309.72 + 113.54 = **$1,304.40**; balance now **$168.98**.
- **The leak is loss size, not win rate:** average win **+$8.04** vs average loss **−$21.22** (2.6×). Biggest loss −$170.50, biggest win +$32.70.
- **Size drives it:** trades at **≥0.30 lots: 61 trades, −$682.27 (≈87% of the net loss)**; 0.10–0.29: −$44.51; 0.01–0.09: −$58.85.
- **By symbol:** GBPUSD −$511.38 (10 trades, 30% win); EURUSD −$156.81 (91 trades, 57% win); gold −$48.16; GBPAUD −$41.54 (0/5).
- **Pattern:** adding to losers. On 9/21, four EURUSD buys at 0.4–0.5 lots, averaged down 1.1482 → 1.1473, all closed at 1.14535: −$433.72 in one sequence. Last week (W39): 24 trades, 25% win, −$465.
- **Rules that follow from the data:** 0.01 lot per 30–40 pip stop (2–3% risk), a hard stop on every trade, no adding to a losing position, and a `risk` check before every entry.

- **2026-09-30 ~12:30 AM PT: balance $306.05** (from $237.26: gold +$36.46 and +$5.09, USDCAD +$27.24 at 0.32 lots). A winning streak on small gold size. The USDCAD size was over the journal's danger line.
