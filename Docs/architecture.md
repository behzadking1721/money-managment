# Architecture Overview

## Scope
MT5 Money Manager EA (MQL5) providing drag-and-drop trade planning (market/pending), live risk/lot/RR preview, unified pre-send guards, in-trade management, and lifecycle-driven statistics/profiles/alerts with persistent state.

- Entry: `MoneyManager.mq5` (orchestration, inputs, timers/ticks, chart events).
- Shared types/contracts: `Include/Core/Contracts.mqh`, utilities `Include/Utils/Common.mqh`.
- Persistence format helpers: `Include/Core/SimpleJson.mqh`.

## High-level Modules

### Core (`Include/Core/`)
- **Contracts**: `MM_TradePlan`, `MM_RiskContext/Result`, `MM_GuardConfig/Result/Report`, `MM_TradeEvent`, enums (account/sizing/guards/events), listener interface.
- **RiskEngine**: computes lot/risk money/% and R:R from plan + context; enforces basis (equity/balance-day/allowed-DD), min/max risk, aggregate open risk, and remaining Daily/Max DD caps.
- **StopsValidator**: validates symbol properties, stops/freeze distances, pending entry/SLTP geometry, volume bounds, and margin/price availability.
- **ExecutionPolicy**: slippage/deviation, retryable vs terminal vs success/partial retcode classification (incl. unknown), bounded retry, partial-fill logging/policy.
- **ExecutionRouter**: preflight pipeline (operational/state → risk → stops → guards) and send path via `CTrade`, returning `MM_ExecResult`; reports rejects to central sink.
- **RejectSink / Logger**: unified reject/status reporting; `CMMLogger` (`g_mmLog`) file+print logging with rotation.
- **Position/Order/SL/TP helpers**: broker operations and trade utilities.

### Guards (`Include/Guards/`)
- **GuardEngine**: evaluates guards in priority order, aggregates results, exposes `CanExecute`/`Preview`; routes BLOCK/WARN to `IRejectSink`.
- **PermissionGuard**: connection/terminal/EA/account/symbol trading permissions.
- **PropGuard**: prop-firm limits (daily/max DD, trades, position/consistency/weekend) using prop rules and live usage.
- **ProtectionGuard**: personal/protection limits (daily/weekly/monthly loss, profit lock, max DD, trades/day, cooldown/consec losses).
- **NewsGuard**: blackout/warn based on availability, staleness, and offline-block policy.
- **SessionSpreadGuard**: session filter and spread max/warn thresholds.

### Trade Lifecycle (`Include/Trade/`)
- **TradeLifecycle**: normalizes `OnTradeTransaction` (deals/orders/requests/positions) into `MM_TradeEvent`s and dispatches to `ITradeEventListener`s; records execution/guard rejects; hedging/netting-aware partial/close/in-out handling with logging.

### State & Protection (`Include/State/`, `Include/Protection/`, `Include/PropFirm/`)
- **StateStore**: per-account JSON state in `MQL5/Files/MoneyManager/` with lock/stale-takeover, atomic save + `.bak`, migration/fail-safe, counters/reset keys, and day-start/peak baselines.
- **Protection**: tracks daily P/L, trades, streaks/cooldown, day-start and peak equity/balance, DD% and remaining DD money.
- **PropFirm**: preset/rule management and DD used/remaining calculations by equity/balance reference.

### Market Context (`Include/News/`, `Include/Session/`)
- **NewsManager**: event store, blackout checks, source/staleness tracking (`live/cache/manual/stale`), and safe defaults when offline.
- **SessionManager**: current session detection (UTC/DST-aware helpers) for session filtering/badges.

### Profiles, Stats, Alerts (`Include/Profiles/`, `Include/Statistics/`, `Include/Alerts/`)
- **Profiles**: default Personal/Prop/Crypto profiles, effective risk/limits/news/spread parameters, per-account persistence, active selection, import/export.
- **Statistics** (`ITradeEventListener`): tracks open/closed trades, partial-close aggregation, planned/initial risk for R, KPIs (WR, PF, expectancy, Avg R, net, max DD, avg duration), per-mode views, and CSV export.
- **Alerts**: cooldowned notifications for guard/news/connection/DD events (log/popup/sound/push configurable).

### UI (`Include/UI/`)
- **PanelShell**: mini/drawer panel, tabs (Main/Stats), controls, tooltips, bilingual labels, status/log integration, send confirmation and preflight UX.
- **DragTool**: draggable Entry/SL/TP plan lines, buy/sell, market/pending inference, sizing mode/risk, instability detection, template capture/apply.
- **PreviewOverlay**: live preview (lot/risk/RR/spread/type) combining risk, stops, and guard preview results.
- **PositionDragTool**: select/manage open positions (drag SL/TP, BE, trail, partial/close) with opt-in confirmations.
- **NewsBanner / SessionBadge / StatusLog / UiStrings**: contextual display, reject/status surface, and EN/FA strings.

## Key Data Flows

### New Trade (Drag → Preview → Send)
1. User activates drag (UI/hotkeys) → `DragTool` maintains Entry/SL/TP and builds `MM_TradePlan`.
2. EA refreshes `MM_RiskContext` (open risk from stats, DD/day-start from protection/state/prop/profile) and `MM_GuardConfig` (limits, news/session/spread/permissions).
3. `PreviewOverlay` runs `RiskEngine`, `StopsValidator`, and `GuardEngine.Preview` to display live status/reasons.
4. On send, UI calls `ExecutionRouter.Preflight/Send` (risk+stops+guards, no-silent-send, confirm) → `ExecutionPolicy/CTrade` execute with retcode handling/retry/logging; rejects go to sink/status/alerts.

### Lifecycle → Stats/Protection/State
1. `OnTradeTransaction` → `TradeLifecycle` emits `MM_TradeEvent`s and rejects.
2. `Statistics` listener updates open/close/partial aggregates, KPIs, and open-risk; CSV export on demand.
3. EA/protection update trade outcomes, day resets, peaks/baselines; `StateStore` persists operational state; alerts/logger record notable events.

### Guards Context
- Inputs + active profile + live modules (protection, prop, news, session, spread, terminal/account state) populate `MM_GuardConfig` each refresh/tick/timer; guard decisions gate preview/send and are centrally reported.

## Files & Runtime Artifacts
- Source: `MoneyManager.mq5`, `Include/**`, `Tests/**`, `Docs/**`.
- Runtime (per account, `MQL5/Files/MoneyManager/`): state JSON/lock/bak/tmp, profiles, CSV exports, rotated logs.

## Extension Points
- Add/adjust guards implementing `IGuard` and register in `GuardEngine` priority order.
- Subscribe additional `ITradeEventListener`s to `TradeLifecycle` for analytics/integrations.
- Extend `INewsProvider`/news parsing for live sources while preserving staleness/offline safety.
- Evolve state/profile schemas with versioned migration in `SimpleJson`/`StateStore`.
