# Drawdown & Persistence Contract Design (Phase 1.2)

**Status:** PROPOSED-BY-DESIGN — pending explicit user approval (no decisions user-approved)  
**Date:** 2026-11-18  
**Scope:** `D:\Amoozesh\programing\money managment` (Money Manager MT5 EA)  
**Branch/HEAD:** `phase1-foundation` / `f6b4af8`  
**EA/Contract versions (current):** `MoneyManager.mq5` `#property version "1.70"`, `MM_VERSION "1.0.0"` (`Include/Utils/Common.mqh:61`), `MM_CONTRACT_VERSION 1` (`Include/Core/Contracts.mqh:8`)  
**Revisions:** Phase 1 draft → Phase 1.1 (U-01..U-17 incorporated for review) → **Phase 1.2 (final financial corrections applied to this document; design-only).**

> **Constraint (design-only):** No MQL5 source files, existing formulas, existing contracts/docs (other than this design document), or `MM_CONTRACT_VERSION` modified. No implementation. No commit/push. No tests executed in this pass; no claim that tests passed. Original audit findings preserved (§1).

---

## 1. Evidence Base and Preserved Original Audit Findings

### 1.1 VERIFIED FACTS (source/docs)

| Area | Fact | Evidence |
|---|---|---|
| Contract version | `MM_CONTRACT_VERSION 1`, `version` fields on contracts; schema evolution requires bump + migration hook + fail-safe on future version | `Include/Core/Contracts.mqh:8`; `Docs/contracts.md` |
| State file set | Per-login `MoneyManager\state_<login>.{json,lock,bak,tmp}` (FILE_COMMON) | `Include/State/StateStore.mqh:109-115` |
| Persisted state (v1) | `version, login, accountMode, activeProfileId, activeTemplateId, tradesDay/Week/Month, dayKey/weekKey/monthKey, lastResetServer, timeFallback, dayStartBalance, dayStartEquity, peakEquity, peakBalance, ui.*, symbolCount, sym.*` | `CStateStore::Save/Load` `Include/State/StateStore.mqh:191-302,308-328` |
| Day/period rollover in store | `Save()` and `Load()` reset counters/day baselines when key differs vs effective server time; `Save()` sets `m_dayStartBalance/Equity` to current on day change | `Include/State/StateStore.mqh:185-189,296-299` |
| Time authority (store) | `EffectiveServerTime()` prefers `TimeTradeServer()`, falls back to `TimeCurrent()` and sets `m_timeFallback=true` with warnings | `Include/State/StateStore.mqh:64-69,183,294` |
| Peak maintenance (store) | `EnsureBaselines()` initializes missing baselines from current and bumps peaks up to current eq/bal | `Include/State/StateStore.mqh:91-100` |
| Locking | Bounded acquire/retry, stale takeover by local age > `staleSec` (default 30s), owner/ts logged | `Include/State/StateStore.mqh:119-151` |
| Backup/atomicity | `Backup()` copies state→`.bak` (best-effort), `Save()` writes `.tmp`, deletes dst, moves tmp→dst; on move fail does direct write fallback and warns; save blocked if `!m_operational` | `Include/State/StateStore.mqh:159-241` |
| Load behavior | Missing file → initialize from current account and `Save()`; sets operational to save result. Future version → `m_operational=false`, fail-safe, no overwrite. No load-time `.bak` restore/integrity validation for corrupt/missing-key content beyond JSON reader defaults | `Include/State/StateStore.mqh:243-303` |
| Operational gate | Store is non-operational on future version; `ExecutionRouter::Preflight` blocks on `STATE_NOT_OPERATIONAL` | `Include/State/StateStore.mqh:268-273,333`; `Include/Core/ExecutionRouter.mqh:84-86` |
| Protection runtime state | Tracks `m_startBalance, m_dayStartBalance, m_dayStartEquity, m_peakEquity, m_peakBalance, m_dailyProfit, m_dailyLoss, m_tradesToday, m_consecutiveLosses/Wins, m_cooldownUntil, rules` | `Include/Protection/Protection.mqh:8-21` |
| Protection init/reset | `Init()` resets all baselines/peaks/counters/streaks to current; `NewDay()` resets day baselines/loss/profit/trades, keeps overall peaks and bumps to current | `Include/Protection/Protection.mqh:26-46` |
| Protection recording | `RecordTrade` updates daily profit/loss, streaks, tradesToday per recorded call | `Include/Protection/Protection.mqh:52-57` |
| Protection DD/risk calcs | `DailyLossPct/ProfitPct` default ref day-start balance; `CurrentDrawdownPct` = `(peakEquity-eq)/peakEquity` (trailing equity peak); `RemainingDailyDDMoney` uses day-start balance; `RemainingMaxDDMoney` uses `peakEquity` or `startBalance` per `fromEquity`; checks mix personal/prop refs; `CheckConsecutiveLoss` sets cooldown and auto-clears on expiry | `Include/Protection/Protection.mqh:69-141` |
| Prop runtime state | Rules, `m_enabled`, `m_firstTradeDay`, `m_tradingDays`, `m_startBalance`, `m_peakEquity`, `m_dailyProfits[]`, `m_dailyCount` | `Include/PropFirm/PropFirm.mqh:7-11` |
| Prop init/enable/presets | `Init/Enable` set baselines from current and reset/clear history; presets FTMO/MFF/FundedNext/The5ers define mode/ddReference/limits/targets | `Include/PropFirm/PropFirm.mqh:12-28` |
| Prop calculations | Consistency, trading days, profit target, max position size (rough notional), correlation warning (placeholder), DD refs/used/remaining helpers | `Include/PropFirm/PropFirm.mqh:29-120` |
| EA wiring | EA inits store/protection/prop; sources DD/risk/guard mainly from `g_prot` with limited store fallback; local day reset via `TimeCurrent().day` on tick plus store day-key rollover; preflight gates on store operational | `MoneyManager.mq5` (inspected), prior audit; `Include/Core/ExecutionRouter.mqh:84-86` |
| **Realized deal capture (current, per-deal)** | On `TRADE_TRANSACTION_DEAL_ADD` + `HistoryDealSelect`, OUT/INOUT BUY/SELL: `profit = DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP` recorded to `g_prot.RecordTrade`; on qualifying IN entry only `g_store.SyncPeaks()` (no realized PnL). EA does **not** aggregate lifecycle-level outcomes and does **not** dedupe by deal id. | `MoneyManager.mq5:368-382` (verified this pass) |
| **TradeLifecycle implementation (current)** | Per-deal normalization/dispatch: IN→OPEN, OUT→CLOSE/PARTIAL_FILL (by `PositionStillOpen`), INOUT→CLOSE/PARTIAL_FILL with `reasonCode "INOUT"` (notes reversal/netting component may be separate deal), other→DEAL_ADD; emits REQUEST rejects/partial, ORDER/POSITION MODIFY. No deal deduplication, no restart reconciliation, no cross-deal/lifecycle PnL aggregation, no streak/consistency accounting. | `Include/Trade/TradeLifecycle.mqh` (verified this pass) |
| **Equity access (current)** | Live equity read via `AccountInfoDouble(ACCOUNT_EQUITY)`; balance via `AccountInfoDouble(ACCOUNT_BALANCE)` in multiple modules | `MoneyManager.mq5`, `StateStore.mqh`, `Protection.mqh`, `PropFirm.mqh` (verified) |
| Account identity (current) | State/login keyed by `AccountInfoInteger(ACCOUNT_LOGIN)`; no `ACCOUNT_SERVER`/company binding in state filename or load validation | `CStateStore::Init` `Include/State/StateStore.mqh:105-117`; `MoneyManager.mq5:235` |
| Independent math sanity | `Verify-Math.ps1` → 29 PASS, 0 FAIL (not MT5/runtime proof) | Prior execution |

### 1.2 PRESERVED ASSUMPTIONS (A1–A5)

- **A1:** `CStateStore`/`CProtection`/`CPropFirm`/EA integration points above are the authoritative sources for DD/persistence behavior in this branch.
- **A2:** `TimeTradeServer()` is the intended prop/operational time authority when available; `TimeCurrent()` is terminal-local fallback only.
- **A3:** Daily/prop "realized" components are derived from closed-deal accounting (`DEAL_PROFIT+COMMISSION+SWAP`) as currently fed by EA; open/floating exposure is equity-based at evaluation time.
- **A4:** `DD_FROM_EQUITY`/`DD_FROM_BALANCE` express reference series selection, but exact static-vs-trailing semantics for total DD must be frozen explicitly.
- **A5:** File-system semantics (FILE_COMMON, rename/delete atomicity, crash windows) are broker/terminal/OS dependent; design must be defensive.

### 1.3 PRESERVED ORIGINAL AUDIT DEFECTS (D1–D10)

| ID | Defect (verified, prior audit) |
|---|---|
| **D1** | Persisted HWM/peaks not restored into `CProtection` runtime in a way that survives init/reset; restart can understate max DD. |
| **D2** | Start/total-DD baselines not fully persisted/restored across `CProtection`/`CPropFirm`. |
| **D3** | Daily realized DD/profit, trades/streaks, cooldown not persisted. |
| **D4** | Day-start baselines not reliably preserved on same-day restart. |
| **D5** | DD-threshold breach/lockout state not persistent. |
| **D6** | Dual day-boundary/time authorities (local `TimeCurrent().day` in EA vs server `DayKey` in `CStateStore`, fallback `TimeCurrent()`). |
| **D7** | Corrupted/missing-key state can become operational defaults (no robust load-time `.bak` restore/integrity fail-safe except future-version gate). |
| **D8** | Save durability/atomicity gaps (delete-before-move, fallback write, `EnsureDir` no-op, init ordering). |
| **D9** | Prop baseline/history loss on restart/enable. |
| **D10** | No persisted prop DD reset timestamp/trading-day boundary metadata. |

### 1.4 PRESERVED RISKS (R1–R9)

- **R1:** Restart can reinitialize baselines/HWM to "now", understating max/daily DD and allowing over-risk (D1,D2,D4,D9).
- **R2:** Daily realized loss, streaks, cooldown, and lockouts can reset on restart, bypassing limits (D3,D5).
- **R3:** Split local/server day boundaries and `timeFallback` can mis-attribute a trade/day reset (D6).
- **R4:** Corrupted/partial/missing-key state may load as operational defaults without integrity fail-safe (D7).
- **R5:** Delete-before-move and fallback paths create crash/recovery windows (D8).
- **R6:** Prop baseline/history/reset-boundary loss breaks consistency/profit-target/min-days semantics across restarts (D9,D10).
- **R7:** Ambiguous "balance vs equity" and "static vs trailing" definitions can yield incompatible enforcement vs display vs prop rules.
- **R8:** Floating (unrealized) DD and realized DD can be double-counted or omitted depending on definition if not contractually separated.
- **R9:** Migration/restore order errors can overwrite valid persisted baselines with live values.

---

## 2. Decision Register U-01 through U-17 (updated)

> **Status labeling:** "Approved-by-proposal" = proposed default captured for user review. **NOT user-approved.** Final approval only in §13. Phase 1.2 clarifications are incorporated but remain proposed.

| ID | Proposed decision (as provided) | Approved-by-proposal default (Phase 1.2) | Verification vs current MQL5 | Conflict with current behavior | Notes / residual |
|---|---|---|---|---|---|
| **U-01** | Separately versioned persistence schema. Coordinate `MM_CONTRACT_VERSION` changes only when public contracts actually change. Propose version 2 if required. | `persistenceSchemaVersion=2` (proposed) for state; keep `MM_CONTRACT_VERSION=1` unchanged unless public/shared contracts change. Lifecycle/aggregation/HWM/cashflow/governance fields are state-schema concerns (persistence version) unless promoted to `Contracts.mqh`. | `StateStore` couples `version` to `MM_CONTRACT_VERSION` (`StateStore.mqh:191,261-276`). No separate schema version. | **Conflict:** conflated versioning. | Requires mapping rule and fail-safe for future schema. |
| **U-02** | Support both Static and Trailing Maximum Drawdown as explicitly selected models. | Explicit selectable `TRAILING_HWM` or `STATIC_INITIAL` per mode/profile/prop preset. | Trailing/mixed implicit logic (`Protection.mqh:79-128`, `PropFirm.mqh:102-120`). | **Conflict:** not first-class/selectable. | Preset mapping configurable per firm (UR-01). |
| **U-03** | Define separate, unambiguous Balance and Equity semantics for Daily DD and Total DD. | Separate explicit Daily ref series and Total ref series with model where applicable; never inferred from single flag. | Mixed/overloaded refs across protection/prop/EA. | **Conflict:** ambiguity (C3,R7,A4). | Per-rule independent refs. |
| **U-04** | Default daily enforcement to DayStartEquity versus CurrentEquity. Support alternative policies required by prop-firm rules. | **Default:** `EQUITY_SNAPSHOT` = `max(0, DayStartEquity - CurrentEquity)` measured against `DayStartEquity` denominator (mandatory coupling, §4.2). Alternatives configurable: `BALANCE_SNAPSHOT`, `REALIZED_ONLY`, `WORST_OF`. | Current default balance-referenced daily loss (`Protection.mqh:69-76,88-93`). | **Conflict:** default differs. | Prop rules may override. |
| **U-05** | Calculate realized daily PnL net of applicable trading costs. Explicitly define the denominator/reference for profit percentages. | Realized trading components net of deal costs (`DEAL_PROFIT+DEAL_COMMISSION+DEAL_SWAP`) aggregated at **lifecycle/deal-attribution** level with dedupe (§3.1, §3.5). `DailyProfitPct = RealizedDayProfit_net / ProfitRef * 100` with explicit configured `ProfitRef` (default proposed `DayStartBalance`). | EA records per close deal (`MoneyManager.mq5:374`), no lifecycle aggregation/dedupe. | **Partial conflict:** cost components present but aggregation/attribution incomplete. | Fees outside deal fields handled via cashflow/integrity (UR-12). |
| **U-06** | Default profit target and consistency calculations to realized closed-trade results, unless selected prop-firm rules specify otherwise. | Default: realized closed-trade (lifecycle final outcome) net results attributed per §3.1; prop rule may override explicitly. | Prop uses in-memory start/balance and coarse `RecordTradingDay` history (`PropFirm.mqh:39-55`), not restart-safe. | **Conflict/Partial:** persistence, attribution, baseline correctness missing (D6,D9,D10). | Floating excluded by default. |
| **U-07** | Define consecutive wins/losses using net closed-trade outcomes. Specify reset rules, scope, and treatment of zero-result trades. | Unit = **one complete trade lifecycle outcome** (§3.5), net after aggregated components, `eps_pnl` (default 0). WIN/LOSS/BREAKEVEN rules defined; streaks persisted, scoped per bound identity/profile context; no auto daily reset by default. | `RecordTrade` per call, strict sign, zero leaves streaks but counts trade (`Protection.mqh:52-57`), not persisted (D3). | **Conflict:** unit, persistence, reset semantics differ. | Hedging/netting aggregation unit must be fixed (UR-11). |
| **U-08** | Use one authoritative trading-day time service. Default to broker server time, with configurable prop-firm reset boundaries. | Single `TradingDayTimeService`: effective time, fallback flag, `ScheduledBoundary`, `tradingDayId`, boundary detection (§3.4). Default `TimeTradeServer()`, fallback `TimeCurrent()` persisted/warned; configurable reset boundaries per profile/prop. | Split authority: store server keys vs EA local `TimeCurrent().day` (`StateStore.mqh:185-189,296-299`, `MoneyManager.mq5:303-311`). | **Conflict (D6,C2).** | DST/offset representation configurable (UR-06). |
| **U-09** | Count each valid trading day exactly once using a persisted trading-day identifier. | Persist `tradingDayId`; count `minTradingDays` at most once per id when valid-day criteria met (configurable, §3.1/§3.4). | Coarse local static-day increment, not persisted/idempotent (`PropFirm.mqh:39-47`). | **Conflict (D10,C8).** | Valid-day criteria per prop rule (UR-05). |
| **U-10** | Detect and record deposits and withdrawals. Never automatically weaken protective limits. Ambiguous cash-flow events require manual review. | Detect/record cashflow events with evidence; never auto-weaken; ambiguous => `requiresManualReview` + conservative lock until explicit confirmed resolution. | No detection/ledger/manual-review state. | **Gap (R1,R7).** | Resolution outcomes policy (UR-07). |
| **U-11** | Bind persisted state to account Login, Server, Account Mode, and Profile identity. | Bind to Login+Server+AccountMode+Profile (and prop profile/ruleset id where applicable); mismatch => no unsafe apply, fail-safe/manual review. | Login-only key/filename (`StateStore.mqh:105-117`), mode/profile not enforced as binding gate. | **Conflict.** | Identity encoding/migration path required. |
| **U-12** | Retain migration information and previous valid state versions for recovery and diagnostics. | Retain migration log, original pre-migration payload, and previous/last-known-good artifacts per policy; include durability-recovery artifacts as applicable. | Single overwritten `.bak` (`StateStore.mqh:159-174`). | **Conflict/Gap (C6).** | Retention parameters (UR-10). |
| **U-13** | Use adequate internal calculation precision. Define comparison epsilon. Round only where required for display or broker execution. | Internal `double`, named epsilons (`eps_money`, `eps_pct`, `eps_pnl`, `eps_cashflow`, lot/step), no premature rounding; round only for display/broker constraints. | Direct comparisons, ad-hoc formatting. | **Partial conflict (R7).** | Values/strictness (UR-04). |
| **U-14** | Represent disabled limits explicitly using a DISABLED state, not an ambiguous numeric sentinel. | Explicit `ENABLED|DISABLED` state per limit; logic branches on state. | Sentinel `>0`/`<=0` widespread (`Protection.mqh`, `PropFirm.mqh`). | **Conflict.** | Legacy mapping rules required. |
| **U-15** | Daily restrictions may clear only after a valid daily rollover. Total restrictions require their explicitly defined recovery or manual authorization policy. | Daily-scoped clears only on valid authoritative rollover; total-scoped requires defined recovery or explicit manual authorization (audited). Unpersistable latest HWM / integrity failures may impose protective block per §3.3, §6. | Cooldown auto-clears on expiry; no persistent breach locks (D5). | **Conflict.** | Recovery workflow (UR-09). |
| **U-16** | Restore persisted HWM values strictly. A higher live value may update the HWM only after account identity and state integrity are verified. Record the startup-gap event. | Strict restore from persisted durable HWM; upward update only after verified identity/integrity and per policy; record startup-gap. Unpersisted-peak/crash cases handled conservatively (§3.3). | `EnsureBaselines/SyncPeaks` bump to current (`StateStore.mqh:91-100,338-340`, `Protection.mqh:48-50,65-66`). | **Conflict (D1,R9).** | Catch-up policy (UR-08). |
| **U-17** | If restored state and live account information disagree, apply fail-safe behavior. Do not silently replace protective baselines with current values. | Any material disagreement => fail-safe (`operational=false`/restricted), block risk-increasing actions as applicable, `requiresManualReview`, preserve artifacts, explicit confirmed recovery. No silent replacement. | Missing/corrupt paths can seed from current (`StateStore.mqh:248-256`). | **Conflict (C5,D7,R4,R9).** | Materiality thresholds enumerated in impl spec. |

---

## 3. Phase 1.2 — Final Financial Corrections

### 3.1 Complete Trade Lifecycle PnL

#### 3.1.1 Verified implementation facts (current)
- `CTradeLifecycle::OnTradeTransaction` emits **per-deal** events and does not aggregate PnL across deals or lifecycle (`Include/Trade/TradeLifecycle.mqh:110-158`); no dedupe and no restart reconciliation.
- EA records realized result on OUT/INOUT BUY/SELL deals as `DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP` per deal (`MoneyManager.mq5:368-382`), without lifecycle aggregation or deal-id dedupe. This is **not** a complete lifecycle net outcome for multi-deal/partial/hedging/netting cases.
- Compatibility conclusion: **existing TradeLifecycle and EA recording are not sufficient** for complete lifecycle PnL; they can be reused as event/deal sources but require an aggregation layer and dedupe/reconciliation (proposed, future implementation).

#### 3.1.2 Proposed default: lifecycle-level aggregation (not closing-deal-only)
- Define a **Trade Lifecycle Aggregate** identified by a stable lifecycle key (proposed: bound identity + `positionId`/position ticket lineage + symbol/magic as applicable; exact key per netting/hedging mode — UR-11).
- **LifecycleNetPnL (money)** for a completed lifecycle = sum over **all unique deals** in the lifecycle of: `DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP + ApplicableDealFees` (where `ApplicableDealFees` are fee components explicitly surfaced in deal fields/records; components not surfaced must follow UR-12 cashflow/integrity handling, never guessed).
- Must account for: **entry commission**, **exit commission**, **trading profit/loss**, **swap**, **applicable fees**, **partial closes**, **multiple deals**, **hedging and netting**.
- **No duplicate attribution (mandatory):** each deal included at most once per lifecycle/day accounting using unique `deal ticket/id` (and, if required, transaction sequence) as dedupe key; ignore already-applied deal ids on replay/restart reconciliation. Commission and swap are attributed only via their originating deal record (never inferred twice from open/close summaries).
- **Lifecycle states (proposed):** `OPEN` (has open exposure/entries), `PARTIALLY_REALIZED` (one or more closing deals realized, exposure remains), `CLOSED` (flat for lifecycle key, final outcome known), `REVERSED/ROLLED` (netting/hedging reversal creating successor exposure — modeled as lifecycle transition with explicit close component and linked successor per rules below).

#### 3.1.3 Hedging and netting (proposed, explicit)
- **Hedging accounts:** positions/tickets can coexist; lifecycle key aligns to the hedged position/positionId lineage. Partial closes and final close aggregate all deals belonging to that position lifecycle. Opposite positions are separate lifecycles unless explicitly linked by broker semantics.
- **Netting accounts:** a single position per symbol aggregates volume; deals may represent partial reductions, increases, or reversals (IN/OUT/INOUT). Lifecycle aggregation follows `DEAL_POSITION_ID`/position identifier lineage and volume-to-flat transitions: a **final outcome event** occurs when net position volume for the lifecycle key returns to zero (or broker-equivalent close) after accounting for the dealt volume. INOUT/reversal is treated as a close component (realized on dealt volume) plus, if exposure remains/reopens, a linked successor lifecycle component as evidenced by subsequent deals — never as an unaggregated standalone "trade" without decomposition.
- **Uncertainty rule:** if hedging/netting semantics cannot be determined from available deal/position evidence, mark lifecycle `degraded` and apply §3.6 fail-safe/manual review (no guessed outcome).

#### 3.1.4 Trades spanning multiple trading days (proposed, explicit)

Let `DealDayId(d)` be the authoritative `tradingDayId` for deal `d`'s effective server time.

| Metric | Proposed attribution rule |
|---|---|
| **Daily realized PnL** | `RealizedDayPnL_net(day) = Σ_{unique deals d : DealDayId(d)==day} (DEAL_PROFIT_d + DEAL_COMMISSION_d + DEAL_SWAP_d + ApplicableDealFees_d)` for deals belonging to bound identity scope. Entry/exit costs realized on their own deal days; no reallocation. |
| **Daily profit** | `RealizedDayProfit_net(day) = max(0, RealizedDayPnL_net(day))` (per U-05/U-06 defaults); percentage uses `ProfitRef` per §4.3. |
| **Consistency** | Default: computed over per-day realized closed-trade results keyed by `tradingDayId` (`RealizedDayPnL_net(day)` / configured basis) unless prop rule specifies otherwise; partial lifecycle contributions affect the days of their deals. |
| **Consecutive wins/losses** | Counted on **Final Outcome Event** of a complete lifecycle only (not per deal/partial): outcome = `LifecycleNetPnL` at closure, attributed to `tradingDayId` of the final closing/reversal-to-flat deal for sequencing; a lifecycle that closes on day N+1 yields one outcome on day N+1 even if it had deal components on day N. (Configurable per prop rule if explicitly required.) |
| **Minimum trading days** | `tradingDayId` counted once when "valid trading day" criteria are met (UR-05). Default proposed: at least one qualifying closed-trade/lifecycle final outcome (or configured qualifying realized event) on that day; a multi-day lifecycle contributes a qualifying event on the day of its final outcome (and does not retroactively create prior-day counts except prior-day final outcomes from other lifecycles). |

**No double-counting across days:** a deal's net components are included in exactly one `RealizedDayPnL_net(day)` (its deal day) and in exactly one lifecycle total; lifecycle total used for streak/final outcome is the sum of those same unique deal components (reconciliation check, not double addition to daily buckets).

### 3.2 Coupled Daily DD Denominator to Measurement Policy

#### 3.2.1 Mandatory denominator mappings (no incompatible combinations)

| Policy | Numerator (Used abs, money) | Mandatory denominator (Ref_den) | Used % |
|---|---|---|---|
| `EQUITY_SNAPSHOT` | `max(0, DayStartEquity - CurrentEquity)` | **`DayStartEquity`** | `Used_abs / DayStartEquity * 100` |
| `BALANCE_SNAPSHOT` | `max(0, DayStartBalance - CurrentBalance)` | **`DayStartBalance`** | `Used_abs / DayStartBalance * 100` |
| `REALIZED_ONLY` | `max(0, -RealizedDayPnL_net(day))` | **`RealizedRiskRef` (explicit, configured)** | `Used_abs / RealizedRiskRef * 100` |
| `WORST_OF` | per selected component above | per selected component above (each with its own mandatory denominator) | per component: `Used_abs_i / Ref_den_i * 100` |

**Rules (proposed):**
- `RealizedRiskRef` is an explicitly defined/configured reference for `REALIZED_ONLY` (proposed default: `DayStartBalance`; allowed alternatives only if explicitly configured, e.g. `DayStartEquity` or approved baseline). It MUST be persisted/configured and never inferred incompatibly.
- **No incompatible numerator/denominator combination is permitted.** Validation must reject/flag configurations that bind a numerator to a non-mandated denominator.
- `WORST_OF` is evaluated as a set of fully-defined `(numerator, denominator)` components; components are never normalized with a foreign denominator.

#### 3.2.2 Remaining daily budget per policy

Let `L = DailyLossLimitPct` (enabled per U-14). `EN` indicates enabled.

| Policy | Allowed loss (money) | Used loss (money) | Remaining daily budget (money) |
|---|---|---|---|
| `EQUITY_SNAPSHOT` | `DayStartEquity * L/100` | `max(0, DayStartEquity - CurrentEquity)` | `EN ? max(0, Allowed - Used) : DISABLED` |
| `BALANCE_SNAPSHOT` | `DayStartBalance * L/100` | `max(0, DayStartBalance - CurrentBalance)` | `EN ? max(0, Allowed - Used) : DISABLED` |
| `REALIZED_ONLY` | `RealizedRiskRef * L/100` | `max(0, -RealizedDayPnL_net(day))` | `EN ? max(0, Allowed - Used) : DISABLED` |
| `WORST_OF` | per component `Allowed_i = Ref_den_i * L/100` (or per-component limits if explicitly configured) | per component `Used_i` | Compute per component `Remaining_i = EN ? max(0, Allowed_i - Used_i) : DISABLED` and per component `%Used_i`. **Selection (configured, explicit):** `WORST_PCT` → governing component = argmax(`%Used_i`); `WORST_MONEY` → governing component = argmin(`Remaining_i`) / argmax(`Used_i`) as defined. Report remaining in the selected basis consistently; effective guard uses the governing (worst) component so no other component is allowed to breach. |

**Effective remaining across multiple enabled limits (personal+prop):** `min` of enabled remaining budgets evaluated under the same policy/basis contract, after mapping each limit to its own mandated measure where rules differ (configuration must be explicit).

### 3.3 HWM Durability

#### 3.3.1 Persistence guarantee (proposed, strongest feasible)
- **Trigger:** on every **verified HWM increase** (post identity/integrity verification per U-16; `candidateHWM > persistedHWM_durable + eps_money`), the system MUST mark HWM state `dirty` and **initiate save-on-new-high** before relying on the new HWM as durably protected across restart.
- **Guarantee statement (proposed):** no verified HWM increase is considered *durably recorded* until a persistence transaction completes successfully and the committed state reflects `hwmDurable == hwmCandidate` (with integrity marker/checksum as applicable). In-memory advancement alone is **not** durable.
- **Write protocol goal:** write temp → verify contents/checksum/size where feasible → atomic publish/rename strategy with retained prior-good artifact; record `lastHwmDurableSaveTime` and `hwmDirty=false` only on success.

#### 3.3.2 Failure and recovery behavior (proposed)

| Condition | Required behavior |
|---|---|
| **Save-on-new-high behavior** | Eager save attempt on verified increase; may coalesce rapid increases but MUST retain highest pending candidate and keep `hwmDirty=true` until durable success. |
| **Failed HWM write** | Keep `hwmDirty=true`, preserve last-known-good durable HWM, emit error/diagnostic, retry per bounded policy; **block new risk-increasing actions** while latest verified HWM cannot be durably saved (fail-safe, because trailing DD protection depends on HWM). Existing positions/management actions that reduce risk may remain allowed only if explicitly defined, but new/increased exposure MUST be blocked (UR-09 alignment for protective posture). |
| **Power loss during save** | On restart, load committed state only: prefer valid primary, else valid `.bak`/last-known-good artifact; never trust partially written temp as committed. If dirty-marker/transaction indicates incomplete commit, treat durable HWM as last committed value and enter fail-safe review per startup-unpersisted-peak rules below. |
| **Temporary file and backup recovery** | Preserve/ignore orphan temp by policy; recover from last valid committed primary or retained backup artifact; validate integrity before adopting. |
| **Startup after an unpersisted peak** | If evidence indicates HWM advanced in-memory but not durably committed (e.g. `hwmDirty` committed state, incomplete transaction marker, or crash window), the EA cannot prove the lost peak. **Proposed fail-safe:** restore `persistedHWM_durable` (U-16), set `integrity.degraded=true`, `requiresManualReview=true`, record `UNPERSISTED_PEAK_SUSPECTED` startup-gap event, and **block new risk-increasing actions** until explicit user-confirmed resolution; do not silently assume higher or lower peak beyond durable record. |
| **Trading must be blocked when latest HWM cannot be durably saved** | **Yes (proposed mandatory):** block new risk-increasing actions while `hwmDirty` persists after a verified increase or save failure, because inability to persist HWM can understate trailing DD on restart (R1). |

### 3.4 Trading-Day Baseline Capture

#### 3.4.1 Required distinctions (proposed)
- **`ScheduledBoundary`**: the authoritative configured trading-day boundary instant/key transition (per `TradingDayTimeService`, U-08).
- **`ActualCaptureTime`**: the effective server time (or fallback-marked time) when the baseline snapshot was actually read.
- **`BaselineCaptureStatus`** (explicit enum/state): e.g. `PENDING`, `EXACT_AT_BOUNDARY` (captured at boundary within defined tolerance), `DELAYED_CAPTURE` (captured after boundary), `DEGRADED_FALLBACK_TIME`, `UNAVAILABLE_REQUIRES_REVIEW`, `MIGRATED_ESTIMATED` (only if ever explicitly allowed and marked; not silent). A baseline MUST store all three fields (and source flags) — **never silently label a delayed snapshot as an exact midnight/scheduled baseline.**

#### 3.4.2 Behavior matrix (proposed)

| Condition | Behavior |
|---|---|
| **EA offline at scheduled boundary** | On first valid evaluation after restart, detect missed boundary via persisted `dayId`/keys; perform rollover and capture baseline at `ActualCaptureTime` with `BaselineCaptureStatus=DELAYED_CAPTURE`, record `ScheduledBoundary`, set degraded/review flags as required. Do not backdate. |
| **No tick arrives at midnight** | Capture on next timer/tick/event opportunity; if `ActualCaptureTime` is after boundary tolerance, mark `DELAYED_CAPTURE` (or `DEGRADED_FALLBACK_TIME` if applicable), never `EXACT_AT_BOUNDARY`. |
| **Open positions exist** | Capture live `AccountInfoDouble(ACCOUNT_EQUITY)` and balance as authoritative inputs at `ActualCaptureTime` (U-06 equity source) including floating PnL impact; record open-position context snapshot metadata if available. No reconstruction of "what equity would have been at boundary". |
| **Server time is unavailable** | Use fallback time source per U-08, set `timeFallback=true` and `BaselineCaptureStatus=DEGRADED_FALLBACK_TIME` (and `DELAYED_CAPTURE` semantics if boundary uncertain), persist warning and require conservative handling for prop-critical enforcement; may set `requiresManualReview` when boundary cannot be proven. |
| **Exact historical equity cannot be reconstructed** | **Do not reconstruct or claim exact boundary equity.** Use best-available live capture with explicit non-exact status, set `requiresManualReview=true` and/or conservative protective posture per U-17 when the baseline is material to enforcement; preserve evidence for manual confirmation. |

### 3.5 Trade Outcome Aggregation

#### 3.5.1 One complete trade outcome (proposed)
- **Source:** derived from `TradeLifecycle` deal/event stream (and, where required, reconciled history) by a lifecycle aggregator producing a single **Final Outcome Record** per completed lifecycle.
- **Final outcome event:** emitted/recorded when lifecycle transitions to `CLOSED` (net exposure returns to flat for the lifecycle key) with aggregated `LifecycleNetPnL`, component totals, deal-id set, open/close times, final `tradingDayId`, and outcome classification (WIN/LOSS/BREAKEVEN per U-07).
- **Do not count every deal as an independent trade:** partial closes, fee legs, and multi-deal executions contribute to the same lifecycle aggregate; only the Final Outcome Record (or explicitly defined qualifying realized event per rule) increments streaks / "trade outcome" statistics as configured.

#### 3.5.2 Explicit behaviors (proposed)
- **Partial close aggregation:** each partial OUT/INOUT deal contributes realized components to lifecycle totals and to `RealizedDayPnL_net` of its `DealDayId`; lifecycle remains open until flat. Final outcome equals sum of all unique deal components over the lifecycle.
- **Hedging behavior:** hedged tickets/positions tracked as distinct lifecycles (unless broker links them); netting across opposite hedged positions is not assumed. Aggregation per lifecycle key.
- **Netting behavior:** aggregate by position identifier/lineage and volume-to-flat; INOUT reversals decomposed into close-of-existing exposure and linked successor exposure per evidenced deals. Final outcome on return-to-flat for that lifecycle.
- **Zero-result handling:** lifecycle `net` within `[-eps_pnl, +eps_pnl]` => `BREAKEVEN` (U-07); recorded as final outcome with zero PnL classification, does not change win/loss streak counters by default.
- **Duplicate transaction prevention:** idempotent processing keyed by unique deal id (and transaction id where applicable) within bound identity; maintain applied-deal watermark/set in persisted state to ignore replays/duplicate deliveries (compatible with `Docs/contracts.md` listener tolerance, but aggregation must be idempotent).
- **Restart reconciliation:** on init/restart, load persisted lifecycle/aggregation checkpoints and applied-deal ids; if required history window is complete and verifiable, reconcile forward from checkpoint; if history incomplete or inconsistent, apply §3.6 fail-safe (`HISTORY_INCOMPLETE`/degraded, `requiresManualReview`, block risk-increasing actions, no guessed outcomes). Never synthesize missing deals.

### 3.6 Equity Source (authoritative inputs)

- **Authoritative live Equity input (proposed mandatory):** `Equity_live = AccountInfoDouble(ACCOUNT_EQUITY)` at evaluation/capture time.
- **Balance and Floating PnL as separate diagnostic components:** `Balance_live = AccountInfoDouble(ACCOUNT_BALANCE)`, `FloatingPnL_diag = Equity_live - Balance_live` (or equivalent diagnostic derivation) stored/reported as components for transparency and reconciliation; they are **not** a replacement source of truth for official equity.
- **Prohibition:** do **not** reconstruct or substitute official account Equity using only `Balance + Floating PnL` computed independently (e.g. summed position PnL) as the authoritative equity value. Any independent calculation may be used only as a diagnostic consistency check; on material divergence, raise integrity diagnostic and apply fail-safe/manual review per U-17.

### 3.7 Prop Profile Governance

#### 3.7.1 Proposed governance model (no unverified hardcoded assumptions)
All prop-firm behavior MUST be driven by an explicit, versioned, auditable profile/ruleset configuration. Hardcoded assumptions are permitted only as **non-authoritative templates** that must be explicitly selected, versioned, and recorded as `Rule source = TEMPLATE` with user/operator confirmation — never treated as verified firm truth.

#### 3.7.2 Required governance fields (proposed schema)

| Field | Definition (proposed) |
|---|---|
| **Profile ID** | Stable unique identifier of the prop profile/ruleset instance bound to state. |
| **Profile version** | Monotonic version of the profile definition; changes recorded in audit/history. |
| **Rule source** | Origin of rules: `TEMPLATE` (named preset), `CUSTOM`, `IMPORTED`, or `VERIFIED_EXTERNAL` (with evidence reference) — never implied. |
| **Rule effective date** | Date/time from which this ruleset version is effective for the account/stage. |
| **Account type/stage** | e.g. `CHALLENGE`, `VERIFICATION`, `FUNDED`, `PERSONAL`, or custom; drives applicable limits/models. |
| **Configurable DD model and reference** | Explicit selections per U-02/U-03/U-04: daily policy/ref/denominator coupling, total model (static/trailing) and ref, `RealizedRiskRef`, `WORST_OF` basis, etc., per account type/stage. |
| **Daily reset policy** | Explicit `TradingDayTimeService` boundary config (U-08): source, mode (`SERVER_MIDNIGHT`/`SERVER_HHMM`/`FIXED_UTC_OFFSET_HHMM`), offset, effective date. |
| **Manual override audit trail** | Append-only records of operator/user overrides (who/when/identity, prior value, new value, reason, confirmation token/event, scope/expiry) especially for recovery, cashflow resolution, baseline/reset actions, and rule changes. |

#### 3.7.3 Separation of concerns
- **Account-level protection** (personal/safety limits, fail-safe, integrity, durability, manual review) and **prop-firm-specific rules** (targets, consistency, reset boundaries, model/ref choices mandated by firm) MUST be modeled separately, with effective enforcement = conservative combination where both apply (e.g. effective remaining = min of applicable enabled budgets) and with clear precedence documented per field. Any behavior dependent on a particular prop firm's contract MUST be configurable and documented in the profile.

---

## 4. Exact Financial Formulas (Proposed-by-design, updated)

> Notation: `max0(x)=max(0,x)`. Money in account currency. `eps_*` per U-13. `EN(x)=1` if limit enabled else 0 (U-14). `Equity_now = AccountInfoDouble(ACCOUNT_EQUITY)` (authoritative, §3.6). `RealizedDayPnL_net(day)` per §3.1.

### 4.1 Maximum / Total Drawdown

| Model | Ref series | Used (abs) | Used (%) | Allowed (abs) | Remaining (abs) |
|---|---|---|---|---|---|
| `TRAILING_HWM` | Equity | `max0(PeakEquityHWM_durable - Equity_now)` | `(PeakEquityHWM_durable>0)?Used/PeakEquityHWM_durable*100:0` | `PeakEquityHWM_durable*LimitPct/100` | `EN?max0(Allowed-Used):DISABLED` |
| `TRAILING_HWM` | Balance | `max0(PeakBalanceHWM_durable - Balance_now)` | `(PeakBalanceHWM_durable>0)?Used/PeakBalanceHWM_durable*100:0` | `PeakBalanceHWM_durable*LimitPct/100` | same |
| `STATIC_INITIAL` | Equity | `max0(InitialBaselineEquity - Equity_now)` | `(InitialBaselineEquity>0)?Used/InitialBaselineEquity*100:0` | `InitialBaselineEquity*LimitPct/100` | same |
| `STATIC_INITIAL` | Balance floor (breached by equity if configured) | `max0(InitialBaselineBalance - Equity_now)` | `(InitialBaselineBalance>0)?Used/InitialBaselineBalance*100:0` | `InitialBaselineBalance*LimitPct/100` | same |
| `STATIC_INITIAL` | Balance vs balance (if configured) | `max0(InitialBaselineBalance - Balance_now)` | `(InitialBaselineBalance>0)?Used/InitialBaselineBalance*100:0` | `InitialBaselineBalance*LimitPct/100` | same |

**HWM update (U-16, §3.3):** candidate increase only after verified identity/integrity; durable only after successful save-on-new-high commit; `hwmDirty` or save failure => block new risk-increasing actions.

### 4.2 Daily Drawdown (mandatory numerator/denominator coupling)

| Policy | Numerator `Used_i` (money) | Mandatory `Ref_den_i` | `%Used_i` | Allowed `A_i` | Remaining `R_i` |
|---|---|---|---|---|---|
| `EQUITY_SNAPSHOT` | `max0(DayStartEquity - CurrentEquity)` | `DayStartEquity` | `Used_i/Ref_den_i*100` | `Ref_den_i*L/100` | `EN?max0(A_i-Used_i):DISABLED` |
| `BALANCE_SNAPSHOT` | `max0(DayStartBalance - CurrentBalance)` | `DayStartBalance` | same | same | same |
| `REALIZED_ONLY` | `max0(-RealizedDayPnL_net(day))` | `RealizedRiskRef` (explicit, configured) | same | same | same |
| `WORST_OF` | each selected component above | each component's mandatory denominator above | per component | per component | per component; governing selected by `WORST_PCT` or `WORST_MONEY` (configured) — guard enforces governing component |

**Invalid configurations (must reject/flag):** any numerator paired with non-mandated denominator (e.g. equity-snapshot numerator with balance denominator).

### 4.3 Daily Profit and Profit Percent

- `RealizedDayProfit_net(day) = max0(RealizedDayPnL_net(day))`; `RealizedDayLoss_net(day) = max0(-RealizedDayPnL_net(day))`.
- `DailyProfitPct = (ProfitRef>0)?RealizedDayProfit_net(day)/ProfitRef*100:0`, `ProfitRef` explicit/configured (default proposed `DayStartBalance`).
- Targets/consistency default to realized closed-trade/lifecycle outcomes per §3.1 unless prop rule overrides.

### 4.4 Streaks and Cooldown

- Outcome from **Final Outcome Record** `x = LifecycleNetPnL`: `x > eps_pnl`→WIN; `x < -eps_pnl`→LOSS; else BREAKEVEN.
- WIN: `consecWins+=1; consecLosses=0`. LOSS: `consecLosses+=1; consecWins=0`. BREAKEVEN: no change.
- Cooldown active if `now_effective < cooldownUntilServer` (persisted). Daily/total restriction clearing per U-15.

### 4.5 Breach/Lockout Evaluation

- Breach when `Used >= Allowed - eps_cmp` (configured strictness) while enabled. Persist flag/reason/time/scope. Daily-scoped clears only on valid rollover; total-scoped requires defined recovery/manual authorization. Durable-save failure for verified HWM or integrity disagreement may impose protective trading block (§3.3, §6).

---

## 5. State Schema Proposal (persistenceSchemaVersion 2, proposed — updated)

> Proposed for implementation after approval. Existing v1 keys migratable. Identity binding per U-11. Fields below extend Phase 1.1 to cover Phase 1.2.

| Group | Fields (proposed) | Phase 1.2 additions/notes |
|---|---|---|
| **Identity/version** | `persistenceSchemaVersion(2)`, timestamps, `boundIdentity{login,server,accountMode,profileId,propProfileId?}`, `writerLease?` | U-01,U-11 |
| **Time/trading-day** | `time{sourcePolicy,resetPolicy,resetHour,resetMinute,resetOffsetMinutes?,lastServerTime,timeFallback,dayKey/tradingDayId,weekKey,monthKey,lastRolloverServerTime,scheduledBoundary,lastScheduledBoundary}` | U-08,U-09; boundary tracking |
| **Baselines** | `baselines{dayStartBalance,dayStartEquity,initialBalance,initialEquity,scheduledBoundary,actualCaptureTime,baselineCaptureStatus,captureReason,openPositionsContext?}` | **§3.4**: status/distinction mandatory |
| **Peaks (durability)** | `peaks{equityHwmDurable,balanceHwmDurable,equityHwmCandidate?,balanceHwmCandidate?,hwmDirty,lastHwmDurableSaveTime,lastSaveError?,startupGapEvents[]}` | **§3.3**: durable vs candidate, dirty/commit state |
| **Daily/period realized** | `daily{realizedPnL_net,realizedProfit_net,realizedLoss_net,tradesCount,dayId,appliedDealIds/checkpoint}`, `period{tradesWeek,tradesMonth,weekId,monthId}` | per-day deal attribution, dedupe checkpoint |
| **Lifecycle aggregation** | `lifecycles/openAggregates[]` (bounded), `finalOutcomes[]` (bounded/summary), `appliedDealIds` watermark/set, `lifecycleCheckpoint` | **§3.1, §3.5**: no per-deal-as-trade, dedupe, restart reconciliation |
| **Streaks/risk** | `streaks{consecWins,consecLosses,lastOutcome,lastOutcomeNet,lastOutcomeDayId}`, `risk{cooldownUntilServer,dailyBreach,totalBreach,manualReviewRequired,manualReviewReasons[],limitStates(ENABLED/DISABLED),realizedRiskRef}` | U-07,U-14,U-15; denominator coupling inputs |
| **Cashflow** | `cashflow{lastKnownBalance,lastKnownEquity?,events[],unresolvedAmbiguous}` | U-10 |
| **Prop governance** | `propProfile{profileId,profileVersion,ruleSource,ruleEffectiveDate,accountTypeStage,ddModelDaily,ddModelTotal,dailyRef,totalRef,dailyPolicy,worstOfMode,resetPolicy,manualOverrideAudit[]}`, `propState{...baselines/peaks/progress/breaches...}` | **§3.7** separation and auditability |
| **Integrity/migration** | `integrity{ok,operational,degraded,loadSource,lastGoodSave,checksum?,requiresManualReview,reasons[],hwmPersistOk}`, `migration{fromVersion,toVersion,migratedAt,lossyFields[],originalArtifactRef,retainedArtifacts[]}` | U-12,U-17, durability flags |
| **Compatibility** | migrate v1 fields where valid; lossy fields => safe defaults + `requiresManualReview` | no silent weakening |

---

## 6. Recovery and Fail-Safe Behavior (updated)

| Condition | Required behavior (proposed) |
|---|---|
| Future/unknown persistence schema | `operational=false`, no overwrite, block trading, diagnostics. |
| Primary corrupt/unreadable, `.bak` valid & verified | Restore from `.bak`, validate, record recovery, `loadSource=BAK`; unresolved protective ambiguity => `requiresManualReview=true`. |
| Primary and `.bak` invalid/missing | Preserve artifacts, hard fail-safe, no auto-rebaseline from current, block trading (§3.8 prior). |
| Identity mismatch | No unsafe apply; fail-safe/manual review or load correct bound state. |
| Cashflow detected or ambiguous | Record event, never weaken limits, ambiguous => `requiresManualReview`. |
| Broker history incomplete / unreconcilable | `degraded`, `requiresManualReview`, block risk-increasing actions, no guessed outcomes (§3.1.4, §3.5.2, §3.6). |
| **Latest verified HWM cannot be durably saved / `hwmDirty`** | Block new risk-increasing actions, retain last durable HWM, retry/alert, require resolution per policy (§3.3). |
| **Startup after unpersisted peak suspected** | Restore durable HWM, `degraded` + `requiresManualReview` + `UNPERSISTED_PEAK_SUSPECTED`, block new risk-increasing actions until explicit confirmed resolution (§3.3). |
| **Delayed/degraded baseline capture** | Persist `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus`, never label delayed as exact; conservative/manual review when material (§3.4). |
| Time fallback / boundary uncertainty | Persist/surface `timeFallback`, conservative prop-critical handling. |
| Multi-instance write conflict | Non-owner read-only for persistence; no conflicting writes. |
| Manual recovery/reset/override | **Explicit user confirmation required**, append-only audit trail (§3.7, §3.9 prior). |

**Invariant:** never silently replace protective baselines/HWM/lockouts with live current values; never count deals as trades; never couple incompatible numerator/denominator.

---

## 7. Test Matrix (Design-level, NOT executed — updated)

| ID | Area | Scenario | Expected (proposed) |
|---|---|---|---|
| T-01 | Restore | Same-day restart with persisted durable HWM/day-start/realized/streak/cooldown/lifecycle checkpoints | Restored exactly; no reinit-to-now; gated until verified |
| T-02 | HWM | Trailing HWM across restart and new equity high after verified gap | Strict restore; upward update only after verified identity+integrity; startup-gap recorded |
| T-03 | Total DD | Static vs trailing, equity vs balance refs | Correct used/remaining per selected model/ref |
| T-04 | Daily DD coupling | EQUITY/BALANCE/REALIZED_ONLY/WORST_OF with mandatory denominators | Correct numerator+denominator pairing; incompatible config rejected; remaining per §3.2 |
| T-05 | Day boundary/capture | Offline at boundary, no midnight tick, open positions, server unavailable, unreconstructable historical equity | `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus` set correctly; delayed never labeled exact; conservative handling |
| T-06 | Lifecycle PnL | Entry+exit commission, swap, fees, partial closes, multi-deal, hedging, netting, INOUT reversal | Single lifecycle aggregate, unique deal attribution, no duplicate commission/swap, correct final outcome |
| T-07 | Multi-day span | Lifecycle spanning day boundary; partials on different days | Daily realized/profit per deal day; consistency per day results; streak/min-trading-day on final outcome per §3.1.4 |
| T-08 | Streaks | Win/loss/breakeven (epsilon) from final outcome only | No per-deal counting; persists across restart |
| T-09 | Lockouts/restrictions | Daily clears only on valid rollover; total requires recovery/manual auth; HWM-dirty block | Per U-15 and §3.3 |
| T-10 | Cashflow | Deposit/withdrawal/ambiguous balance op | Detected/recorded, never weakens, ambiguous => manual review |
| T-11 | Identity | Login/server/mode/profile mismatch or switch | No unsafe apply; correct bound load or fail-safe |
| T-12 | Integrity | Corrupt primary + valid bak; both invalid | Bak restore or hard fail-safe with preserved artifacts |
| T-13 | History incomplete/restart recon | Missed deals, replay, restart mid-lifecycle | Dedupe by deal id, reconcile if verifiable else fail-safe/manual review, no guessed outcomes |
| T-14 | Migration | v1→v2, lossy fields, idempotency, retained artifacts | Correct transform, flags, no silent weakening |
| T-15 | Multi-instance | Concurrent charts/EAs same identity | Single writer lease, no conflicting writes |
| T-16 | Prop governance | Profile id/version/source/effective date/stage, configurable models/refs/reset, overrides audited; templates not assumed verified | Rules driven by config; account-level vs prop-firm separation enforced |
| T-17 | HWM durability/crash | **Peak advancement followed by immediate crash/restart before durable save; failed HWM write; power loss during temp/bak commit** | Latest uncommitted peak not trusted; restore durable HWM, `UNPERSISTED_PEAK_SUSPECTED`/degraded/manual review as applicable, block new risk-increasing actions; committed state recoverable from primary/bak |
| T-18 | Equity source | Live equity vs balance/floating diagnostics divergence | `ACCOUNT_EQUITY` authoritative; no reconstruction from Balance+Floating as source of truth; divergence => diagnostic/fail-safe |

**Execution status:** NOT RUN (design only).

---

## 8. Migration Plan (Proposed — updated)

1. **Versioning (U-01):** introduce `persistenceSchemaVersion=2`; keep `MM_CONTRACT_VERSION` unchanged unless public contracts change.
2. **Pre-migration preservation (U-12):** archive original v1 payload + metadata before first v2 write; retain migration log and previous valid artifacts per policy.
3. **Field mapping v1→v2:** copy/migrate existing valid v1 fields; augment bound identity (server/mode/profile) — if unavailable, `requiresManualReview` until confirmed.
4. **Lossy/unknown fields (conservative):** lifecycle aggregates, applied-deal checkpoints, `RealizedDayPnL_net` components, streaks, cooldown, breach/lockout, `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus`, HWM durable/dirty markers, prop governance/history/reset ids, cashflow ledger absent in v1 → safe defaults, `integrity.degraded=true`, `requiresManualReview=true`, record lossy fields (never assume "no loss/no peak gap").
5. **HWM/baselines:** carry persisted peaks/day-starts as durable candidates only where provenance is valid; do not replace with current; record startup-gap/migration uncertainty per §3.3–§3.4.
6. **Validation & publish:** semantic validation (including denominator-coupling config consistency, identity binding, integrity markers); on success write v2 atomically with retained artifacts; on failure preserve originals and fail-safe.
7. **Idempotency:** detect migrated v2 and skip re-transform.
8. **Rollback/diagnostics:** retain previous valid versions and migration log (no automatic downgrade).

---

## 9. Implementation Dependencies (for approved phase)

- Approval of §13 items and freeze of configurable prop-firm/profile governance rules.
- `TradingDayTimeService` (U-08) with `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus` support.
- **Lifecycle aggregation engine** (dedupe, restart reconciliation, hedging/netting decomposition, final outcome emission) integrated with/over `TradeLifecycle` events and history reconciliation.
- Restore/hydrate APIs for `CProtection`/`CPropFirm` without reset-to-now (C1); unified DD/risk calculation path implementing §4 and denominator coupling.
- Persistence layer: schema v2 R/W, integrity checks, durable HWM save-on-new-high with dirty/commit tracking, `.bak`/artifact recovery, lease/lock hardening, migration/retention (U-01,U-10..U-12,U-16,U-17, §3.3).
- Cashflow detection/ledger and manual-review workflow (explicit confirmation, audited).
- Prop profile governance storage/UI/config (ids, versions, source, effective date, stage, configurable models/refs/reset, override audit) separate from account-level protection.
- UI/status surfacing: `timeFallback`, `requiresManualReview`, breaches, lock/lease source, `hwmDirty`, baseline capture status, manual-confirm recovery.
- Coordinated doc updates and, if any public shared contract changes, `MM_CONTRACT_VERSION` handling — **only in implementation phase with approval**.
- Evidence plan (NOT executed now): MQL5/script/Strategy Tester/restart and crash-simulation scenarios for T-01..T-18 before claiming validation.

---

## 10. Approved-by-proposal Defaults (NOT user-approved)

- **U-01:** `persistenceSchemaVersion=2`; `MM_CONTRACT_VERSION` unchanged absent public-contract change.
- **U-02/U-03:** Explicit selectable Static/Trailing total DD with separate Balance/Equity semantics for daily and total; per-profile/prop-preset mapping.
- **U-04 + §3.2:** Default daily enforcement `EQUITY_SNAPSHOT` with mandatory `DayStartEquity` denominator; alternatives configurable with mandatory couplings; `WORST_OF` per-component denominators.
- **U-05 + §3.1:** Realized PnL net from lifecycle-level aggregation of unique deal components (`PROFIT+COMMISSION+SWAP+applicable deal fees`) with dedupe; `ProfitRef` explicit (default proposed `DayStartBalance`).
- **U-06 + §3.1.4:** Profit target/consistency default to realized closed-trade/lifecycle outcomes keyed by `tradingDayId`, unless prop rule overrides.
- **U-07 + §3.5:** Streaks from one complete lifecycle final outcome (not per deal), `eps_pnl` breakeven (default 0), persisted, no auto daily reset.
- **U-08 + §3.4:** Single authoritative trading-day service, default broker server time, configurable boundaries; `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus` mandatory; no silent delayed-as-exact labeling.
- **U-09:** Valid trading day counted once via persisted `tradingDayId`.
- **U-10:** Detect/record cashflows; never weaken; ambiguous => `requiresManualReview`.
- **U-11:** Bind state to Login+Server+AccountMode+Profile (and prop identity).
- **U-12:** Retain migration info and previous valid versions/artifacts.
- **U-13:** Internal `double`, defined epsilons, rounding only for display/broker execution.
- **U-14:** Explicit `DISABLED` limit state.
- **U-15:** Daily restrictions clear only on valid rollover; total restrictions require defined recovery/manual authorization.
- **U-16 + §3.3:** Strict durable HWM restore; upward update only after verified identity/integrity and per policy; record startup-gap; block new risk-increasing actions when latest HWM not durably saved / unpersisted-peak suspected.
- **U-17:** Fail-safe on disagreement; no silent replacement of protective baselines.
- **§3.6:** `AccountInfoDouble(ACCOUNT_EQUITY)` authoritative live equity; Balance/Floating separate diagnostics; no reconstruction of official equity from Balance+Floating alone.
- **§3.7:** Versioned, auditable prop profile governance; no unverified hardcoded prop-firm assumptions.

---

## 11. Remaining Unresolved Decisions (need explicit choice/value)

| ID | Unresolved point | Why unresolved |
|---|---|---|
| **UR-01** | Per-preset/per-mode mapping: total DD model (static/trailing), daily/total refs, daily policy, `RealizedRiskRef` for FTMO/MFF/FundedNext/The5ers/custom | Prop firms/contracts differ; presets indicative only |
| **UR-02** | `ProfitRef` default and allowed options per mode/rule | Affects behavior/compatibility |
| **UR-03** | `WORST_OF` enabled? composition set and selection mode (`WORST_PCT` vs `WORST_MONEY`) and multi-limit interaction | Must be explicit to avoid ambiguity |
| **UR-04** | `eps_pnl`, `eps_money`, `eps_pct`, `eps_cashflow`, breach comparison strictness (`>=` vs `>`) | Values policy-dependent |
| **UR-05** | "Valid trading day" criteria for `minTradingDays` (final outcome vs qualifying realized event) per prop rule | Varies by firm |
| **UR-06** | Reset boundary config schema (`SERVER_HHMM`/offset/timezone), DST handling, boundary tolerance for `EXACT_AT_BOUNDARY` | MT5/profile constraints and firm rules |
| **UR-07** | Manual cashflow-resolution outcomes and any explicitly confirmed cases where protective references may change without weakening guarantees | Recovery actions must be specified |
| **UR-08** | Upward HWM catch-up after verified offline/startup gap (auto post-verification `max(durable,live)` vs hold-for-confirmation) | Strictness vs gap handling |
| **UR-09** | Total-restriction recovery/manual-authorization workflow (including non-recoverable cases) and whether any non-risk-reducing actions allowed while HWM-dirty/protective-blocked | Policy-dependent |
| **UR-10** | Migration/artifact retention policy (count/size/age/naming/location) including durability artifacts | Parameters unspecified |
| **UR-11** | Lifecycle key and net closed-trade aggregation unit in hedging/netting (deal/position/lineage/magic+symbol) and INOUT successor-link rules | MT5 deal-stream mapping must be precise |
| **UR-12** | Handling of broker fees/credits/adjustments not representable in `DEAL_PROFIT/COMMISSION/SWAP` (classification, attribution, manual review triggers) | Broker-specific evidence limits |
| **UR-13** | Default `RealizedRiskRef` for `REALIZED_ONLY` (proposed `DayStartBalance`) and allowed alternatives | Must be explicitly chosen/approved |
| **UR-14** | When a multi-day lifecycle's final outcome occurs, whether and how it may satisfy "valid trading day" for prior days in any prop mode (default proposed: no, only final-outcome day) | Prop-rule dependent |

---

## 12. Superseded Prior Draft Sections

Phase 1 and 1.1 sections on formulas, daily DD coupling, HWM handling, baseline capture, trade/PnL attribution, equity sourcing, and prop governance are **superseded/integrated** by §3–§6 and §10 of this revision. §1 preserves original audit findings (D1–D10, A1–A5, R1–R9) and verified facts (extended with Phase 1.2 verified implementation facts).

---

## 13. USER APPROVAL REQUIRED

> Only decisions that genuinely require explicit user confirmation are listed. **Nothing in this document is user-approved.**

1. **Adopt U-01..U-17 and Phase 1.2 corrections (§3.1–§3.7, updated §4–§8, §10)** as binding design direction, or provide edits/rejections per item.
2. **UR-01:** Approve per-preset/per-mode mappings (Static/Trailing, daily/total refs, daily policy, `RealizedRiskRef`, reset/boundary) for FTMO/MFF/FundedNext/The5ers/custom, acknowledging prop rules differ by firm/contract.
3. **UR-02/UR-13:** Approve `ProfitRef` and `RealizedRiskRef` defaults/allowed options.
4. **UR-03:** Approve `WORST_OF` enablement/composition and selection mode (`WORST_PCT` vs `WORST_MONEY`).
5. **UR-04:** Approve epsilon values and breach comparison strictness.
6. **UR-05/UR-14:** Approve "valid trading day" criteria and multi-day lifecycle attribution for min-trading-days/consistency.
7. **UR-06:** Approve reset-boundary config schema, DST handling, and `EXACT_AT_BOUNDARY` tolerance.
8. **UR-07:** Approve manual cashflow-resolution outcomes and explicitly confirmed non-weakening reference-change cases (if any).
9. **UR-08:** Approve upward HWM catch-up policy after verified gap (auto post-verification vs hold-for-confirmation).
10. **UR-09:** Approve total-restriction recovery/manual-authorization workflow, non-recoverable cases, and allowed actions while HWM-dirty/protective-blocked.
11. **UR-10:** Approve migration/artifact retention policy.
12. **UR-11:** Approve lifecycle/aggregation key and hedging/netting/INOUT decomposition rules for final outcomes.
13. **UR-12:** Approve handling of non-deal-representable broker fees/credits/adjustments.
14. **Implementation gate:** Approve proceeding to implementation phase (with coordinated contract/doc/version handling per U-01, no weakening of fail-safe, and durable HWM save-on-new-high blocking semantics) and dependency order in §9.

---

## 14. Final Note (Stop)

Phase 1.2 design corrections applied to this document only. **No MQL5 source, existing contracts/docs, or `MM_CONTRACT_VERSION` changed. No implementation performed. No tests executed.** Original audit findings preserved in §1. Await explicit user approval on §13 before any implementation.
