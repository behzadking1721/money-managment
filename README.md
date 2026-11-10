# Money Manager Expert Advisor

A comprehensive MetaTrader 5 (MQL5) Expert Advisor for money management, risk control, position/order management, prop-firm compliance, news/session filters, alerts, statistics and a customizable UI panel.

## Structure
```
MoneyManager.mq5          main EA
Include/
  Utils/Common.mqh        enums, structs, helpers
  Core/                   LotSizing, StopLoss, TakeProfit, OrderManager, PositionManager
  Protection/             Protection (daily limits, drawdown, cooldown, ...)
  PropFirm/               Prop firm rules & presets
  News/                   News manager (FF + local fallback)
  Session/                Session detection, DST, colors
  Profiles/               Profile presets + import/export .set
  Alerts/                 Sound/push/email/popup alerts
  Statistics/             Trade logger CSV + metrics
  UI/                     Panel (mini bar)
```

## Features
See task spec: lot sizing (5 methods + ATR + DD scaling), SL (5), TP/Multi-TP (3), magic filter, slippage/requote, partial fills, retries, commission, auto account currency, symbol suffix, hedge/netting detection, min/max risk.

Order management: market/limit/stop/OCO, expiry, scale in/out, pending manager, confirmation.

Position management: break even (3), trailing (fixed/ATR/candle), partial close (3), multi-TP, time-based exit, hedging control.

Protection: daily loss/profit, profit lock, weekly/monthly, max DD, lot reduction after loss, DD recovery, weekend auto-close, swap warning, virtual SL/TP, max trades/day, cooldown, consecutive loss.

Prop firm: presets + custom, challenge/funded, DD from equity/balance, min trading days, consistency, max position size %, correlation warning, news blackout.

News & session: FF calendar + local fallback, news bar, custom events, spread warning, session display + colors, session overlay, auto DST, panel color by session.

Profile system: presets (conservative/moderate/aggressive), save custom, import/export .set.

Alerts: sound/push/email/popup, per-event, connection status.

UI: mini bar (session color, spread live, server time, account badge, connection, +/- risk & TP, toggle %/amount, drag on/off), drawer (6 tabs), quick action bar (X all/profit/loss, BE all, partial, RR), appearance settings (font, size, opacity, position, dark/light/auto, draggable + save pos, hide/show hotkey H, hotkey help).

Statistics & log: trade logger CSV, daily snapshot, win rate/RR/PF, Sharpe/recovery, max consec loss/win, avg duration, last trade info, export CSV.

## Usage
Attach to a chart. Configure inputs. Hotkey H toggles panel visibility.

## Build
Compile MoneyManager.mq5 with MetaEditor (MQL5). Zero errors/warnings.
