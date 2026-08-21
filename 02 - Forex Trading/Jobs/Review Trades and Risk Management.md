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
