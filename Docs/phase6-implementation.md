# Phase 6 (Stats, Profiles, Alerts, CSV) â€” Implementation Notes

## Delivered
- **`Include/Statistics/Statistics.mqh`**: `CStatistics` implements `ITradeEventListener` and derives closed-trade records/KPIs from normalized `MM_EVENT_OPEN/CLOSE` events. Tracks open positions (by position/ticket/symbol fallback), computes initial risk (SL distance/tick value with send-time planned-risk fallback), and calculates: WinRate, Profit Factor, Expectancy, Avg R, Max Drawdown (peak-to-trough on cumulative net), trades, gross/net, avg duration. Supports per-`ENUM_MM_ACCOUNT_MODE` KPI view and CSV export (`ticket,symbol,type,openTime,closeTime,volume,openPrice,closePrice,profit,commission,swap,R,duration,accountMode`).
- **`Include/Profiles/Profiles.mqh`**: `CProfileManager` provides default profiles for `Personal`/`Prop`/`Crypto` with risk basis/limits/DD/news/spread parameters, per-account tagged-JSON persistence (`MQL5/Files/MoneyManager/profiles_<login>.json` via `SimpleJson`), active-profile selection, and import/export of a profile JSON file.
- **`Include/Alerts/Alerts.mqh`**: `CAlertManager` emits cooldowned alerts for guard BLOCK/WARN (DD/loss codes routed to DD channel), news blackout, connection loss/restore, and DD-cap/daily-loss events (print/popup/sound/push configurable).
- **`Include/UI/StatusLog.mqh`**: central `IRejectSink` now forwards guard rejects to alerts.
- **`Include/UI/PanelShell.mqh`**: Drawer tabs **Main/Stats** (`K` toggle) showing KPI summary (mode-filtered with all-mode fallback) and active profile; buttons for CSV export, next profile, profile export/import (import path `MoneyManager\profile_import.json`), plus existing trade/position controls.
- **`MoneyManager.mq5`**: wires stats as lifecycle listener, registers planned risk on send, sets account-mode context, connects alert manager to status sink, triggers connection/news edge alerts, initializes/saves profiles.

## Spec notes / follow-ups
- R uses `net (profit+commission+swap) / initial risk`; initial risk prefers tracked SL-at-open, falls back to planned risk when unavailable. Partial-close aggregation and netting/hedging parity remain Phase 2/5 debt.
- Live DD/weekly/monthly/consistency counters are still best-effort from existing Protection/Prop wiring; full authoritative accounting and provider-backed news staleness/source tags are integration follow-ups.
- Compile reported 0 errors/0 warnings in MetaEditor; demo/functional evidence pending per project process.
