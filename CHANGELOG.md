# Changelog

All notable changes to this project are documented here (phase-based).

### Phase 16 — Automated Position Management Integration (2026-11-19)

- **Added:** `Include/Position/PositionManagementEngine.mqh` — automated position management engine on top of hardened `CPositionManager`: per-ticket/per-lifecycle automation (hedging and netting), automated Break Even (points/R/ANY, one-time per stage), automated trailing (fixed/ATR/candle, activation, step), multi-level partial close with server-confirmed execution, time-based exit, magic+symbol filtering, pending-confirmation state machine.
- **Added:** Restart-safe partial stage reconstruction from live positions + broker deal history (`HistorySelectByPosition`). Unknown/ambiguous history treated as UNKNOWN; partial-close stages not re-executed (fail safe); BE/trailing remain available (monotonic/duplicate-safe).
- **Added:** `MoneyManager.mq5` auto-management integration — 16 inputs in `=== Auto Position Management ===` group, `BuildPosMgmtConfig()`, `HandlePosMgmtToggle()`, engine init in `OnInit`, `OnTick()` delegation, UI status wiring.
- **Added:** `Include/UI/PanelShell.mqh` — `Auto` toggle button + `PM` status label.
- **Added tests:** `Tests/Phase16/EngineMath_Test.mq5`, `Tests/Phase16/RestartSafety_Test.mq5`, `Tests/Phase16/MultiPosition_Test.mq5` — deterministic decision math, fail-safe restart, multi-position cases.
- **All Phase 16 tests compile clean:** 0 errors, 0 warnings after MQL5 const/`StringToUpper` reference fixes and status-parameter rename.
- **MoneyManager.mq5 compiles clean:** 0 errors, 0 warnings.
- **TD-19 added:** no parallel position-management state file; restart safety via live positions + deal history reconstruction (fail safe on unknown history).

### Phase 15 — Position Management Safety & Reliability (2026-11-19)

- **Hardened:** `Include/Core/PositionManager.mqh` — MoveToBreakEven, TrailStop, PartialClose, TimeBasedExit now check SYMBOL_TRADE_STOPS_LEVEL and SYMBOL_TRADE_FREEZE_LEVEL, normalize SL/price to symbol digits, validate volume against VOLUME_MIN/VOLUME_MAX/VOLUME_STEP, check server retcodes (not just CTrade bool), preserve TP, prevent SL loosening, guard maxMinutes <= 0, avoid repeated close attempts, and track last error/retcode.
- **Hardened:** `Include/UI/PositionDragTool.mqh` — ApplyModify, MoveToBE, ApplyTrailOnce, PartialClose, CloseSelected now apply the same safety checks (stops/freeze levels, tick normalization, retcode checking, percent validation, remaining-volume validation).
- **Added test:** `Tests/Phase15/PositionManager_Test.mq5` — BE direction safety, SL protection, invalid ticket handling, percent validation, time exit disabled, volume normalization, margin mode awareness, magic filtering.
- **Added test:** `Tests/Phase15/PositionDragTool_Test.mq5` — BE/trail direction safety, ATR unavailability, volume boundaries, invalid percentages, stop/freeze rejection, TP preservation, retcode checking.
- **All Phase 15 tests compile clean:** 0 errors, 0 warnings.
- **MoneyManager.mq5 compiles clean:** 0 errors, 0 warnings.

### Phase 14 — Protection & Prop Accounting Hardening (TD-04) (2026-11-19)

- **Fixed:** `WeekKeyMonday` in `Include/Protection/Protection.mqh` now anchors week 0 to the first Monday of the year (Monday-start weeks). Days before the first Monday form a partial first week (weekIndex=0). Previously the week index calculation could produce negative indices for early-year dates.
- **Added test:** `Tests/Phase14/MinimalProtection_Test.mq5` — deterministic checks for fresh protection init and prop firm enable/load preset.
- **Added test:** `Tests/Phase14/Protection_Prop_Test.mq5` — deterministic checks for weekly/monthly loss calculation, daily/weekly/monthly reset, restart persistence, commission/swap/fee inclusion, partial close accounting, daily DD, max DD, equity/balance reference, risk-increasing block, profit target, min trading days, consistency.
- **All Phase 14 tests compile clean:** 0 errors, 0 warnings in MetaEditor.
- **TD-04** (weekly/monthly loss tracking/enforcement and prop consistency/profit-target/min-trading-days logic) — protection accounting tests added; runtime demo validation pending.
- **Zero new trading behavior introduced.**

### Phase 13 — Hedging & Netting Compatibility (TD-02) (2026-11-19)

- **Fixed:** `PositionStillOpen` in `Include/Trade/TradeLifecycle.mqh`, `Include/Statistics/Statistics.mqh`, and `MoneyManager.mq5` now verifies `POSITION_TYPE` matches the expected side before reporting a position as "still open." Previously, netting reversals (BUY↔SELL with preserved `POSITION_IDENTIFIER`) false-positive matched the new reversed position, causing old directional lifecycles to be misclassified as partial closes instead of completed closes.
- **Fixed:** `SyncOpenFromPosition` in `Statistics.mqh` direction-guards sync to prevent tracking data from a reversed position under a preserved identifier.
- **Fixed:** `HandlePartialClose` in `Statistics.mqh` starts a new logical lifecycle track for INOUT reversal opposite exposure (no carryover/merge) when the server position still exists with flipped direction.
- **Fixed:** `MoneyManager.mq5` `OnTradeTransaction` passes expected side (derived from deal type) to `PositionStillOpen` for DEAL_ENTRY_OUT and DEAL_ENTRY_INOUT.
- **Added test:** `Tests/Phase13/HedgingNetting_Test.mq5` — deterministic checks for hedging multi-position, hedging partial close, netting volume increase/decrease, netting reversal (BUY→SELL, SELL→BUY), aggregate open risk, net PnL with no double counting, SL/TP management, plus Phase 12/2.3 regressions.
- **TD-02** moved from Potential Defects to Addressed in `Docs/TECHNICAL_DEBT.md`.
- **Zero new trading behavior introduced** for non-reversal paths; no martingale added.

## [v1.0.0] - 2026-11-18

### Summary
- Code-complete for Phases 1–7 (foundation, risk/execution, guards, drag UI/preview, in-trade management, stats/profiles/alerts/CSV, hardening).
- Phase 7 compile verified in MetaEditor: **0 errors, 0 warnings** (user-reported). `MoneyManager.ex5` built locally.
- Final documentation added: `Docs/test-checklist.md`, `Docs/tech-debt.md`, `Docs/getting-started.md`, `Docs/architecture.md`.
- `MM_VERSION` set to `1.0.0` in `Include/Utils/Common.mqh`.

### Notes
- Pending: final demo validation and Strategy Tester coverage (see `Docs/tech-debt.md`, `Docs/test-checklist.md`). Record evidence in `Docs/phase1-test-results.md` and phase test artifacts as applicable.

### Phase 2.3 Runtime Verification (2026-11-19)
- **Status:** Completed – Unit/Script Runtime Verified (recorded in `Docs/Implementation/PHASE_2_3_RUNTIME_VERIFICATION.md`).
- **MT5 script runtime results (reported):** `Tests/Phase3/GuardEngine_Test.mq5` ALL PASS, `Tests/Phase2_3/ProtectionLimits_Test.mq5` ALL PASS, `Tests/Phase2_3/TradeAggregation_Test.mq5` ALL PASS. **Total: 70 assertions successful.**
- **Limitations (pending):** Netting reversal integration not yet executed on a Netting account; EA integration testing on a demo account is not complete. No successful tests or Phase 2.1/2.2 logic changed for this status record.

### Phase 6 / Phase 7 progress (2026-11-19)
- **Phase 6 (Multi-TP):** Implemented and compiled (0 errors, 0 warnings). Optional Multi-TP planning/validation/UI (up to 5) with hedging-only split execution and explicit netting pre-send rejection; single-TP path preserved. Demo integration runtime **pending** (no runtime PASS claimed).
- **Phase 7 (Personal Account Configuration, in progress):** Hardened effective mode/profile handling so prop-firm engine/rules/guard context are inactive unless explicitly configured; personal risk-basis fallback kept non-prop; UI/stats surfaces transparent personal protection/limit diagnostics (DL/WL/ML/DD/trades/cooldown/consec + active mode/profile). Added focused test `Tests/Phase7/PersonalAccount_Config_Test.mq5`. Compiles clean (0 errors, 0 warnings); runtime MT5 script/demo verification **not run**.

### Phase 8 progress (2026-11-19)
- **Phase 8 (Optional Prop Firm Configuration, in progress):** Preset/rule mapping and DD used/remaining aligned to configured references (equity/balance) with baseline/peak sync in runtime context; prop rules remain explicit/optional and inactive in personal mode; unsupported/unverified rules (consistency/min-trading-days runtime-only history not persisted) are not falsely enforced and marked as unverified; UI stats surfaces prop DD used/limits when prop explicitly active. Added focused test `Tests/Phase8/PropFirm_Config_Test.mq5`. Compiles clean (0 errors, 0 warnings); runtime MT5 script/demo verification **not run**.

### Phase 9 progress (2026-11-19)
- **Phase 9 (Risk Guardian and Account Protection, in progress):** Hardened `CProtection` exposure dedupe ring handling (correct ring insert/lookup/head reset on overflow) to preserve recent dedupe/count integrity, and made cooldown/consecutive-loss expiry/reset behavior predictable (`CheckCooldown`/`CheckConsecutiveLoss` consistent with `UpdateCooldown`). Weekly/monthly realized loss accounting, server-time period sync/reset, guard priority/first-block and preview/send consistency, and existing preflight/state-operational gating remain intact (risk-reducing position management unchanged). Added focused test `Tests/Phase9/RiskGuardian_Test.mq5`. Compiles clean (0 errors, 0 warnings); runtime MT5 script/demo verification **not run**.

### Phase 10 progress (2026-11-19)
- **Phase 10 (News and Trading Sessions, in progress):** Removed synthetic default news events and made unavailable/stale/live-fetch-unverified states explicit (no silent assumptions, no false blackouts from invented data); blackout evaluation limited to known symbol/currency-relevant events with effective profile/input blackout windows. Session detection hardened with UTC-based, approx DST-aware range handling and explicit filter-allowed helper wired into guard config. Added focused test `Tests/Phase10/NewsSession_Test.mq5`. Compiles clean (0 errors, 0 warnings); runtime MT5 script/demo verification **not run**. Live provider WebRequest/fetch-parsing and exchange-accurate DST/calendar mapping remain unverified/deferred.

### Phase 11 progress (2026-11-19)
- **Phase 11 (Statistics and Reporting, in progress):** Improved statistics aggregation for partial/INOUT closes (deterministic lifecycle finalization path for focused/offline accounting, preserved initial-risk baseline for aggregated R, commission/swap included in net) and added additive `net` column to CSV export for reconciliation while preserving existing schema order. Stats UI now clarifies per-mode/all context and totals; incomplete data remains non-blocking. Added focused test `Tests/Phase11/Statistics_Reporting_Test.mq5`. Compiles clean (0 errors, 0 warnings); runtime MT5 script/demo verification **not run**. Broker-history reconciliation and full hedging/netting parity remain pending validation.

### Phase 12 / Persistence & Recovery (2026-11-19)
- **Persistence & Recovery Engine (next phase priority, TD-05/TD-17):** Roadmap has **no independent "Persistence and Recovery Engine" phase**; persistence/recovery safety gaps (TD-05 state persistence/migration/gating under restart/upgrade/corruption; TD-17 time-fallback surfacing) are addressed as the next phase priority, building on existing `StateStore`/`Protection`/`TradeLifecycle`/`Statistics` without rewriting healthy code.
- **Added:** `Include/State/RecoveryEngine.mqh` — `CRecoveryEngine` orchestrates restart recovery on top of `CStateStore`. Recovery outcomes: `PRIMARY_OK`, `BACKUP_FALLBACK`, `DEGRADED`, `BLOCKED`, `EXPLICIT_INIT_OK`. Never auto-resets/re-bases protective baselines when continuity uncertain; blocks new risk-increasing actions until explicit resolution; keeps risk-reducing position management (BE/trail/close) active even in failed/blocked recovery state; preserves original state + `.bak`; no account identity (login/broker/server) persisted.
- **Wired:** `MoneyManager.mq5` binds `CRecoveryEngine` to `CStateStore` on `OnInit`, gates `StoreReadyForRiskIncreasing()` on recovery state, position risk-reduction loop in `OnTick` remains active regardless of recovery outcome.
- **Added test:** `Tests/Phase12/RecoveryEngine_Test.mq5` — focused checks: fresh init block, explicit init, simulated restart (continuity uncertain, state preserved), corrupt primary + valid backup (backup fallback), corrupt primary + corrupt backup (blocked/manual review), future schema (blocked, no rebase, no overwrite), privacy (no login/server/broker persisted), risk-reduction active invariant in all states.

## [v0.7.0-phase7] - 2026-11-18 (Phase 7: Hardening)

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
- Compile verified in MetaEditor (0 errors, 0 warnings) per user report. Functional/demo evidence pending.

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


