# Changelog

All notable changes to this project are documented here (phase-based).

## [v0.7.0-phase7] - In progress (Phase 7: Hardening)

### Added
- `Include/Core/Logger.mqh`: file logger (`g_mmLog`) with rotation/cleanup for EA/guard/execution/trade/news/state events.
- `Tests/IntegrationTest.mq5`: integration smoke script covering logger/news staleness, DD/remaining helpers, prop DD helpers, retcode classification, stops validation, stats aggregation/open-risk, and key guard decisions.
- `Docs/phase7-implementation.md`: Phase 7 implementation/wiring notes and pending verification.

### Changed
- `MoneyManager.mq5` (v1.70): Phase 7 wiring for logger init, real open-risk into risk context, profile/protection/prop-firm/state DD & day-start context, news staleness/source/blackout guard inputs, trade-close recording hooks, and day/state sync.
- `Include/PropFirm/PropFirm.mqh`, `Include/Protection/Protection.mqh`, `Include/State/StateStore.mqh`: day-start/peak tracking and remaining/used DD helpers with persistence/logging support.
- `Include/News/NewsManager.mqh`, `Include/UI/NewsBanner.mqh`: news source/staleness API and banner display.
- `Include/Statistics/Statistics.mqh`, `Include/Trade/TradeLifecycle.mqh`: partial-close/in-out aggregation, live open-risk calc, hedging/netting-aware event normalization and logging.
- `Include/Core/ExecutionPolicy.mqh`, `Include/Core/ExecutionRouter.mqh`, `Include/Core/StopsValidator.mqh`: unknown retcode/partial-fill handling, route logging, and symbol/property/margin edge-case validation.
- `Include/Guards/GuardEngine.mqh`: news-state application helper for guard config.
- `Include/UI/PanelShell.mqh`, `Include/UI/DragTool.mqh`, `Include/UI/UiStrings.mqh`, `Include/UI/PreviewOverlay.mqh`: expanded bilingual labels/tooltips and UI polish.

### Notes
- MetaEditor compile/test not executed by agent; user verification pending (target 0 errors/0 warnings) with demo/script evidence.

## [v0.6.0-phase6] - In progress (Phase 6: Stats, Profiles, Alerts, CSV)

### Added
- `Include/Statistics/Statistics.mqh`: event-driven `CStatistics` (`ITradeEventListener`) computing KPIs from `MM_EVENT_OPEN/CLOSE` (WinRate, Profit Factor, Expectancy, Avg R, Max Drawdown peak-to-trough, trades, avg duration), per-`AccountMode` filtering, planned-risk registration for R, and CSV export (ticket,symbol,type,openTime,closeTime,volume,openPrice,closePrice,profit,commission,swap,R,duration,accountMode).
- `Include/Profiles/Profiles.mqh`: `CProfileManager` with Personal/Prop/Crypto defaults, extended risk/DD/limits/news params, per-account JSON store, and profile import/export (JSON).
- `Include/Alerts/Alerts.mqh`: `CAlertManager` with cooldowned alerts for guard block/warn (via reject sink), news blackout, connection loss/restore, and DD/loss-cap events (log/popup/sound/push configurable).
- `Include/UI/StatusLog.mqh`: forwards guard rejects to `CAlertManager`.
- `Include/UI/UiStrings.mqh`, `Include/UI/PanelShell.mqh`: drawer **Stats/Main** tab with KPI lines, account/profile label, and buttons for CSV export, profile next/export/import (with confirmation/opt-in where applicable); hotkey `K` toggles tab.
- `MoneyManager.mq5`: Phase 6 wiring (stats listener on lifecycle, alert manager + connection/news alerts, profile init/active-by-mode/save, UI stats/profile integration, planned-risk registration on send).

### Notes
- Compile verified in MetaEditor (0 errors, 0 warnings) per local run; functional/demo evidence pending.

## [v0.5.0-phase5] - In progress (Phase 5: In-trade Management)

### Added
- `Include/UI/PositionDragTool.mqh`: drag SL/TP for selected open position with server sync/apply, BE, trail-once, partial close, and opt-in confirmed multi-position actions.
- `Include/UI/PanelShell.mqh`, `MoneyManager.mq5`: position management controls/hotkey (`P`) and tick/chart-event wiring.

### Notes
- Advanced trail/lock-profit variants and broader multi-position workflows to be extended; compile verified in MetaEditor (0 errors, 0 warnings) per local run.

## [v0.4.0-phase4] - In progress (Phase 4: Drag & Drop UI & Live Preview)

### Added
- `Include/UI/UiStrings.mqh`: bilingual EN/FA UI strings.
- `Include/UI/StatusLog.mqh`: status log implementing `IRejectSink` (central BLOCK/WARN/error capture) for UI.
- `Include/UI/NewsBanner.mqh`, `Include/UI/SessionBadge.mqh`: news banner (title/time/impact/source tag) and session badge.
- `Include/UI/DragTool.mqh`: draggable Entry/SL/TP(1-3) chart lines, buy/sell, auto market/pending (limit/stop) inference + override, risk%/manual-lot mode, instability detection, template capture/apply.
- `Include/UI/PreviewOverlay.mqh`: live lot/risk/RR/spread/type and Risk/Stops/Guards preview (block/warn reasons, no sink side-effects).
- `Include/UI/PanelShell.mqh`: Mini/Drawer panel shell with controls, hotkeys, confirm/no-silent-send, preflight+send via `ExecutionRouter`.
- `MoneyManager.mq5`: Phase 4 orchestration (State/Lifecycle/Guards/Router + Drag/UI wiring, live context refresh, `OnTradeTransaction`).
- Docs: `Docs/phase4-implementation.md`.

### Notes
- Build verified locally (0 errors/warnings reported). Full persistence (UI state/templates per symbol), ATR snap/RR-lock handles, drawer tabs, visual/virtual SL-TP, and live news/provider-session wiring to be completed in subsequent integration.

## [v0.3.0-phase3] - In progress (Phase 3: Unified Guards)

### Added
- `Include/Guards/IGuard.mqh`: guard interface, `MM_GuardConfig`, result aggregation primitives.
- Guards (priority order): `PermissionGuard` (connection/trade/symbol permissions), `PropGuard` (daily/max DD, trades, position size, consistency, weekend warn), `ProtectionGuard` (daily/weekly/monthly loss, profit lock, max DD, trades, cooldown/consec loss), `NewsGuard` (blackout block/warn, offline-stale warn by default with optional block), `SessionSpreadGuard` (session filter, spread max block/warn).
- `Include/Guards/GuardEngine.mqh`: unified evaluation/`CanExecute`/`Preview`, first-block reporting, **all BLOCK/WARN routed to central `IRejectSink::OnGuardReject`**.
- `Include/Core/ExecutionRouter.mqh`: integrated guard preflight (sized plan) before send; `MM_ExecResult` includes guard report.
- Tests/docs: `Tests/Phase3/GuardEngine_Test.mq5`, `Docs/phase3-implementation.md`.

### Notes
- Runtime config/counters/news-session state to be wired from State/Stats/Prop/News/Session modules; build verified locally (0 errors/warnings reported).

## [v0.2.0-phase2] - In progress (Phase 2: Risk/Execution/Sizing)

### Added
- `Include/Core/RiskEngine.mqh`: risk basis (Equity/BalanceDay/AllowedDD=min daily/max), per-lot risk via tick value/size, auto & manual sizing, aggregate open-risk + DD remaining caps, conservative step-floor lot normalization, no-SL block, RR calc, live context/open-risk helpers.
- `Include/Core/StopsValidator.mqh`: stops/freeze min distance, pending type inference, pending/SLTP/margin/volume/trade-mode validation, `ValidatePlan` pre-send gate.
- `Include/Core/ExecutionPolicy.mqh`: per-symbol/template slippage (deviation), retryable vs terminal retcode policy (frozen set), success/partial handling, retcode reasons, bounded retry executor.
- `Include/Core/ExecutionRouter.mqh`: preflight (operational gate â†’ risk â†’ stops) and send pipeline with retry and central `IRejectSink` reporting (GuardEngine hook for Phase 3).
- Phase 2 tests/docs: `Tests/Phase2/{RiskEngine,StopsValidator,ExecutionPolicy}_Test.mq5`, `Docs/phase2-implementation.md`, `Docs/phase2-prep.md`.

### Notes
- Phase 2 complete when local build/tests (incl. FX/JPY/crypto & cap/retcode scenarios) pass and evidence is recorded/committed.

## [v0.1.0-phase1] - Unreleased (Phase 1: Foundation)

### Added
- Repository skeleton: `Experts/`, `Include/`, `Tests/`, `Docs/`, `.kilo/plans/` with frozen implementation plan.
- Project docs: `README.md`, `CHANGELOG.md`, `.gitignore` (MT5 artifacts, logs, local data, sensitive sets, `.continue`, tracked only `.kilo/plans`).
- Frozen shared contracts (`Include/Core/Contracts.mqh`, `Docs/contracts.md`): `AccountMode`, `SizingMode`, `GuardDecision`, `TradePlan`, `RiskResult`, `GuardResult`, `TradeEvent`, `Profile`, `Template` with schema `version` for state migration.
- Unified reject sink contract: `Include/Core/RejectSink.mqh` (`IRejectSink`); `CTradeLifecycle::RecordGuardReject` for guard BLOCK/WARN + execution rejects.
- File-based `StateStore` per account (`MQL5/Files/MoneyManager/state_<login>.json`): shared lock (owner/pid recorded) + stale-lock takeover (default 30s, logged), **atomic** write (tmpâ†’move, fallback direct **after** `.bak`), single `.bak`, server-time counters/resets with explicit `timeFallback` + warning, fail-safe non-operational on future `version` (no overwrite / no trading), restart-safe per-symbol/template persistence, version migration hook.
- `TradeLifecycle` (`OnTradeTransaction`) normalizing to `TradeEvent`, `ITradeEventListener` dispatch, central reject-reason sink (execution + guards contract). Unified reject path mandated for Phase 3 (`IRejectSink`, no parallel sinks).
- Phase 1 tests/checklists & scripts: `Tests/Phase1/SimpleJson_Test.mq5`, `StateStore_Test.mq5`, `Lifecycle_Map_Test.mq5`, manual checklist, `Docs/phase1-test-results.md` (pending real execution), `Docs/simplejson-limitations.md`.

### Notes
- Build and functional testing are performed locally in MetaEditor/MT5; evidence recorded in `Docs/phase1-test-results.md`.
- **Phase 1 not complete until:** local MetaEditor build (0 errors/warnings) and all Phase 1 tests (incl. multi-chart lock, stale-lock recovery, state migration, netting/hedging event cases as applicable) are executed and evidence recorded in `Docs/phase1-test-results.md`, then committed/pushed and tagged `v0.1.0-phase1`.
- **Phase 2 tech debt:** netting vs hedging deal/partial-close normalization and position aggregation parity in `TradeLifecycle` (Phase 1 conservative) â€” validate in demo and finalize in Phase 2.
- MT5 minimum build: TBD (record after compile verification).
- SimpleJson is minimal (known/tagged keys only) â€” see limitations doc.

## [0.0.1] - Prior state
- Initial prototype modules and `MoneyManager.mq5`/`MoneyManager.ex5` present before Phase 1 restructure.

