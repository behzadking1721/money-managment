# Phase 3 (Unified Guards) — Implementation Notes

## Delivered
- `Include/Guards/IGuard.mqh`: `IGuard` interface, `MM_GuardConfig` (permission/protection/prop/news/session-spread limits, runtime counters/state flags), `MM_MAX_GUARD_RESULTS`.
- **Guards (in frozen priority/reporting order):**
  1. `PermissionGuard.mqh` — terminal connected, auto-trading/EA/account/symbol trade permissions & close-only (BLOCK).
  2. `PropGuard.mqh` — daily/max DD, max trades/day, max position size, consistency (config-driven), weekend window warning (BLOCK/WARN, `ACCOUNT_PROP` only).
  3. `ProtectionGuard.mqh` — daily/weekly/monthly loss, daily profit lock, max drawdown, max trades/day, cooldown/consecutive loss (BLOCK).
  4. `NewsGuard.mqh` — blackout (BLOCK when configured), upcoming/warn states, **offline/stale default WARN** with optional BLOCK (`newsOfflineBlock`) per frozen spec.
  5. `SessionSpreadGuard.mqh` — session filter (BLOCK) and spread max BLOCK / elevated WARN.
- `Include/Guards/GuardEngine.mqh` (`CGuardEngine`, `MM_GuardReport`):
  - Evaluates guards in priority order; aggregates results, first blocking reason.
  - **Central sink routing:** every BLOCK/WARN is sent to `IRejectSink::OnGuardReject` (unified path). `CanExecute`/`Evaluate` report to sink; `Preview` evaluates without sink side-effects for UI live preview.
  - `FillLiveConfig` helper for live spread snapshot.
- `Include/Core/ExecutionRouter.mqh`: wired optional `CGuardEngine` + `MM_GuardConfig`; `Preflight`/`Send` run guards on sized plan after risk+stops, block via first guard reason (already sink-reported). `MM_ExecResult` carries `MM_GuardReport`.

## Default block vs warn behavior (as configured)
- **BLOCK:** permission/trading disabled, prop DD/limits/max position/consistency breaches, protection hard limits & cooldown/consec-loss, news blackout when `newsBlackoutOnHigh`, offline-stale when `newsOfflineBlock`, disallowed session, spread over max.
- **WARN:** prop weekend window, news upcoming or stale/offline (default), spread above warn threshold.

## Integration notes
- `MM_GuardConfig` runtime fields (counters, DD used, news state/blackout/stale, sessionAllowed, spread) must be populated by StateStore/Stats/Prop/News/Session modules at evaluation time (Phase 3 glue / later phases).
- `ExecutionRouter.Init/SetGuards` + pass `guardCfg` to `Preflight/Send` enables pre-send enforcement; UI can use `GuardEngine.Preview` for non-mutating live feedback.
- All guard BLOCK/WARN flow to the single reject sink per contract; no parallel reject paths.

## Tests
- `Tests/Phase3/GuardEngine_Test.mq5`: allow, protection block, Prop-over-Protection priority, news stale warn (default) & blackout block, session block, spread block/warn, sink routing, `Preview` no side-effects.

## Pending wiring (subsequent phases)
- Source config/counters from real Protection/Prop/News/Session/State modules and persist; connect `daily/weekly/monthly` accounting and prop DD basis/reset/consistency from lifecycle events.
- News provider (FF+cache+manual) to set `newsInBlackout/newsIsStale/newsDataAvailable/newsUpcomingWarn` and impact mapping.