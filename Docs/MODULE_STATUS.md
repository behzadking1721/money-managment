# Module Status Inventory

Classification legend:
- **Complete**: Implemented for its intended scope in current baseline (may still have known limitations).
- **Partially Complete**: Implemented core behavior but missing depth/integration/validation for full intended scope.
- **Legacy**: Older or alternate implementation retained; not the primary active path.
- **Not Used**: Present but not wired into the active EA/runtime path (based on current source wiring).
- **Needs Verification**: Usage/behavior cannot be confirmed from static inspection alone.

> Note: A module is not marked incomplete solely because it is not on the primary execution path.

## 1. Entry Point & Shared

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `MoneyManager.mq5` | EA orchestration, inputs, module wiring, event/timer/tick handlers, context refresh, in-trade management hooks | Complete | Yes (main entry) | Most `Include/*` modules, MT5 trade/account/chart APIs | `PositionStillOpen` direction guard prevents netting reversal false-positive; INOUT reversal starts new logical lifecycle; contains significant integration logic |
| `Include/Utils/Common.mqh` | Common enums/structs/constants and utility helpers (lot normalization, points/prices, ATR/spread/suffix/account helpers) | Complete | Yes | MQL5 trade/symbol/account includes | Some constants/structs overlap conceptually with newer contracts; verify unused legacy types before relying on them |
| `Include/Core/Contracts.mqh` | Canonical shared contracts (plan/risk/guard/exec/events, listener/reject interfaces, config structs) | Complete | Yes | MQL5 std types, project conventions | Schema evolution requires version/migration discipline (see `Docs/contracts.md`) |
| `Include/Core/SimpleJson.mqh` | Minimal JSON builder/reader for known schemas (state/profiles persistence support) | Partially Complete | Yes (indirect via state/profiles modules) | File/string parsing utilities | Limited/general-purpose JSON support; see `Docs/simplejson-limitations.md` |

## 2. Core Execution & Risk

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `Include/Core/RiskEngine.mqh` | Risk/lot sizing, basis selection, DD/aggregate caps, R:R, open-risk helpers | Complete | Yes | `Contracts.mqh`, symbol/account/position APIs | Open-risk quantification limited for positions without SL; rounding/edge cases require broker-specific validation |
| `Include/Core/StopsValidator.mqh` | Validates symbol properties, stops/freeze distances, entry/SLTP geometry, volume/margin/price constraints | Complete | Yes | `Contracts.mqh`, symbol/account APIs | Broker/symbol-specific stop/freeze semantics need runtime validation |
| `Include/Core/ExecutionPolicy.mqh` | Slippage/deviation, retcode classification (retryable/terminal/success/partial/unknown), bounded retry execution | Partially Complete | Yes | `Contracts.mqh`, `Logger.mqh`, `CTrade` | Retcode/filling behavior varies by broker; remainder/partial-fill policy needs per-broker validation |
| `Include/Core/ExecutionRouter.mqh` | Preflight pipeline (state/risk/stops/guards) and send path with reject reporting/logging | Complete | Yes | RiskEngine, StopsValidator, ExecutionPolicy, RejectSink, GuardEngine, StateStore, Logger, `CTrade` | Depends on accurate context/config refresh; integration correctness relies on callers providing current state |
| `Include/Core/OrderManager.mqh` | Order placement helpers (market/limit/stop/OCO-related operations) | Needs Verification | Needs Verification | `CTrade`, contracts/common types | Not directly included by `MoneyManager.mq5`; active-path usage vs. `ExecutionRouter`/UI flow needs verification |
| `Include/Core/PositionManager.mqh` | Position management operations (BE, trailing, partial/close, time-based exit) | Complete | Yes | MT5 position/trade APIs, common/contracts | Hardened: stops/freeze level checks, tick-size normalization, server retcode validation, TP preservation, SL-loosening prevention, maxMinutes<=0 guard, close-attempt debounce, last-error/retcode tracking. Behavior depends on broker mode (netting/hedging), symbol properties, and input configuration. |
| `Include/Core/StopLoss.mqh` | Stop-loss calculation methods/utilities | Needs Verification | Needs Verification | Symbol/indicator/common utilities | Direct wiring in current EA flow not confirmed from entry-point includes |
| `Include/Core/TakeProfit.mqh` | Take-profit calculation methods/utilities (incl. multi-TP helpers) | Needs Verification | Needs Verification | Symbol/indicator/common utilities | Direct wiring in current EA flow not confirmed from entry-point includes |
| `Include/Core/LotSizing.mqh` | Lot sizing method abstractions/utilities | Needs Verification | Needs Verification | Common/contracts/symbol data | `CRiskEngine` performs active sizing in entry path; overlap/usage of this module needs verification |
| `Include/Core/Logger.mqh` | File + print logging with rotation (`g_mmLog`) | Complete | Yes | File I/O, MT5 runtime | Log retention/size policy and filesystem behavior are environment-dependent |
| `Include/Core/RejectSink.mqh` | Unified reject sink interface/contract for guard and execution rejects | Complete | Yes | `Contracts.mqh` | Effective only when all reject producers route through sink (design requirement) |

## 3. Guards

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `Include/Guards/GuardEngine.mqh` | Guard registration/order, aggregate evaluation, preview/can-execute, news-state application, sink routing | Complete | Yes | `IGuard.mqh`, guard implementations, `RejectSink`, contracts | Correctness depends on timely/accurate `MM_GuardConfig` population |
| `Include/Guards/IGuard.mqh` | Guard interface and shared guard config/result types | Complete | Yes | `Contracts.mqh` | N/A (contract/interface) |
| `Include/Guards/PermissionGuard.mqh` | Terminal/EA/account/connection/symbol trading permission checks | Complete | Yes (via GuardEngine) | Terminal/account/symbol APIs | Runtime permissions can change dynamically; reflects checked state at evaluation time |
| `Include/Guards/PropGuard.mqh` | Prop-firm rule enforcement (DD/trades/position/consistency/weekend as configured) | Partially Complete | Yes (when prop enabled/configured) | PropFirm rules, config/context | Depth of consistency/profit-target/min-trading-days enforcement requires validation against firm-specific rules |
| `Include/Guards/ProtectionGuard.mqh` | Personal/protection limits (daily/weekly/monthly loss, profit lock, DD, trades/day, cooldown/consec loss) | Partially Complete | Yes | Protection/state/profile/config inputs | Weekly/monthly accounting completeness across resets/edges needs verification |
| `Include/Guards/NewsGuard.mqh` | News blackout/warn/block decisions based on availability/staleness/policy | Partially Complete | Yes | NewsManager state/config | Depends on news data quality/source freshness; live-provider integration is limited |
| `Include/Guards/SessionSpreadGuard.mqh` | Session allow/filter and spread max/warn checks | Complete | Yes | SessionManager, symbol spread/config | Session definitions/DST behavior should be validated for target markets |

## 4. Trade Lifecycle, State, Profiles

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `Include/Trade/TradeLifecycle.mqh` | Normalize `OnTradeTransaction` into events, dispatch listeners, record rejects, handle partial/full close semantics | Partially Complete | Yes | MT5 trade transaction structs, listener interfaces, logger/reject sink | `PositionStillOpen` now verifies position direction to prevent netting reversal false-positive; runtime validation on demo pending |
| `Include/State/StateStore.mqh` | Per-account JSON state persistence with lock, stale takeover, atomic save/bak, migration/fail-safe, baselines/peaks/counters | Partially Complete | Yes | `SimpleJson`, file I/O, contracts/time helpers | `IsOperational` fail-safe must be honored by all actions; schema/migration and full UI/template persistence coverage need continued verification |
| `Include/State/RecoveryEngine.mqh` | Restart recovery orchestration on top of `CStateStore`: backup fallback, corrupt-data handling, continuity-uncertain gating, explicit-resolution-only init; risk-reduction stays active in blocked state | Partially Complete | Yes (wired in `MoneyManager.mq5`) | `StateStore`, `Contracts`, `Logger` | Recovery execution evidence pending; runtime restart/backup-fallback validation on demo not yet run |
| `Include/Profiles/Profiles.mqh` | Default profiles, effective parameter resolution, active profile selection, per-account persistence, import/export | Complete | Yes | `SimpleJson`, file I/O, contracts/enums | Import/export paths and schema evolution require validation; UI exposure is subset of all profile fields |

## 5. Protection, Prop, News, Session

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `Include/Protection/Protection.mqh` | Tracks P/L, trades, streaks/cooldown, day-start and peak equity/balance, DD and remaining DD helpers | Partially Complete | Yes | Account/time APIs, state integration | Week key calculation fixed (anchors week 0 to first Monday of year). Weekly/monthly authoritative accounting and reset-policy edge cases need deeper validation; deterministic tests in `Tests/Phase14/Protection_Prop_Test.mq5`. |
| `Include/PropFirm/PropFirm.mqh` | Prop presets/rules, baseline sync, used/remaining Daily/Max DD calculations | Partially Complete | Yes (when prop enabled) | Rule structs, account/protection inputs | Preset/rule coverage and firm-specific semantics (consistency/targets/min days) are not fully validated |
| `Include/News/NewsManager.mqh` | News event storage, blackout checks, source/staleness tracking, safe offline behavior | Partially Complete | Yes | Time/symbol/config inputs, event storage | Live provider fetch/parsing/integration and resilience under real connectivity are incomplete |
| `Include/Session/SessionManager.mqh` | Trading session detection and session state for filtering/badges | Complete | Yes | Time/DST helpers, MT5 time APIs | Session boundary/DST correctness should be verified for broker/server time zones |

## 6. Statistics & Alerts

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `Include/Statistics/Statistics.mqh` | Lifecycle listener for trade tracking, KPI computation, open-risk estimation, per-mode views, CSV export | Partially Complete | Yes | Trade events, file I/O, account/mode context | `PositionStillOpen`/`SyncOpenFromPosition` direction guard prevents netting reversal mismatch; INOUT reversal starts new track; open-risk limited without SL |
| `Include/Alerts/Alerts.mqh` | Cooldowned alerts for guards/news/connection/DD events (log/popup/sound/push as configured) | Complete | Yes | `StatusLog`/logger hooks, MT5 alert APIs | Delivery depends on terminal settings/permissions (push/email/sound/popup availability) |

## 7. UI Modules

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `Include/UI/PanelShell.mqh` | Primary chart panel/drawer UI, controls, tabs, event routing, send/position/profile/stats actions | Complete | Yes | DragTool, PositionDragTool, PreviewOverlay, StatusLog, NewsBanner, SessionBadge, UiStrings, core modules | Object-based UI complexity; usability/accessibility refinements remain (roadmap) |
| `Include/UI/DragTool.mqh` | Interactive Entry/SL/TP planning lines, buy/sell/pending intent, sizing inputs, templates/hooks, plan build | Complete | Yes | Chart objects/events, contracts, symbol data | Advanced UX (ATR snap, RR lock handles, richer visual modes) is limited/needs enhancement |
| `Include/UI/PreviewOverlay.mqh` | Live preview of lot/risk/RR/spread/type and guard/stops/risk feedback | Complete | Yes | RiskEngine, StopsValidator, GuardEngine, DragTool | Preview quality depends on current context/config and module accuracy |
| `Include/UI/PositionDragTool.mqh` | Select and manage open positions (drag SL/TP, BE, trail, partial/close) | Complete | Yes | Position/trade APIs, chart events, `PositionManager` patterns | Hardened: ApplyModify/MoveToBE/ApplyTrailOnce/PartialClose/CloseSelected now check stops/freeze levels, normalize to tick size, validate retcodes, validate percent (0<pct<100), validate remaining volume, preserve TP. Multi-position/hedging workflows and confirmations require runtime validation. |
| `Include/UI/StatusLog.mqh` | Central reject/status log surface implementing `IRejectSink`; forwards guard alerts | Complete | Yes | RejectSink, Alerts, UI strings | Log/history presentation is lightweight (not a full persistent audit UI) |
| `Include/UI/NewsBanner.mqh` | Chart banner for news state/source/staleness/blackout messaging | Complete | Yes | NewsManager, UiStrings | Message fidelity depends on news data availability and bilingual copy coverage |
| `Include/UI/SessionBadge.mqh` | Session indicator badge/label | Complete | Yes | SessionManager, UiStrings | Visual/UX polish may be needed |
| `Include/UI/UiStrings.mqh` | Bilingual EN/FA UI labels, messages, tooltips | Partially Complete | Yes | UI modules | Bilingual coverage/encoding consistency requires ongoing audit |
| `Include/UI/Panel.mqh` | Alternate/earlier panel implementation | Legacy | Not Used (by current `MoneyManager.mq5`) | UI/common dependencies (internal) | Retained in tree; not the active wired panel path—treat as legacy unless reintroduced intentionally |

## 8. Tests & Documentation Artifacts

| File path | Responsibility | Status | Actively used by EA | Dependencies | Known limitations |
|---|---|---|---|---|---|
| `Tests/Phase1Test.mq5` | Phase 1 scripted checks | Needs Verification | Not Used (runtime EA) | Project modules under test | Execution/evidence status not recorded in this task |
| `Tests/Phase2Test.mq5` | Phase 2 scripted checks | Needs Verification | Not Used (runtime EA) | Project modules under test | Execution/evidence status not recorded in this task |
| `Tests/Phase3Test.mq5` | Phase 3 scripted checks | Needs Verification | Not Used (runtime EA) | Project modules under test | Execution/evidence status not recorded in this task |
| `Tests/IntegrationTest.mq5` | Integration smoke checks across core subsystems | Partially Complete | Not Used (runtime EA) | Logger, guards, stats, prop/protection, stops, execution policy | Script coverage exists; automated Strategy Tester coverage is absent; execution evidence pending |
| `Docs/test-checklist.md` | Manual validation checklist | Complete | Not Used (runtime EA) | N/A | Manual process; not automated evidence |
| `Docs/phase1-test-results.md` | Phase 1 evidence template/log | Partially Complete | Not Used (runtime EA) | N/A | Marked pending/not executed in-file |
| `Docs/tech-debt.md` | Existing tracked debt/follow-ups (Phase 7/v1.0.0 context) | Complete | Not Used (runtime EA) | N/A | Must be preserved; may not include all newly audited items (see `Docs/TECHNICAL_DEBT.md`) |
| `Docs/architecture.md`, `Docs/contracts.md`, other phase docs | Architecture/contracts/phase history | Complete | Not Used (runtime EA) | N/A | Historical snapshots; current baseline is defined by source + this baseline set |

## 9. Summary Counts (by classification, module inventory rows above)

- **Complete:** 24
- **Partially Complete:** 15
- **Legacy:** 1
- **Not Used:** 0 (as sole classification; non-runtime docs/tests marked accordingly in context)
- **Needs Verification:** 6

> Counts are indicative for planning; use individual rows for authoritative status and caveats.
