# Phase 1.3 — Source Verification (Audit & Design-only)

**Project:** `D:\Amoozesh\programing\money managment`  
**Branch/HEAD:** `phase1-foundation` / `f6b4af8`  
**Date:** 2026-11-18  
**Scope:** Read-only source inspection and documentation. **No MQL5 source, existing contracts/docs (except new Phase 1.3 docs), or `MM_CONTRACT_VERSION` modified. No implementation. No tests executed.**  
**Authority:** `Docs/Design/DRAWDOWN_PERSISTENCE_CONTRACT_DESIGN.md` (Phase 1.2) vs current source; preserved audit findings D1–D10, A1–A5, R1–R9 remain authoritative as prior evidence.

> **Classification rule:** Items below are tagged **VERIFIED** (observed in source/docs), **ASSUMPTION** (plausible but not proven by inspected code), or **UNKNOWN/NOT PROVEN** where runtime/MT5 behavior cannot be confirmed from static inspection. No proposed decision is treated as user-approved.

---

## 1. Files Inspected

### 1.1 Prioritized runtime modules (requested)
| File | Purpose inspected |
|---|---|
| `Include/State/StateStore.mqh` | State schema, paths, lock/backup/atomic save/load, day keys, peaks/baselines, operational/fail-safe, migration handling |
| `Include/Protection/Protection.mqh` | Daily/total DD baselines, peaks, realized tracking, streaks/cooldown, limit checks, reset/init |
| `Include/PropFirm/PropFirm.mqh` | Prop rules/presets, baselines/history, consistency/profit target/trading days, DD refs |
| `Include/Trade/TradeLifecycle.mqh` | `OnTradeTransaction` normalization, deal mapping, reject sink, open/close/partial/INOUT, dedupe/reconciliation absence |
| `Include/Core/RiskEngine.mqh` | Risk basis, lot/risk calc, open-risk aggregation, DD budget consumption |
| `Include/Core/ExecutionRouter.mqh` | Preflight/send pipeline, state-operational gate, guard/risk/stops integration |
| `Include/Core/ExecutionPolicy.mqh` | Retcodes, retry/partial-fill policy, slippage application |
| `Include/Core/StopsValidator.mqh` | Stops/freeze/margin/price/volume/symbol checks |
| `Include/Core/LotSizing.mqh` | Legacy/aux lot sizing methods (present) |
| `Include/Core/OrderManager.mqh` | Order placement helpers (present) |
| `Include/Core/PositionManager.mqh` | BE/trail/partial/close/time-exit helpers |
| `Include/Core/Contracts.mqh` | `MM_CONTRACT_VERSION`, enums/structs, trade events, profile/template fields |
| `Include/Core/RejectSink.mqh` | Unified reject interface |
| `Include/Core/SimpleJson.mqh` | JSON builder/reader (present; limitations per docs) |
| `Include/Core/Logger.mqh` | Logging (present) |
| `Include/Guards/GuardEngine.mqh` | Guard orchestration, preview vs sink reporting, live config helpers |
| `Include/Guards/IGuard.mqh` | Guard config/state fields, weekly/monthly/pct fields |
| `Include/Guards/PermissionGuard.mqh` | Permission/connection/trade-allowed checks |
| `Include/Guards/PropGuard.mqh` | Prop limits/consistency/weekend checks |
| `Include/Guards/ProtectionGuard.mqh` | Daily/weekly/monthly loss, profit lock, DD, trades, cooldown/consec checks |
| `Include/Guards/NewsGuard.mqh` | News blackout/stale handling |
| `Include/Guards/SessionSpreadGuard.mqh` | Session/spread checks |
| `MoneyManager.mq5` | EA wiring, init/deinit/tick/timer/chart events, context refresh, day reset, deal handling, save/peak triggers |

### 1.2 Supporting/runtime-adjacent modules
| File | Purpose inspected |
|---|---|
| `Include/Statistics/Statistics.mqh` | Trade/event aggregation, partial/finalize, open risk, KPIs, CSV |
| `Include/Profiles/Profiles.mqh` | Profile records/persistence, active selection, import/export |
| `Include/News/NewsManager.mqh` | News data/staleness/blackout source behavior |
| `Include/Session/SessionManager.mqh` | Session determination (server/GMT usage not exhaustively traced here) |
| `Include/Utils/Common.mqh` | Shared enums/structs/helpers (`SPropFirmRules`, `DD_FROM_*`, normalize, `DetectAccountType`, account currency) |

### 1.3 Tests inspected
| File | What it covers |
|---|---|
| `Tests/Phase1/StateStore_Test.mq5` | Init/save/reload, per-symbol/UI restore, v0→current migration path, account mode field |
| `Tests/Phase1/Lifecycle_Map_Test.mq5` | Request-failure reject dispatch/sink, partial-fill event, guard-reject record/dispatch; notes deal-add cases require live/demo |
| `Tests/Phase1/SimpleJson_Test.mq5` | Basic JSON round-trip fields (present, inspected by listing/context) |
| `Tests/Phase2/RiskEngine_Test.mq5`, `StopsValidator_Test.mq5`, `ExecutionPolicy_Test.mq5` | Phase 2 unit-style scripts (present) |
| `Tests/Phase3/GuardEngine_Test.mq5` | Guard engine behavior (present) |
| `Tests/IntegrationTest.mq5` | Integration script (present) |
| `Tests/Phase1/README.md` | Manual/stale-lock guidance (present) |

### 1.4 Contracts/docs inspected
`Docs/contracts.md`, `Docs/TECHNICAL_DEBT.md`, `Docs/tech-debt.md`, `Docs/MODULE_STATUS.md`, `Docs/DEVELOPMENT_BASELINE.md`, `Docs/DEVELOPMENT_ROADMAP.md`, `Docs/phase1-test-results.md`, `Docs/phase2-prep.md`, `Docs/phase2-implementation.md`, `Docs/phase3-implementation.md`, `Docs/phase4-implementation.md`, `Docs/phase6-implementation.md`, `Docs/phase7-implementation.md`, `Docs/architecture.md`, `Docs/getting-started.md`, `Docs/test-checklist.md`, `Docs/simplejson-limitations.md`, `Docs/SKILLS_CATALOG.md`, `Docs/Design/DRAWDOWN_PERSISTENCE_CONTRACT_DESIGN.md`. Additional files present in repo listing were not exhaustively read line-by-line but noted where relevant (`CHANGELOG.md`, `README.md`, `CORE ENGINE.txt`).

**Not executed:** MetaEditor compile, MT5/Strategy Tester, demo/live validation, or any project test scripts in this phase (VERIFIED by process: no execution performed).

---

## 2. Source-Level Verified Findings

### 2.1 StateStore — persistence, identity, time, save/load, durability

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| S-01 | `Include/State/StateStore.mqh` / `CStateStore::Init` | :105-117 | State identity/path keyed by `login` only: `base="state_"+login`, files under `MoneyManager` (FILE_COMMON). No server/mode/profile binding in path or validation. | Conflicts with U-11 (bind Login+Server+AccountMode+Profile). | Wrong-context restore possible if files copied/shared or context changes (C7-class risk, R9). |
| S-02 | `CStateStore` fields / `Save`/`Load` | :26-59, :191-219, :261-303, :308-341 | Persisted v1: `version, login, accountMode, activeProfileId, activeTemplateId, tradesDay/Week/Month, dayKey/weekKey/monthKey, lastResetServer, timeFallback, dayStartBalance, dayStartEquity, peakEquity, peakBalance, ui.*, symbolCount, sym.*`. No realized daily PnL components, no streaks, no cooldown, no breach/lockout flags, no prop block/history/reset metadata, no cashflow ledger, no HWM dirty/durable markers, no baseline capture status, no lifecycle/deal checkpoints. | Conflicts with D3,D5,D9,D10 and Phase 1.2 §3.1,§3.3,§3.4,§3.5,§3.7,§5 (U-05..U-10,U-12,U-15,U-16). | Restart/enable can lose protective and accounting state (R1,R2,R6). |
| S-03 | `EffectiveServerTime`, day/week/month keys | :60-69 | Prefers `TimeTradeServer()`, fallback `TimeCurrent()` sets `m_timeFallback=true`. Keys: day `yyyymmdd`, month `yyyy*100+mon`, week `yyyy*100 + (day_of_year/7)` (coarse). | Conflicts with U-08/U-09 (single authoritative trading-day service, configurable boundaries, persisted `tradingDayId`, valid-day semantics). Week key simplistic vs configurable prop boundaries. | Boundary/reset misalignment possible; not configurable for prop firms. |
| S-04 | `Save` | :176-241 | Blocks save only if `!m_operational` (:178). Acquires lock (:179), best-effort `Backup()` (:180) then warns on fail but continues (:181). On day-key change resets `m_tradesDay` and sets `m_dayStartBalance/Equity` to current (:185). Calls `EnsureBaselines()` (:189). Writes tmp, `FileDelete(dst)` then `FileMove(tmp→dst)`; on move fail does direct write fallback and deletes tmp (:221-238). No checksum/verify, no fsync equivalent, no dirty marker, no retained migration/original artifacts beyond single `.bak`. | Conflicts with D8, U-12, U-16/§3.3 (durability/save-on-new-high guarantee, commit verification), U-17. `EnsureBaselines` during save can bump peaks to now (:98-99) — problematic if restoring semantics. | Crash/power-loss windows (R5); HWM/new-high not durably guaranteed on change; last-good history limited. |
| S-05 | `Backup` | :159-174 | Copies current state file to single `.bak` (overwritten). No rotation/retention of prior-good versions or pre-migration originals. | Conflicts with U-12/UR-10. | Limited forensic/recovery options. |
| S-06 | `Load` | :243-303 | Missing file => initializes defaults from current balance/equity/peaks and calls `Save()`; operational set to save result (:248-256). Reads content; treats `ver<=0` as 1; migrates `ver<MM_CONTRACT_VERSION` forward by setting version only (no field transforms logged as lossy-flag schema beyond info) (:261-267); `ver>MM_CONTRACT_VERSION` => `operational=false`, fail-safe, no overwrite (:268-273). On day-key change resets day trades and sets day-starts to current (:296). Calls `EnsureBaselines()` (:300) which can bump peaks to current (:98-99). **No attempt to restore `.bak` on parse/missing-key/corruption, no checksum/semantic integrity validation, no `requiresManualReview` state.** | Conflicts with D4,D7,U-17,§6 (fail-safe on disagreement/corruption, `.bak` recovery, no silent rebaseline), U-16 (strict HWM restore). | Corrupt/partial content may yield defaults/operational mis-state; peaks/baselines can be loosened or reset to now (R1,R4,R9). |
| S-07 | `EnsureBaselines` / `SyncPeaks` / getters | :91-100, :336-340 | Seeds missing baselines/peaks from current and sets `peak=max(peak,current)` for equity/balance (:98-99). `PeakEquity/PeakBalance` call `EnsureBaselines()`; `SyncPeaks()` public. | Conflicts with U-16 (strict restore; upward update only after verified identity/integrity/policy). | Can mutate HWM upward without durability/verification semantics; can mask missing persisted state. |
| S-08 | Locking | :79-89, :119-157 | Bounded retries, stale takeover by local age `> staleSec` (default 30) deleting lock (:137-145), writes owner/chart/ts/srv/pid (:130). No heartbeat/lease identity hash, no explicit "read-only when locked by other writer" enforcement in API, no bound-identity in lock payload. | Conflicts with §3.10 multi-instance single-writer/read-only requirement (UR context). | Concurrent writers/races possible in edge cases; no safe observer mode contract. |
| S-09 | `IsOperational` | :333 | Exposed getter used by router preflight (verified) but store can be `operational=true` after default-init save path; no integrity/review flags. | Conflicts with U-17/§6 richer fail-safe states (`requiresManualReview`, degraded, hwmDirty). | Operational gate narrower than proposed safety model. |

### 2.2 Protection — runtime baselines, DD, daily realized, streaks/cooldown

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| P-01 | `CProtection::Init` | `Include/Protection/Protection.mqh:26-35` | Resets start/day-start/peaks to current, zeros daily profit/loss/trades/streaks/cooldown. | Conflicts with D1–D4 and §7 restore-before-init (must not clobber restored state). | Restart/enable can erase protective history. |
| P-02 | `NewDay` | :37-46 | Sets day-start balance/equity to current, zeros daily profit/loss/trades, keeps/bumps peaks. | Day boundary authority and `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus` absent (U-08, §3.4). | No provable exact boundary capture semantics. |
| P-03 | `SyncPeaks` / accessors | :47-51, :65-67 | Monotonic up to current equity/balance only. | U-16 strict durable restore and controlled catch-up. | Can advance HWM without persistence guarantee. |
| P-04 | `RecordTrade` | :52-57 | Per-call signed `profit`: `>0` adds to `m_dailyProfit`, resets losses/wins accordingly; `<0` adds to `m_dailyLoss`, increments losses; `==0` changes no streak but increments `m_tradesToday`. | U-07 requires net closed-trade lifecycle outcome, `eps_pnl`, persistence, defined resets/scope; no dedupe. | Per-deal/per-call counting can misrepresent lifecycle outcomes and double-count on replays (R2,R8). |
| P-05 | Daily metrics | :59-78, :87-93 | `DailyLossPct/ProfitPct` default ref day-start balance; `RemainingDailyDDMoney` uses day-start balance minus `m_dailyLoss`. | U-03/U-04/§3.2 mandatory numerator/denominator coupling and policy selection; U-05 profit ref explicit/configurable. | Fixed coupling/default differs from proposed default equity-snapshot enforcement. |
| P-06 | Max DD metrics | :79-85, :94-105, :120-128 | `CurrentDrawdownPct` = `(peakEquity-eq)/peakEquity`; `RemainingMaxDDMoney` uses `peakEquity` or `startBalance` by `fromEquity`; `CheckMaxDrawdown` mixes personal `maxDDPercent` vs trailing peak and prop `ddReference` vs peak/start. | U-02/U-03 explicit static/trailing model + unambiguous refs. | Ambiguous/overloaded semantics (C3,R7). |
| P-07 | Cooldown/limits | :107-141 | `CheckConsecutiveLoss` sets cooldown `TimeCurrent()+cooldownMinutes*60` and auto-clears after expiry (:133-136). `CheckCooldown` time-based. Limits use `>=` comparisons in places (:109, :112, :122, :126, :129). | U-15 daily/total restriction persistence and clear rules; U-13 epsilon/strictness; cooldown time authority should align with U-08. | Auto-clear and non-persisted states can weaken protection (D3,D5,R2). |
| P-08 | Missing state | entire class | No persistence hooks, no restore API, no breach/lockout flags object, no weekly/monthly realized accounting fields. | D3,D5,§5 schema. | Not restart-safe for required risk state. |

### 2.3 PropFirm — rules, baselines, history, accounting

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| PR-01 | `CPropFirm::Init/Enable` | `Include/PropFirm/PropFirm.mqh:12-13` | `Init` sets baselines to current and clears history; `Enable` sets baselines to current and enables. | D2,D9,§7/§3.7: must not overwrite restored/persisted prop state except explicit reset. | Restart/enable loses prop baselines/history (R6). |
| PR-02 | Presets | :17-28 | FTMO/MFF/FundedNext/The5ers hardcoded values (`ddReference`, limits, targets, min days, consistency, etc.). | §3.7 requires versioned, auditable, configurable governance and no unverified hardcoded assumptions treated as truth. | Template values may diverge from real/updated firm contracts; not auditable as selected/effective rule source. |
| PR-03 | `CheckConsistency` / history | :29-38, :39-47 | Consistency uses in-memory `m_dailyProfits[]`; `RecordTradingDay` pushes `dayProfit` (caller passes `g_prot.DailyProfit()` in EA) and increments `m_tradingDays` when local `dt.day` changes via `static int lastDay` (:45-46). No persisted `tradingDayId`, no idempotent once-per-day guard by authoritative key, not restart-safe. | U-06,U-09,§3.1.4,§3.7. | Consistency/min-days can miscount or reset (R6). |
| PR-04 | Profit target | :50-55 | `(ACCOUNT_BALANCE - m_startBalance)/m_startBalance*100` using in-memory `m_startBalance`. | U-06 and baseline persistence/governance. | Restart can reset reference. |
| PR-05 | DD helpers | :85-120 | `DailyLossRef/MaxDDRef` choose day-start or peak/start by `m_rules.ddReference`; remaining/used computed from provided args. No explicit static-vs-trailing model field; no persistence. | U-02/U-03/UR-01, D10. | Semantics depend on caller and preset; restart-unsafe. |
| PR-06 | Position size/correlation | :56-80 | Max position size rough notional; correlation placeholder (base-currency count). | Not core to DD/persistence but indicates rule completeness limits (documented behavior). | May not enforce firm rules accurately (ASSUMPTION of intent). |

### 2.4 TradeLifecycle — deal normalization, aggregation gaps, dedupe/reconciliation

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| L-01 | `CTradeLifecycle::OnTradeTransaction` DEAL_ADD | `Include/Trade/TradeLifecycle.mqh:110-158` | Selects history deal; processes BUY/SELL deal types; maps IN→OPEN, OUT→CLOSE/PARTIAL_FILL via `PositionStillOpen`, INOUT→CLOSE/PARTIAL_FILL with `reasonCode "INOUT"` and comment noting reversal/netting component may be separate deal (:146-151). Emits per-deal event with deal profit/commission/swap/volume/price. | §3.1,§3.5 require lifecycle-level aggregation, unique-deal dedupe, final outcome on flat, hedging/netting decomposition, no per-deal-as-trade. | Per-deal stream cannot by itself produce correct lifecycle net/streak/final outcomes. |
| L-02 | No dedupe / no reconciliation | entire class | No applied-deal watermark/set, no idempotency guard on `trans.deal`, no restart/history reconciliation, no lifecycle state store. | §3.1.2, §3.5.2 (duplicate prevention, restart reconciliation). | Replays/missed events can double-count or lose attribution (R8 risk). |
| L-03 | Request/modify handling | :159-202 | REQUEST non-success (except done/placed/partial) recorded to reject sink; DONE_PARTIAL emits PARTIAL_FILL event; order/position updates emit MODIFY. | Reject routing aligns with contract intent; partial-fill semantics limited to request result. | Adequate for execution rejects but not for full lifecycle accounting. |
| L-04 | `PositionStillOpen` | :41-53 | Checks ticket/position by id and symbol fallback. | Heuristic; netting/hedging edge cases depend on broker/MT5 semantics (ASSUMPTION: may be insufficient in all modes). | Misclassification of partial vs close possible in some modes (aligns with TD-02). |

### 2.5 EA (MoneyManager.mq5) — wiring, day reset, peaks, deal recording, guards, save triggers

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| E-01 | `OnInit` | `MoneyManager.mq5:233-283` | `g_store.Init()` then warns on fail but continues (:236); inits alerts/guards/router/profiles/positions/protection; `g_prot.SyncPeaks(); g_store.SyncPeaks()` (:248-249); inits news/session/stats/lifecycle listener; if prop enabled loads preset and `g_prop.Enable(r)` and `g_prop.SyncBaseline(...)` (:256-259) else `g_prop.Init()` (:261). Sets `g_lastDay` from `TimeCurrent()` (:278). **No restore-hydrate of protection/prop from persisted risk state.** | Conflicts with §7 restore-before-init, D1–D5,D9,D10, U-16,U-17. | Protective state can be reinitialized despite persisted peaks/baselines. |
| E-02 | `OnTick` day reset | :301-312 | Day boundary by local `MqlDateTime(TimeCurrent()).day != g_lastDay` (:303-311): calls `g_prot.NewDay()`, `g_store.SyncPeaks()`, `g_store.Save()`. Separately `CStateStore::Save/Load` do server-key rollover and may reset day-starts to current (:185-189,:296-299 in store). | Conflicts with U-08/U-09/§3.4 single authoritative trading-day service and no-silent-delayed-as-exact capture. | Dual authorities and ambiguous baseline capture (D6,R3). |
| E-03 | Peak/sync cadence | :120, :169, :222, :248-249, :294, :307, :313, :381 | Frequent `SyncPeaks` on store/protection; `g_store.Save()` only on deinit (:295), local day reset (:308), and inside store operations (init/missing-file path). No save on every verified HWM increase. | Conflicts with §3.3 save-on-new-high and durable HWM guarantee. | New HWM between saves can be lost on crash/power loss/shutdown (R1). |
| E-04 | Deal handling | :362-383 | `OnTradeTransaction` forwards to lifecycle (:366). Separately on DEAL_ADD OUT/INOUT BUY/SELL computes `profit = DEAL_PROFIT+DEAL_COMMISSION+DEAL_SWAP` and calls `g_prot.RecordTrade(profit)` and prop `RecordTradingDay(g_prot.DailyProfit())` (:368-378). On IN BUY/SELL calls `g_store.SyncPeaks()` (:379-382). No deal-id dedupe, no lifecycle aggregation, no attribution by trading-day id beyond current runtime state. | Conflicts with §3.1,§3.5,U-05..U-07,U-09. | Double-count/replay risk if events re-delivered; per-deal accounting vs lifecycle outcomes. |
| E-05 | Guard/risk context | :103-151, :153-223 | `RefreshRiskContext` builds context from `g_prot` day-start/peaks/loss and prop/store fallbacks; computes remaining daily/max DD via prop or protection helpers; `openRiskMoney` from `g_stats.CalcOpenRiskMoney(InpMagic,"")` (:150). `RefreshGuardConfig` sets limits from profiles/inputs and current pct values from protection/prop; news/session/spread/live spread filled; **`weeklyLossPct` and `monthlyLossPct` are never assigned** (inspected: only limit fields set at :160-161, no pct assignments). | Conflicts with accurate weekly/monthly enforcement (TD-04 context), U-03/U-04 denominator/model unification. | `ProtectionGuard` weekly/monthly blocks cannot trigger from live pct (remain default 0) — VERIFIED behavior gap. |
| E-06 | State-operational preflight | router :84-86; EA continues init on store init fail | Router blocks send when store non-operational. EA prints warning if `g_store.Init()` fails but does not abort init or force a global non-operational trading posture beyond store/router state (:236). | U-17/§6 stronger fail-safe on integrity/identity issues not fully represented. | Possible windows where UI/logic runs with degraded persistence assumptions (needs runtime verification). |

### 2.6 Guards, execution, risk — enforcement paths

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| G-01 | `GuardEngine` | `Include/Guards/GuardEngine.mqh:62-87` | Priority order Permission→Prop→Protection→News→SessionSpread; `CanExecute` routes results to sink, `Preview` disables sink side-effects. | Sink routing concept aligns; values depend on cfg correctness. | Enforcement quality limited by cfg population (E-05). |
| G-02 | `ProtectionGuard` | `Include/Guards/ProtectionGuard.mqh:21-44` | Blocks on daily/weekly/monthly loss pct, daily profit lock, max DD pct, trades/day, cooldown, consec loss using `>=` thresholds. | U-13 epsilon/strictness; U-14 disabled-state representation (uses `>0` limit enable); U-15 persistence/clear semantics. | Weekly/monthly ineffective if pct not fed (E-05). |
| G-03 | `PropGuard` | `Include/Guards/PropGuard.mqh:21-56` | Checks prop trades/day, daily DD used, total DD used, max position size (rough notional), consistency (blocks when `propTodayProfitPct >= propConsistencyPct`), weekend warn. | Consistency/profit inputs and persistence not aligned with §3.1/§3.7; rule hardcoding upstream. | Prop-rule correctness depends on in-memory/preset data. |
| G-04 | `IGuardConfig` | `Include/Guards/IGuard.mqh:25-44,76-90` | Has `weeklyLossPct/monthlyLossPct` and limits, but defaults 0 and EA does not populate pct. | Weekly/monthly accounting gap. | Structural support exists, runtime wiring incomplete (VERIFIED). |
| G-05 | `ExecutionRouter::Preflight/Send` | `Include/Core/ExecutionRouter.mqh:80-125` | Gates on empty symbol, `STATE_NOT_OPERATIONAL`, risk blocked/invalid, stops invalid, guards `CanExecute`. Sends via execution policy/retry. | Correct high-level gate chain; cannot compensate for missing persisted/restored risk state. | Safe only relative to inputs provided. |
| G-06 | `RiskEngine` | `Include/Core/RiskEngine.mqh:56-258` | Basis: equity, day-start balance, or allowed DD (`min(remainingDailyDD, remainingMaxDD)` when provided). Computes per-lot risk incl. commission/swap option, caps by aggregate/open risk and DD budgets, floors to step, blocks if below min/invalid. Has its own `CalcOpenRiskMoney` scan; EA also injects `g_stats.CalcOpenRiskMoney` (:150 in EA). | Multiple open-risk sources possible; DD semantics depend on caller-provided remaining values (from protection/prop current behavior). | Consistency depends on unified authoritative inputs (Phase 1.2 goal). |

### 2.7 Statistics — lifecycle aggregation attempt (limited) and risks

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| ST-01 | `CStatistics` | `Include/Statistics/Statistics.mqh:199-302,353-359` | Tracks open trades by `positionId`/ticket/symbol; on OPEN stores/updates; on PARTIAL_CLOSE/INOUT aggregates realized components and reduces remaining/risk, finalizes when position no longer open; on CLOSE finalizes or records standalone. Uses `PositionStillOpen`/live sync. | Partial aggregation exists but is **not** wired as authoritative accounting for protection/prop/streaks; not deduped by deal id, not restart-reconciled, not bound to `tradingDayId`, and relies on event stream. | Helpful for KPIs/open-risk estimation but insufficient as source of truth for DD/protection (and can orphan/mis-aggregate per comments/edge cases). |
| ST-02 | Open risk | :361-399 | Computes remaining risk from tracked opens (syncs live) plus fallback scan of live positions excluding tracked `positionId`. | Does not include commission/swap in same way as trade outcome accounting; positions without SL contribute 0 in fallback. | Conservative in some cases, under-counting in others (no-SL). |

### 2.8 Profiles, account identity, prop templates

| # | File / class/function | Location (approx) | Current behavior (VERIFIED) | Conflict with Phase 1.2 design | Practical consequence |
|---|---|---|---|---|---|
| PF-01 | `CProfileManager` | `Include/Profiles/Profiles.mqh:137-143,155-159,174-215` | Persists per-login `profiles_<login>.json` (FILE_COMMON) with active id; sets active by mode; stores limits/news/spread settings and `MM_Profile` fields. No server binding. | U-11 identity binding and §3.7 prop governance metadata (profile/rule version, source, effective date, stage, audit trail) absent. | Profile/rule selection not fully auditable or bound to server identity. |
| PF-02 | Prop presets source | `Include/PropFirm/PropFirm.mqh:17-28` and `Include/Utils/Common.mqh:48-53` | Rule values and `ENUM_DD_REFERENCE` hardcoded in code structs/enums. | §3.7 no unverified hardcoded assumptions. | Must remain configurable/documented, not treated as verified firm truth. |

### 2.9 Tests and evidence state (documentation-verified)

| # | Source | Verified fact | Practical consequence |
|---|---|---|---|
| T-01 | `Tests/Phase1/StateStore_Test.mq5` | Covers basic save/reload, per-symbol, UI, v0 migration field presence; does not cover `.bak` restore on corruption, integrity flags, HWM durability, daily realized/streak/cooldown persistence, identity binding, or concurrent access. | Persistence safety claims unproven for Phase 1.2 requirements. |
| T-02 | `Tests/Phase1/Lifecycle_Map_Test.mq5` | Covers request reject, partial fill, guard reject; explicitly notes deal-add cases require live/demo. No lifecycle aggregation/dedupe/restart reconciliation tests. | Lifecycle PnL/aggregation unverified. |
| T-03 | `Docs/phase1-test-results.md` | Template largely pending/TBD (hedging/netting, restart, migration edge cases, stale lock, server-time fallback, deal add/partial/close). | No recorded execution evidence for critical DD/persistence scenarios. |
| T-04 | `Docs/contracts.md`, `Docs/TECHNICAL_DEBT.md` | StateStore/TradeLifecycle contracts and TD items (TD-02, TD-04, TD-05, TD-17 etc.) acknowledge gaps (hedging/netting parity, weekly/monthly/prop accounting, persistence/gating/migration, server-time fallback surfacing). | Known limitations align with D1–D10/R1–R9 and Phase 1.2 corrections. |

---

## 3. Critical Financial Verification (A–F)

### A. Trade lifecycle accounting (commissions, swap, fees, partials, INOUT, hedging, netting)

- **VERIFIED current representation:** EA records **per qualifying close deal** `DEAL_PROFIT+DEAL_COMMISSION+DEAL_SWAP` into `CProtection::RecordTrade` (`MoneyManager.mq5:368-378`); TradeLifecycle emits **per-deal** events with same components (`TradeLifecycle.mqh:121-157`); Statistics aggregates per `positionId` from event stream for KPIs/open-risk (`Statistics.mqh:236-302`). No source sums all lifecycle deals into a single final outcome for protection/prop/streak enforcement.
- **VERIFIED gaps:** no deal-id dedupe, no restart reconciliation, no explicit lifecycle final-outcome event consumed by protection/prop. INOUT marked but successor/open component handling depends on separate deals and current heuristics.
- **Double-counting risk:** **HIGH** if deal events replay/duplicate or if per-deal recording is combined naively with future aggregation without idempotency (VERIFIED absence of dedupe). Current per-deal-only recording also **cannot represent** "one complete trade outcome" for partial/multi-deal/hedging/netting as required by §3.1/§3.5.
- **Feasibility of proposed aggregation:** **POSSIBLE in design** if a unique deal-id idempotent ledger + lifecycle keying + reconciliation (and MT5 history access where needed) are implemented; **BLOCKED_BY_SOURCE today** because required persisted checkpoints/keys and aggregation logic do not exist. MT5 hedging vs netting semantics and history completeness remain environment-dependent (ASSUMPTION/needs runtime evidence, aligns with TD-02, `Docs/contracts.md` netting note).

### B. Daily Drawdown (numerator/denominator compatibility; underestimation)

- **VERIFIED current formulas:** `CProtection::DailyLossPct`/`RemainingDailyDDMoney` use `m_dailyLoss` vs day-start **balance** by default (:69-76,:87-93). `DailyLoss` accumulates `-profit` on negative `RecordTrade` calls (:55) — realized/call-based, not equity-snapshot. Prop daily refs can use day-start equity or balance depending on `DD_FROM_*` (`PropFirm.mqh:85-112`). Guard `dailyLossPct` fed from `g_prot.DailyLossPct(dayStartBal)` (`MoneyManager.mq5:170`).
- **Incompatibilities vs §3.2:** mandatory coupling (equity-snapshot numerator to DayStartEquity, etc.), `REALIZED_ONLY` with explicit `RealizedRiskRef`, and `WORST_OF` component-wise evaluation are **not implemented**. Config cannot express/validate these couplings.
- **Underestimation scenarios (VERIFIED/derivable from current behavior):**
  - Equity-snapshot drawdown (`DayStartEquity - CurrentEquity`) can exceed balance/realized-only measure during floating loss; current default balance-realized path would **not capture** that if a prop/rule requires equity-snapshot (R7,R8).
  - Restart/init/reset can zero `m_dailyLoss`, streaks, or rebase day-starts to now (P-01,E-01,E-02,S-06) causing **material underestimation** (D3,D4).
  - Weekly/monthly guard pct never populated (E-05) => weekly/monthly limits unenforced even if configured.
  - Per-deal recording without dedupe/lifecycle attribution can misstate realized totals (over or under) on edge cases.

### C. HWM durability (save/restore lifecycle, loss paths, dirty-state blocking)

- **VERIFIED save/restore:** peaks persisted as `peakEquity/peakBalance` in state file on `Save()`; `Save()` occurs on `OnDeinit` (`MoneyManager.mq5:295`), local day reset (`:308`), and store init/missing-file/load-side saves (`StateStore.mqh:253` and load paths). `SyncPeaks` is frequent but **does not trigger save**. Backup is single overwritten `.bak`; atomicity has delete-before-move and fallback direct write (S-04,S-05). Load does not restore `.bak` on corruption and can bump peaks to current via `EnsureBaselines` (S-06,S-07).
- **Loss paths (VERIFIED/credible):** crash, power loss, terminal kill, or failed write between HWM increase and next save can lose the new HWM (no save-on-new-high, no dirty/commit marker). Power loss during save has temp/delete/rename windows (S-04).
- **New risk while dirty/invalid:** **no dirty HWM concept exists**; router blocks only on `STATE_NOT_OPERATIONAL` (store future-version/explicit) not on unsaved HWM or integrity/review conditions. Therefore, **no path currently blocks risk-increasing actions because "latest HWM cannot be durably saved"** — direct conflict with §3.3.
- **Restore correctness:** persisted peaks can be overwritten/ignored by init/sync-to-current order and `EnsureBaselines` (E-01,S-06,S-07,P-01,P-03) — aligns with D1.

### D. Trading-day baseline (offline at boundary, tick absence, reconstructability)

- **VERIFIED behavior:** EA local-day reset uses `TimeCurrent().day` on tick (`MoneyManager.mq5:303-311`) and captures day-starts via `CProtection::NewDay()` (current account values). Store uses server `DayKey` on `Save/Load` and resets day-starts to **current** on key change (`StateStore.mqh:185-189,296-299`). No `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus`.
- **Offline at scheduled boundary / no midnight tick:** next tick/load/save evaluates "now" and sets baselines to current at that later time (VERIFIED from code paths) — effectively a delayed capture **labeled/treated implicitly**, not explicitly marked delayed vs exact.
- **Exact historical equity reconstructability:** **NOT PROVEN from available source/logic.** No code reconstructs historical intraday equity at boundary; MT5 provides live `AccountInfoDouble(ACCOUNT_EQUITY)` now but historical equity-at-time is not generally derivable without persisted snapshots/ticks (ASSUMPTION grounded in MT5 API usage seen: only current equity reads). Therefore, exact boundary equity **cannot be reliably reconstructed** by current implementation and must be treated as unavailable in such cases (consistent with §3.4).

### E. Account identity binding (login, server, mode, profile)

- **VERIFIED:** `CStateStore::Init` uses `AccountInfoInteger(ACCOUNT_LOGIN)` only for file naming (`StateStore.mqh:105-117`); `accountMode` and `activeProfileId` stored but not enforced as identity-binding gate on load. `CProfileManager` stores per-login profiles (`Profiles.mqh:137-143,174-215`). No `ACCOUNT_SERVER`/company binding found in inspected persistence paths (grep showed no server binding usage).
- **Conflict:** fails U-11. Practical risk: state/profile applied in wrong account/server/mode/profile context.

### F. Prop-firm rules (generic protection vs configurable prop-specific)

- **VERIFIED separation in code:** generic protection in `CProtection`/`ProtectionGuard`; prop-specific in `CPropFirm`/`PropGuard` and presets (`PropFirm.mqh:17-28`, `PropGuard.mqh`). EA combines via config/context (`MoneyManager.mq5:153-223`).
- **VERIFIED issue:** presets embed specific numeric rules (`DD_FROM_EQUITY/BALANCE`, targets, min days, consistency) as hardcoded templates; not versioned/audited/effective-dated as selected firm truth. Prop-firm contracts vary (stated requirement) — **must remain configurable and documented**, not hardcoded as verified (conflicts with §3.7).

---

## 4. Critical Conflicts (Phase 1.2 vs Current Source)

| ID | Conflict | Evidence | Impact |
|---|---|---|---|
| C-01 | No restore-before-init; init/enable/sync can rebaseline to current | `CProtection::Init` P-01, `CPropFirm::Init/Enable` PR-01, EA `OnInit/SyncPeaks` E-01,E-03, Store `Load/EnsureBaselines` S-06,S-07 | R1,R2,R6,R9 |
| C-02 | Dual day-boundary authorities and no boundary capture status | EA local day E-02, Store server keys S-03/S-06, no `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus` | D6,R3,§3.4 noncompliance |
| C-03 | Daily/Total DD semantics implicit; no mandatory numerator/denominator coupling; default differs | P-05,P-06,PR-05,E-05,§3.2 | R7,R8, underestimation risk |
| C-04 | Realized accounting is per-deal, not lifecycle-aggregated; no dedupe/reconciliation | E-04,L-01,L-02,ST-01 | §3.1/§3.5 noncompliance, double/mis-count risk |
| C-05 | HWM not durably save-on-new-high; no dirty/commit state; no block on unsaved HWM | E-03,S-04,S-06, no router/guard condition | R1,§3.3 noncompliance |
| C-06 | Persistence coverage gaps (realized components, streaks, cooldown, breaches, prop history/reset, cashflow, governance, lifecycle checkpoints) | S-02,P-08,PR-01..PR-05 | D3,D5,D9,D10,R2,R6 |
| C-07 | Integrity/fail-safe weak: no `.bak` restore on corruption, no review state, missing-file seeds current | S-06,S-09,E-01 | D7,R4,U-17 |
| C-08 | Identity binding insufficient (login-only) | S-01,PF-01 | U-11 violation |
| C-09 | Versioning coupled (store vs `MM_CONTRACT_VERSION`), no separate persistence schema v2 | S-06, `Contracts.mqh:8`, `Docs/contracts.md` | U-01 |
| C-10 | Weekly/monthly loss pct not populated though limits/config exist | E-05,G-02,G-04, `Profiles.mqh` fields | TD-04/enforcement gap |
| C-11 | Prop presets hardcoded, not versioned/audited rule-source governance | PR-02,PF-02 | §3.7 |

---

## 5. Practical Consequences (summary)

- **Safety:** protective DD/streak/cooldown/lockout/prop baselines can reset or understate after restart, boundary misalignment, missing persistence, or HWM loss (R1–R3,R6).
- **Correctness:** per-deal (not lifecycle) accounting, missing dedupe/reconciliation, and numerator/denominator ambiguity can mis-measure realized PnL, daily DD, streaks, consistency, and min-trading-days (R7,R8,§3.1–§3.5).
- **Durability:** single `.bak`, delete-before-move/fallback writes, and no save-on-new-high leave crash windows and limited recovery (R5,§3.3).
- **Governance:** identity and prop-rule provenance insufficient for auditable, firm-specific, multi-context operation (U-11,§3.7).
- **Verification state:** critical scenarios in `Docs/phase1-test-results.md` remain pending; tests inspected do not cover Phase 1.2 safety requirements (T-01..T-04).

---

## 6. Implementation Blockers (evidence-based)

| Blocker | Why blocking |
|---|---|
| **No user approval (U-01..U-17, UR items, UR-13/UR-14 resolution)** | Design/contract freeze and behavior choices (models, denominators, refs, catch-up, recovery, retention, aggregation keys) remain open; implementing now risks rework and unsafe defaults. |
| **Persistence schema + migration not designed/approved as implementable spec** | S-02/C-06/C-09 require coordinated schema v2, lossy-field handling, identity binding, and artifact retention. |
| **Restore-before-init & authoritative calculation path absent** | C-01/C-03/C-04 require architectural wiring changes across EA/Protection/PropFirm/StateStore/guards/stats. |
| **HWM durability mechanism absent** | C-05 requires save-on-new-high/commit/dirty/block semantics and crash-safe protocol decisions. |
| **Hedging/netting/lifecycle semantics unverified in runtime** | A/TD-02: MT5 behavior must be evidenced before claiming correct aggregation. |
| **Incomplete history / cashflow / server-binding behavior undefined in code** | D, E, F show no current mechanisms; policies and thresholds (UR-04,UR-06,UR-07,UR-10,UR-12) unresolved. |

---

## 7. Contract-Freeze Readiness

**NOT READY for contract freeze.**

Rationale (VERIFIED): core protective/persistence behaviors in source conflict with Phase 1.2 requirements (C-01..C-11); multiple unresolved decisions (UR-01..UR-14 including numbering ambiguity) affect formulas, schema, and enforcement; required runtime evidence (hedging/netting, crash/HWM durability, restart/boundary, history completeness) is absent/pending. Freeze is appropriate only after: (1) explicit user decisions on §13/UR items, (2) updated design/contracts aligned to approved choices, and (3) minimum evidence plan for high-risk semantics.
