# Development Baseline

## 1. Project Identity & Versioning

| Item | Value | Source |
|---|---|---|
| Product | MetaTrader 5 Money Manager / Trade Manager EA | `MoneyManager.mq5`, `README.md` |
| EA property version | `1.70` | `MoneyManager.mq5:6` |
| Common header version | `1.0.0` (`MM_VERSION`) | `Include/Utils/Common.mqh:61` |
| Contract/schema version | `1.0` / `MM_CONTRACT_VERSION` | `Include/Core/Contracts.mqh`, `Docs/contracts.md` |
| Current Git branch | `phase1-foundation` | `git branch` |
| Latest commit | `f13b544` — `docs: finalize v1.0.0 docs and hardening fixes` | `git log` |
| Pre-existing working-tree change | `MoneyManager.ex5` (modified, not part of this documentation task) | `git status` |

**Note:** Version identifiers differ by context (`1.70` EA property, `1.0.0` common constant/changelog milestone). Both are present in the current codebase and should be treated as-is.

## 2. Repository Structure

```text
.
├── MoneyManager.mq5                  # Main EA entry point
├── MoneyManager.ex5                  # Compiled binary (pre-existing modification)
├── README.md
├── CHANGELOG.md
├── .gitignore
├── .gitattributes
├── .github/workflows/compile.yml     # CI compile workflow
├── CORE ENGINE.txt                   # Feature checklist (EN/FA notes)
├── PROJECT_COMPLETE.md
├── STATUS.md
├── Docs/
│   ├── architecture.md
│   ├── contracts.md
│   ├── getting-started.md
│   ├── phase1-test-results.md
│   ├── phase2-implementation.md
│   ├── phase2-prep.md
│   ├── phase3-implementation.md
│   ├── phase4-implementation.md
│   ├── phase6-implementation.md
│   ├── phase7-implementation.md
│   ├── simplejson-limitations.md
│   ├── tech-debt.md                  # Existing (preserved)
│   ├── test-checklist.md
│   ├── DEVELOPMENT_BASELINE.md       # This document
│   ├── MODULE_STATUS.md
│   ├── DEVELOPMENT_ROADMAP.md
│   └── TECHNICAL_DEBT.md
├── Include/
│   ├── Alerts/Alerts.mqh
│   ├── Core/
│   │   ├── Contracts.mqh
│   │   ├── ExecutionPolicy.mqh
│   │   ├── ExecutionRouter.mqh
│   │   ├── Logger.mqh
│   │   ├── LotSizing.mqh
│   │   ├── OrderManager.mqh
│   │   ├── PositionManager.mqh
│   │   ├── RejectSink.mqh
│   │   ├── RiskEngine.mqh
│   │   ├── SimpleJson.mqh
│   │   ├── StopLoss.mqh
│   │   ├── StopsValidator.mqh
│   │   └── TakeProfit.mqh
│   ├── Guards/
│   │   ├── GuardEngine.mqh
│   │   ├── IGuard.mqh
│   │   ├── NewsGuard.mqh
│   │   ├── PermissionGuard.mqh
│   │   ├── PropGuard.mqh
│   │   ├── ProtectionGuard.mqh
│   │   └── SessionSpreadGuard.mqh
│   ├── News/NewsManager.mqh
│   ├── Profiles/Profiles.mqh
│   ├── PropFirm/PropFirm.mqh
│   ├── Protection/Protection.mqh
│   ├── Session/SessionManager.mqh
│   ├── State/StateStore.mqh
│   ├── State/RecoveryEngine.mqh
│   ├── Statistics/Statistics.mqh
│   ├── Trade/TradeLifecycle.mqh
│   ├── UI/
│   │   ├── DragTool.mqh
│   │   ├── NewsBanner.mqh
│   │   ├── Panel.mqh
│   │   ├── PanelShell.mqh
│   │   ├── PositionDragTool.mqh
│   │   ├── PreviewOverlay.mqh
│   │   ├── SessionBadge.mqh
│   │   ├── StatusLog.mqh
│   │   └── UiStrings.mqh
│   └── Utils/Common.mqh
├── Tests/
│   ├── Phase1Test.mq5
│   ├── Phase2Test.mq5
│   ├── Phase3Test.mq5
│   └── IntegrationTest.mq5
├── .kilo/                            # Project-local Kilo config/plans/state
└── .continue/                        # Local tool state
```

## 3. Main EA Entry Point & Orchestration

- **Entry file:** `MoneyManager.mq5`
- **Lifecycle handlers:** `OnInit`, `OnDeinit`, `OnTick`, `OnTimer` (1s), `OnChartEvent`, `OnTradeTransaction`
- **Responsibilities:**
  - Declares user inputs (account, risk, trailing/BE, prop firm, news/session/spread, UI/magic).
  - Instantiates and wires core modules: risk/stops/execution, guards, lifecycle, protection/state/prop/news/session, profiles/stats/alerts, UI components.
  - Refreshes `MM_RiskContext` and `MM_GuardConfig` on tick/timer from live account, protection, state, prop, profile, news, and session data.
  - Routes UI actions (drag/send/position management/profile/stats/export) through `CPanelShell` → `CExecutionRouter` and related modules.
  - Applies in-trade controls (BE, trailing, time exit) per tick for positions matching configured magic.
  - Forwards `OnTradeTransaction` to `CTradeLifecycle` and records closed-deal outcomes into protection/prop/stats/logging paths.
  - Persists state/profiles and manages day resets, peaks, and connection/news edge alerts.

## 4. Core Modules & Responsibilities

| Area | Key modules | Primary responsibility |
|---|---|---|
| Contracts & types | `Core/Contracts.mqh`, `Utils/Common.mqh`, `Core/SimpleJson.mqh` | Shared structs/enums/listener interfaces, common helpers, minimal JSON serialization for state/profile data |
| Risk & sizing | `Core/RiskEngine.mqh`, `Core/LotSizing.mqh`, `Core/StopLoss.mqh`, `Core/TakeProfit.mqh` | Lot/risk calculation, basis selection, caps (risk/DD/aggregate), SL/TP computation methods, R:R |
| Validation & execution | `Core/StopsValidator.mqh`, `Core/ExecutionPolicy.mqh`, `Core/ExecutionRouter.mqh`, `Core/OrderManager.mqh`, `Core/PositionManager.mqh` | Pre-send validation, retcode/retry policy, guarded send pipeline, order/position operations (BE/trail/partial/close/time exit) |
| Observability & rejects | `Core/Logger.mqh`, `Core/RejectSink.mqh`, `UI/StatusLog.mqh`, `Trade/TradeLifecycle.mqh` | File/print logging, unified reject sink, transaction normalization and event dispatch |
| Guards | `Guards/GuardEngine.mqh`, `IGuard.mqh`, `PermissionGuard.mqh`, `PropGuard.mqh`, `ProtectionGuard.mqh`, `NewsGuard.mqh`, `SessionSpreadGuard.mqh` | Priority-ordered allow/warn/block checks for permissions, prop limits, protection/DD, news, session/spread |
| State & persistence | `State/StateStore.mqh`, `State/RecoveryEngine.mqh`, `Profiles/Profiles.mqh` | Per-account state (lock/atomic save/bak/migration/fail-safe, counters/baselines/peaks) and profile persistence/import/export; restart recovery orchestration on top of StateStore (backup fallback, corrupt-data handling, continuity-uncertain gating) |
| Account protection & prop | `Protection/Protection.mqh`, `PropFirm/PropFirm.mqh` | Daily/weekly/monthly DD tracking helpers, streaks/cooldown/trade counts, prop presets/rules and DD used/remaining calculations |
| Market context | `News/NewsManager.mqh`, `Session/SessionManager.mqh` | News events/blackout/staleness/source handling; session detection/filtering |
| Reporting & alerts | `Statistics/Statistics.mqh`, `Alerts/Alerts.mqh` | Trade KPIs, open-risk estimation, CSV export, cooldowned alerts |
| UI | `UI/PanelShell.mqh`, `UI/DragTool.mqh`, `UI/PreviewOverlay.mqh`, `UI/PositionDragTool.mqh`, `UI/NewsBanner.mqh`, `UI/SessionBadge.mqh`, `UI/UiStrings.mqh`, `UI/Panel.mqh` | Chart panel/drawer, drag planning, live preview, position drag/manage, banners/badges/strings/status |

## 5. Execution Architecture

### 5.1 New Trade Flow (Plan → Preview → Send)
1. **Plan creation:** `CDragTool` manages Entry/SL/TP lines and sizing inputs; `CPanelShell::TrySend`/`CDragTool::BuildPlan` produce `MM_TradePlan`.
2. **Context refresh:** `MoneyManager.mq5::RefreshRiskContext/RefreshGuardConfig` builds `MM_RiskContext` and `MM_GuardConfig` from account data, protection/state baselines/peaks, prop/profile rules, aggregate open risk (`CStatistics::CalcOpenRiskMoney`), news/session/spread, and permissions.
3. **Preview:** `CPreviewOverlay` combines `CRiskEngine`, `CStopsValidator`, and `CGuardEngine::Preview` to display lot/risk/RR/spread/guard status.
4. **Preflight:** `CExecutionRouter::Preflight` validates operational/state readiness, computes risk, validates stops/geometry/volume/margin, and requires `CGuardEngine::CanExecute` (if configured). Failures are reported via `IRejectSink`/status with reason codes.
5. **Send:** `CExecutionRouter::Send` applies execution policy/slippage/magic, calls `CExecutionPolicy::ExecuteWithRetry`/`CTrade`, logs/classifies retcodes, and records rejects on failure. `CPanelShell` confirms before send (and warns on instability), registers planned risk in statistics, and clears/deactivates drag on success.

### 5.2 Lifecycle & Accounting Flow
1. `OnTradeTransaction` → `CTradeLifecycle` normalizes broker events into `MM_TradeEvent`s and dispatches to `ITradeEventListener`s (e.g. `CStatistics`).
2. `MoneyManager.mq5` records deal outcomes into `CProtection` and `CPropFirm` (daily profit/loss/trade counters, trading-day tracking) and logs.
3. `CStateStore`/`CProtection` maintain day-start baselines and peaks; day reset saves state.

### 5.3 In-Trade Management Flow
- `OnTick` iterates positions by magic and applies optional BE (`MoveToBreakEven`), trailing (`TrailStop`), and time-based exit (`TimeBasedExit`) via `CPositionManager` with parameters from inputs.
- `CPositionDragTool` supports selecting/dragging SL/TP and actions (BE, trail once, partial close, close selected/all on symbol) through UI events with confirmations for destructive actions.

## 6. Risk Management Architecture

- **Sizing modes:** auto risk-percent (default input `SIZING_AUTO_RISK`) and manual lot; UI/drag can toggle mode and adjust value.
- **Risk basis (`CRiskEngine`):** Equity, Day-start Balance, or Allowed DD (`min(remaining Daily DD, remaining Max DD)` when provided). Prop-enabled contexts prefer Allowed DD; profiles can override basis.
- **Core calculation:** risk-per-lot derived from SL distance, tick value/size, and optional commission/swap estimates; lot is computed from allowed money after portfolio/open-risk and DD budgets, floored to volume step, and bounded by symbol/profile caps.
- **Caps/blocks:** max/min risk %, aggregate open-risk budget, remaining Daily/Max DD caps, max position volume, invalid/missing SL or symbol data, and below-minimum lot after caps.
- **Open-risk aggregation:** EA uses `CStatistics::CalcOpenRiskMoney(InpMagic,"")` for context; `CRiskEngine::CalcOpenRiskMoney` also provides SL-distance-based aggregation logic (used where invoked). Positions without SL cannot be fully quantified (tracked as limitation/debt).
- **Risk Guardian / guards:** `CProtectionGuard`, `CPropGuard`, `CPermissionGuard`, `CNewsGuard`, `CSessionSpreadGuard` evaluated via `CGuardEngine` to gate preview/send with BLOCK/WARN reasons.

## 7. UI Architecture

- **Panel:** `CPanelShell` renders mini/drawer chart objects (BG, labels, buttons) with Main/Stats tabs, language toggle (EN/FA), drag/send/clear/risk/profile/stats/position controls, and status/log display.
- **Planning:** `CDragTool` provides interactive chart lines for Entry/SL/TP, buy/sell activation, sizing/risk adjustments, template capture/apply hooks, instability detection, and plan building.
- **Preview:** `CPreviewOverlay` shows live lot/risk/RR/guard feedback during planning.
- **Position UI:** `CPositionDragTool` enables selection and SL/TP drag/management of open positions (magic-aware).
- **Context UI:** `CNewsBanner`, `CSessionBadge`, `CStatusLog` (implements `IRejectSink`), and `CUiStrings` provide market context, bilingual text/tooltips, and centralized reject/status output.
- **Legacy/alternate:** `UI/Panel.mqh` exists in source tree (see module status) alongside the active `PanelShell` path.

## 8. Account & Prop Firm Architecture

- **Account modes:** `ACCOUNT_PERSONAL` (default), `ACCOUNT_PROP`, `ACCOUNT_CRYPTO` (`Core/Contracts.mqh`, inputs, profiles/stats/mode labels).
- **Personal/default mode:** protection and profile limits drive DD/loss/trade/session/news constraints; risk basis defaults to equity unless overridden.
- **Prop Firm mode (optional):** enabled via `InpPropFirmEnabled` or prop account mode; `CPropFirm` loads presets/rules (FTMO/MFF/FundedNext/The5ers noted in implementation/docs) and computes used/remaining Daily/Max DD by reference; guard/config wiring applies prop limits (daily/max DD, position/consistency/weekend/trades as configured).
- **Profiles:** `CProfileManager` supplies default Personal/Prop/Crypto profiles and effective parameters (risk basis/min-max risk, DD/loss/profit limits, trades/cooldown/consec-loss, spread, news flags) with per-account persistence and import/export.
- **Operating assumption:** single connected trading account per runtime context (MT5 account session).

## 9. Order Types & Execution Capabilities

| Capability | Implementation status | Notes |
|---|---|---|
| BUY / SELL direction | Present | Plan/drag/UI support both sides |
| Market orders | Present | `CExecutionRouter`/`COrderManager`/drag plan market path |
| Pending Limit orders | Present | Order type/ext enums and plan building support pending types |
| Pending Stop orders | Present | Supported in contracts/order management |
| Stop-Limit / OCO types | Partially represented | `ENUM_ORDER_TYPE_EXT` includes `OT_STOP_LIMIT`, `OT_OCO` in `Utils/Common.mqh`; full end-to-end workflow depends on module/integration usage and broker support |
| Interactive Entry/SL/TP chart lines | Present | `CDragTool` (+ preview) |
| Automatic lot sizing by risk/SL | Present | `CRiskEngine` auto-risk mode |
| Manual lot override | Present | Manual sizing mode and inputs/UI toggles |
| Multi-TP planning | Present (contract/UI plumbing) | Plan supports multiple TP levels (`MM_MAX_TP_LEVELS` in contracts; legacy `MM_MAX_TP=3` in `Common.mqh`); roadmap targets optional multi-TP up to five initially |
| Break Even / Trailing / Time exit | Present (optional controls) | `CPositionManager` + EA tick logic; disabled/controlled by inputs |
| Position drag/modify/partial/close | Present | `CPositionDragTool` and panel actions with confirmations for destructive ops |
| Pre-send guards & confirmation | Present | Guard engine + UI confirm/instability prompt |

## 10. Testing Infrastructure

| Item | Path | Type | Notes |
|---|---|---|---|
| Phase 1 tests | `Tests/Phase1Test.mq5` | Script/test source | Contracts/state/lifecycle foundations (per naming/history) |
| Phase 2 tests | `Tests/Phase2Test.mq5` | Script/test source | Risk/stops/execution/drag preparation areas (per naming/history) |
| Phase 3 tests | `Tests/Phase3Test.mq5` | Script/test source | Guard/protection/prop-related coverage (per naming/history) |
| Integration tests | `Tests/IntegrationTest.mq5` | Script-based smoke/integration checks | Covers logger/news/protection/prop/retcodes/stops/stats/guards per `Docs/phase7-implementation.md` |
| Manual checklist | `Docs/test-checklist.md` | Documentation | Phase-oriented manual validation steps |
| Phase 1 evidence log | `Docs/phase1-test-results.md` | Documentation | Template pending execution/evidence; not a completed automated record |
| CI compile workflow | `.github/workflows/compile.yml` | Automation config | Exists in repo; no automated Strategy Tester suite documented |

**Verification note:** No agent-executed compile/test run is recorded in this task. Existing docs indicate compile evidence and demo/manual validation are tracked separately and may be pending for specific phases.

## 11. Current Baseline Assessment (Summary)

- Core architecture is modular and integrated around a single EA entry point with separated risk, validation, execution, guards, lifecycle, persistence, and UI layers.
- Market/pending planning, auto/manual sizing, guard-gated execution, in-trade management, profiles, statistics/CSV, alerts, and EN/FA UI elements are implemented in source.
- Product hardening areas remain (provider-backed live news, full netting/hedging parity validation, deeper Strategy Tester coverage, and complete accounting/persistence edge-case validation) and are documented in existing/new debt records.
