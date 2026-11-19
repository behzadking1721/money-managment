# Phase 1.3 — Decision Register (U-01..U-17, UR-01..UR-14)

**Project:** `D:\Amoozesh\programing\money managment`  
**Date:** 2026-11-18  
**Status discipline:** statuses are evidence-based per item (`VERIFIED`, `RECOMMENDED`, `NEEDS_USER_DECISION`, `BLOCKED_BY_SOURCE`, `DEFERRED`). **No decision is user-approved.**  
**Sources:** `Docs/Design/PHASE_1_3_SOURCE_VERIFICATION.md`, current source under `MoneyManager.mq5`, `Include/**`, `Tests/**`, and docs in `Docs/**`.

---

## 1. UR Numbering Ambiguity (must be resolved explicitly)

**VERIFIED fact:** `Docs/Design/DRAWDOWN_PERSISTENCE_CONTRACT_DESIGN.md` (Phase 1.2) lists **UR-01..UR-12** in §11 and also introduces **UR-13** and **UR-14** in the same section and in §13 approval items (default/selection of `RealizedRiskRef` and multi-day lifecycle attribution for min-trading-days/consistency). The request for this phase also enumerates UR-01..UR-12 and requires resolving UR-13/UR-14 ambiguity without discarding any item.

**Resolution (proposed, not approved):** retain **all** items as **UR-01..UR-14** with definitions below (UR-13 = `RealizedRiskRef` default/options; UR-14 = valid-trading-day/multi-day lifecycle attribution details). No item discarded. User must confirm numbering/content as part of approval.

---

## 2. U-01 through U-17 Register

| ID | Decision statement (Phase 1.2) | Status | Current source behavior (VERIFIED) | Recommended/default (evidence-based, not approved) | Why / risks | Dependencies | User approval mandatory? |
|---|---|---|---|---|---|---|---|
| **U-01** | Separately versioned persistence schema; coordinate `MM_CONTRACT_VERSION` only when public contracts change; propose v2 if required | **RECOMMENDED / NEEDS_USER_DECISION** | `CStateStore` stores/compares `version` vs `MM_CONTRACT_VERSION` (`Include/State/StateStore.mqh:191,261-276`); `MM_CONTRACT_VERSION 1` (`Include/Core/Contracts.mqh:8`); `Docs/contracts.md` couples schema evolution to contract version. No separate persistence schema version. | **RECOMMENDED:** introduce `persistenceSchemaVersion=2` in state payload for state-only evolution; keep `MM_CONTRACT_VERSION` unchanged unless public/shared contract structs/semantics change. Requires explicit migration hook and future-version fail-safe. | Aligns with scope separation and avoids unnecessary public-contract churn; **risk:** migration complexity and doc/code coupling must be corrected carefully. | Blocks/feeds schema/migration (UR-10), all persisted-field additions (D3/D5/D9/D10, §3.3–§3.7). | **Yes** |
| **U-02** | Support both Static and Trailing Maximum Drawdown as explicitly selected models | **RECOMMENDED / NEEDS_USER_DECISION** | Trailing peak equity in `CurrentDrawdownPct` and mixed peak/start logic in `CheckMaxDrawdown/RemainingMaxDDMoney` (`Include/Protection/Protection.mqh:79-128`); prop uses `ddReference` to pick refs (`Include/PropFirm/PropFirm.mqh:85-120`) but no explicit static-vs-trailing total model selector. | **RECOMMENDED:** first-class explicit model `TRAILING_HWM` or `STATIC_INITIAL` per mode/profile/prop rule, independent of daily settings; preset mapping configurable (UR-01). | Eliminates ambiguity (C3,R7); **risk:** wrong mapping to firm rules causes breaches/missed enforcement. | UR-01, UR-08 (catch-up interacts with trailing), U-03. | **Yes** |
| **U-03** | Separate, unambiguous Balance and Equity semantics for Daily DD and Total DD | **RECOMMENDED / NEEDS_USER_DECISION** | Mixed/overloaded refs and defaults across `CProtection`, `CPropFirm`, EA guard/risk context (`MoneyManager.mq5:103-223`). | **RECOMMENDED:** explicit daily reference series and total reference series (each balance/equity) + model where applicable; no inference from single flag. | Prevents misapplication across firms (R7); **risk:** config complexity. | UR-01, U-02, U-04, UR-13. | **Yes** |
| **U-04** | Default daily enforcement to DayStartEquity vs CurrentEquity; support alternatives for prop rules | **RECOMMENDED / NEEDS_USER_DECISION** | Current default daily loss/profit/remaining uses day-start **balance** (`Include/Protection/Protection.mqh:69-76,87-93`); EA feeds guard daily pct from that balance ref (`MoneyManager.mq5:170`). Prop can reference day-start equity/balance for daily helpers (`PropFirm.mqh:85-112`). | **RECOMMENDED:** default `EQUITY_SNAPSHOT = max(0,DayStartEquity-CurrentEquity)` with mandatory `DayStartEquity` denominator (§3.2), alternatives `BALANCE_SNAPSHOT`, `REALIZED_ONLY` (UR-13), `WORST_OF` (UR-03) configurable per profile/prop rule. | Captures floating+realized intraday risk per proposed default; **risk:** behavior change vs current users and firm-specific rules must override. | U-03, UR-03, UR-13, UR-04, baseline capture §3.4. | **Yes** |
| **U-05** | Realized daily PnL net of applicable trading costs; explicit denominator/reference for profit percentages | **RECOMMENDED / NEEDS_USER_DECISION / PARTIALLY BLOCKED_BY_SOURCE** | Deal components recorded as `DEAL_PROFIT+DEAL_COMMISSION+DEAL_SWAP` per close deal in EA (`MoneyManager.mq5:374`) and per-deal in lifecycle (`Include/Trade/TradeLifecycle.mqh:125-127`); no lifecycle aggregation/dedupe. Profit pct ref defaults to day-start balance in protection (`Protection.mqh:74-78`). | **RECOMMENDED:** net realized components from unique deals aggregated at lifecycle/attribution level with idempotent dedupe (§3.1); `DailyProfitPct = max(0,RealizedDayPnL_net)/ProfitRef*100` with explicit configurable `ProfitRef` (candidate default `DayStartBalance`, UR-02). Broker fees/credits outside deal fields handled via UR-12 policy. | Aligns with accounting reality; **risk:** incomplete without dedupe/reconciliation and history completeness (UR-11,UR-12). | UR-11, UR-12, UR-02, U-01 (schema). | **Yes** |
| **U-06** | Profit target/consistency default to realized closed-trade results unless prop rule specifies otherwise | **RECOMMENDED / NEEDS_USER_DECISION** | Prop profit target uses balance delta vs in-memory `m_startBalance` (`PropFirm.mqh:50-55`); consistency uses in-memory `m_dailyProfits[]` fed by `RecordTradingDay(g_prot.DailyProfit())` with coarse local day increment (`PropFirm.mqh:29-47`, `MoneyManager.mq5:376`). Not restart-safe. | **RECOMMENDED:** default to realized closed-trade/lifecycle outcomes keyed by `tradingDayId`, persisted; prop-rule override only if explicit/configured and documented. | Prevents floating-inclusive or resettable targets; **risk:** mapping to firm-specific definitions (UR-01,UR-14). | U-05, U-07, U-09, UR-01, UR-14, U-01. | **Yes** |
| **U-07** | Consecutive wins/losses by net closed-trade outcomes; specify resets, scope, zero-result handling | **RECOMMENDED / NEEDS_USER_DECISION** | `CProtection::RecordTrade` per call: `>0` win, `<0` loss, `==0` no streak change but increments trade count (`Protection.mqh:52-57`). Streaks/cooldown not persisted. | **RECOMMENDED:** outcome from **final lifecycle outcome** net (`LifecycleNetPnL`) with `eps_pnl` (UR-04); WIN/LOSS/BREAKEVEN rules, persisted, scoped to bound identity/profile context; no auto daily reset by default; cooldown persisted per U-08 time authority. | Avoids per-deal/partial streak noise and restart loss; **risk:** depends on lifecycle aggregation correctness (UR-11). | UR-11, UR-04, U-01, U-15, U-08. | **Yes** |
| **U-08** | One authoritative trading-day time service; default broker server time; configurable prop-firm reset boundaries | **RECOMMENDED / NEEDS_USER_DECISION** | Store uses server-preferred `EffectiveServerTime`/keys but EA also resets by local `TimeCurrent().day` (`StateStore.mqh:60-69,185-189,296-299`, `MoneyManager.mq5:303-311`). No configurable boundary. | **RECOMMENDED:** single `TradingDayTimeService` (effective time, fallback flag, `ScheduledBoundary`, `tradingDayId`, boundary detection) consumed everywhere; default server, configurable `SERVER_MIDNIGHT/HHMM/offset` per profile/prop (UR-06). | Eliminates D6/R3; **risk:** DST/offset misconfig. | UR-06, U-09, §3.4, U-01. | **Yes** |
| **U-09** | Count each valid trading day exactly once using a persisted trading-day identifier | **RECOMMENDED / NEEDS_USER_DECISION** | `CPropFirm::RecordTradingDay` increments on local day change via static variable, non-persisted/idempotent (`PropFirm.mqh:39-47`). | **RECOMMENDED:** persisted `tradingDayId` and once-per-id counting when valid-day criteria met (UR-05/UR-14), idempotent across restarts/calls. | Fixes min-days correctness (D10,R6); **risk:** criteria vary by firm. | U-08, UR-05, UR-14, U-01. | **Yes** |
| **U-10** | Detect/record deposits and withdrawals; never auto-weaken; ambiguous => manual review | **RECOMMENDED / NEEDS_USER_DECISION** | No cashflow detection/ledger/manual-review state in inspected code; balance changes can implicitly affect current-seeded defaults (S-06). | **RECOMMENDED:** balance checkpoint + unexplained-delta detection, record events, set `requiresManualReview` on ambiguity, never auto-weaken protective baselines/limits; explicit confirmed resolution workflow (UR-07). | Prevents silent protection weakening (R1,R7); **risk:** classification limits (UR-12). | UR-07, UR-12, UR-04 (epsilon), U-01, U-17. | **Yes** |
| **U-11** | Bind persisted state to Login, Server, Account Mode, Profile identity | **RECOMMENDED / NEEDS_USER_DECISION** | Login-only state/profile file keys (`StateStore.mqh:105-117`, `Profiles.mqh:132,139,174-215`); no server binding; mode/profile not enforced as binding gate. | **RECOMMENDED:** bind identity tuple `{login,server,accountMode,profileId,propProfileId?}` for load/apply/write; mismatch => fail-safe/manual review or correct bound load. | Prevents cross-context restore; **risk:** migration/path encoding and multi-profile partitions. | U-01, U-17, UR-10. | **Yes** |
| **U-12** | Retain migration info and previous valid state versions for recovery/diagnostics | **RECOMMENDED / NEEDS_USER_DECISION** | Single overwritten `.bak` only (`StateStore.mqh:159-174`); no migration log or retained originals. | **RECOMMENDED:** retain pre-migration original, migration log (from/to/time/lossy fields/outcome), and previous/last-known-good artifacts with bounded retention (UR-10); include durability-recovery artifacts where applicable. | Forensics/recovery (C6); **risk:** storage growth/retention policy. | UR-10, U-01. | **Yes** |
| **U-13** | Adequate internal precision; defined comparison epsilon; round only for display/broker execution | **RECOMMENDED / NEEDS_USER_DECISION** | `double` math throughout; direct `>=` comparisons common; formatting via `DoubleToString` in places. No formal epsilon contract. | **RECOMMENDED:** keep internal `double`, define named epsilons (`eps_money`, `eps_pct`, `eps_pnl`, `eps_cashflow`, lot/step) and breach strictness (UR-04); normalize/round only at display and broker constraints. | Reduces edge false/missed breaches (R7); **risk:** wrong epsilon values. | UR-04, U-14. | **Yes** |
| **U-14** | Explicit `DISABLED` limit state, not ambiguous numeric sentinel | **RECOMMENDED / NEEDS_USER_DECISION** | Widespread `>0`/`<=0` sentinel semantics for enabled limits (`Protection.mqh`, `PropFirm.mqh`, guards/config). | **RECOMMENDED:** explicit `ENABLED|DISABLED` (or enabled flag) per limit; migrate legacy sentinels with review where ambiguous. | Removes ambiguity in reporting/enforcement; **risk:** broad refactor/migration mapping. | U-01 (schema), UR-03/UR-04 interactions. | **Yes** |
| **U-15** | Daily restrictions clear only on valid daily rollover; total restrictions require defined recovery/manual authorization | **RECOMMENDED / NEEDS_USER_DECISION** | Daily counters reset on day change; `CheckConsecutiveLoss` auto-clears cooldown on expiry (`Protection.mqh:129-137`); no persistent breach/lockout states. | **RECOMMENDED:** persist breach/lock scope; daily-scoped clears only on valid authoritative rollover (U-08/U-09); total-scoped requires defined recovery or explicit manual authorization (audited) (UR-09). Protective blocks allowed for HWM-dirty/integrity per §3.3/§6. | Prevents bypass after restart/expiry (D5,R2); **risk:** overly strict lockouts if recovery undefined. | U-08,U-09,UR-09,U-01,U-16. | **Yes** |
| **U-16** | Strict HWM restore; higher live updates only after verified identity/integrity; record startup-gap; (with §3.3) durability/blocking | **RECOMMENDED / NEEDS_USER_DECISION** | `EnsureBaselines/SyncPeaks` bump peaks to current (`StateStore.mqh:91-100,338-340`, `Protection.mqh:47-51,65-66`); EA syncs frequently but saves rarely (E-03); no dirty/commit markers or block on unsaved HWM. | **RECOMMENDED:** treat persisted HWM as durable authority on restore; upward catch-up only after verified identity/integrity and approved policy (UR-08), record startup-gap; save-on-new-high with durable commit and `hwmDirty`; block new risk-increasing actions when latest HWM not durably saved/unpersisted-peak suspected (§3.3). | Core to trailing DD correctness (D1,R1,C-05); **risk:** trading blocked during persistence failures (intentional fail-safe). | U-11,U-17,UR-08,UR-09,U-01. | **Yes** |
| **U-17** | On restored/live disagreement apply fail-safe; never silently replace protective baselines | **RECOMMENDED / NEEDS_USER_DECISION** | Missing state seeds current and saves; load has limited fail-safe (future-version only) and no `.bak` integrity recovery; no `requiresManualReview` (`StateStore.mqh:243-303`). | **RECOMMENDED:** material disagreement/integrity/identity/cashflow/history ambiguity => fail-safe or restricted mode, block risk-increasing actions, `requiresManualReview`, preserve artifacts, explicit confirmed recovery; never silent rebaseline. | Prevents unsafe auto-recovery (D7,R4,R9); **risk:** availability/operational friction, requires UX flow. | U-10,U-11,U-12,U-16,UR-07,UR-12. | **Yes** |

---

## 3. UR-01 through UR-14 Register (each resolved as recommendation or explicit open choice)

### UR-01 — Preset and mode configuration (Static/Trailing, daily/total refs, daily policy, `RealizedRiskRef`, reset/boundary per preset/mode)

| Field | Content |
|---|---|
| **Exact question** | For each supported mode/profile/preset (Personal, Prop: FTMO/MFF/FundedNext/The5ers, Crypto, custom), what are the authoritative selections for: total DD model (static/trailing), daily reference series, total reference series, daily enforcement policy, `RealizedRiskRef`, reset boundary policy, and other prop-specific toggles? |
| **Current source behavior (VERIFIED)** | Hardcoded presets in `Include/PropFirm/PropFirm.mqh:17-28` (FTMO: equity refs, daily 5, total 10, target 10, min 4; MFF: balance refs, total 12, target 8, min 5, consistency 40; FundedNext: funded equity refs, total 10, target 0; The5ers: challenge balance refs, total 10, target 6, max position 2). `DD_FROM_EQUITY/BALANCE` in `Include/Utils/Common.mqh:24`. No explicit static-vs-trailing model flag; daily enforcement measure not parameterized as EQUITY_SNAPSHOT/BALANCE_SNAPSHOT/REALIZED_ONLY/WORST_OF. Profiles store some limits/news/spread (`Include/Profiles/Profiles.mqh`). |
| **Available options** | (A) Treat code presets as **non-authoritative templates** requiring explicit selection + metadata (source/effective date/version, §3.7). (B) Encode firm rules as verified built-ins (not possible without verified contracts). (C) Fully custom rule engine per profile. |
| **Advantages / disadvantages** | (A) Flexible and auditable; needs user/config input. (B) Low effort but **unsafe/unverifiable**. (C) Powerful but complex UI/schema. |
| **Financial/operational risks** | Wrong model/ref/policy can allow breach or false lockout; prop contracts differ and change. |
| **Recommended default** | **RECOMMENDED:** (A) + (C-lite): ship editable templates labeled `TEMPLATE` with `ruleSource`, `profileVersion`, `ruleEffectiveDate`, `accountTypeStage`; require explicit confirmation before enforcement; do not claim presets are verified firm rules. Keep account-level protection configurable separately. |
| **User approval mandatory?** | **Yes** — per-preset/mode mappings and template truthfulness cannot be inferred from source. |
| **Dependencies** | U-02,U-03,U-04,U-08, UR-02,UR-03,UR-05,UR-06,UR-13, §3.7. |
| **Status** | **NEEDS_USER_DECISION** (blocked on firm/rule confirmation). |

### UR-02 — ProfitRef and (baseline profit denominator) configuration

| Field | Content |
|---|---|
| **Exact question** | What is the explicit `ProfitRef` for `DailyProfitPct` (and related profit percent displays) per mode/rule, and what options are allowed? |
| **Current source behavior (VERIFIED)** | `CProtection::DailyProfitPct` uses day-start balance as ref (`Include/Protection/Protection.mqh:74-78`). No configurable profit reference. |
| **Available options** | `DayStartBalance` (current-like), `DayStartEquity`, `InitialBaselineBalance/Equity` (static context), or per-rule configurable. |
| **Advantages / disadvantages** | Day-start balance stable intraday for realized profit; day-start equity consistent with equity-snapshot daily DD default; initial baseline aligns to some target definitions but may differ from firm rules. |
| **Financial/operational risks** | Wrong denominator misreports progress/locks. |
| **Recommended default** | **RECOMMENDED:** configurable `ProfitRef` with default **`DayStartBalance`** for backward-alignment, but allow `DayStartEquity` where profile/prop rule selects equity basis; document choice per profile. (User must confirm default.) |
| **User approval mandatory?** | **Yes** (behavioral/reporting choice). |
| **Dependencies** | U-05,U-06,U-03, UR-01. |
| **Status** | **NEEDS_USER_DECISION** (recommended default proposed). |

### UR-03 — `WORST_OF` composition and selection

| Field | Content |
|---|---|
| **Exact question** | Is `WORST_OF` enabled? If so, which daily components may be included, and is the governing component selected by `WORST_PCT` or `WORST_MONEY` (and how with multiple limits)? |
| **Current source behavior (VERIFIED)** | No `WORST_OF` policy; daily enforcement is effectively single-path (balance-realized oriented in protection) (`Protection.mqh:69-76,87-93`). |
| **Available options** | (A) Disable `WORST_OF` initially. (B) Enable over subset {EQUITY_SNAPSHOT,BALANCE_SNAPSHOT,REALIZED_ONLY} with per-component mandatory denominators. Selection: `WORST_PCT` (max % used) or `WORST_MONEY` (min remaining / max used abs) — must be explicit and consistently reported. |
| **Advantages / disadvantages** | (A) Simpler/safer to validate. (B) Covers stricter prop interpretations but increases config/test complexity. |
| **Financial/operational risks** | Mis-specified composition can over/under-restrict; inconsistent reporting confuses operators. |
| **Recommended default** | **RECOMMENDED:** support `WORST_OF` as **configurable option disabled by default**; when enabled, require explicit component set and explicit selector (`WORST_PCT` **or** `WORST_MONEY`, default `WORST_PCT` recommended for percentage-based limits) with per-component denominators per §3.2. |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-04, §3.2, UR-01, UR-04, UR-13. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-04 — Epsilon values and breach comparison strictness

| Field | Content |
|---|---|
| **Exact question** | What are `eps_pnl`, `eps_money`, `eps_pct`, `eps_cashflow` (and any lot/step epsilon), and should breaches trigger on `>= Allowed - eps_cmp` or strictly `>`? |
| **Current source behavior (VERIFIED)** | Direct comparisons with `>=` in several checks (e.g. `DailyLossPct()>=limitPercent`, `m_dailyLoss/ref*100.0>=m_rules.maxDailyLoss`, drawdown `>=maxDDPercent`, trades `>=maxTrades`) in `Include/Protection/Protection.mqh:109,112,122,126,129,132` and guards (`PropGuard.mqh`, `ProtectionGuard.mqh`). No named epsilons. |
| **Available options** | Define per-domain epsilons (e.g. money 0.01 in account currency or symbol-appropriate; pct 1e-9–1e-6; pnl 0.00 default for breakeven band configurable); keep `>=` semantics with epsilon-adjusted threshold, or adopt documented strictness per rule. |
| **Advantages / disadvantages** | Epsilons reduce floating-point noise; too large can delay/skip true breaches (unsafe), too small can be noisy. |
| **Financial/operational risks** | Off-by-epsilon near limits can materially affect prop compliance; must err conservative for protection. |
| **Recommended default** | **RECOMMENDED (provisional):** `eps_pnl=0.00` (configurable), `eps_money=0.01` (or currency precision), `eps_pct=1e-6`, `eps_cashflow=0.01` (configurable), breach on `Used >= Allowed - eps_cmp` with `eps_cmp = min(eps_money, Allowed*eps_pct)`-style conservative choice — **values require user approval**. |
| **User approval mandatory?** | **Yes** (numeric policy). |
| **Dependencies** | U-13, U-07, U-10, §4.5. |
| **Status** | **NEEDS_USER_DECISION** (numeric values unconfirmed). |

### UR-05 — "Valid trading day" criteria for `minTradingDays`

| Field | Content |
|---|---|
| **Exact question** | What constitutes a valid trading day for `minTradingDays` (e.g. any placed trade, any closed trade, any final lifecycle outcome, or prop-specific) and how is it counted once per `tradingDayId`? |
| **Current source behavior (VERIFIED)** | `CPropFirm::RecordTradingDay` increments `m_tradingDays` when local day changes (static `lastDay`) and appends daily profit (`PropFirm.mqh:39-47`), called from EA on deal close path with `g_prot.DailyProfit()` (`MoneyManager.mq5:376`). Not tied to a clear "valid day" definition beyond call timing. |
| **Available options** | (A) Day with ≥1 **final lifecycle outcome** (recommended alignment with §3.1.4). (B) Day with ≥1 executed/opened trade. (C) Day with ≥1 qualifying realized close event (deal-level). (D) Fully prop-rule configurable. |
| **Advantages / disadvantages** | (A) Consistent with outcome-based metrics; (B/C) may satisfy some firms but easier to game/ambiguous. (D) required for correctness across firms. |
| **Financial/operational risks** | Miscount can fail/pass prop evaluation incorrectly. |
| **Recommended default** | **RECOMMENDED:** configurable per prop profile; default **(A) at least one final lifecycle outcome on `tradingDayId`**, counted once per id (U-09). |
| **User approval mandatory?** | **Yes** (firm-dependent). |
| **Dependencies** | U-09, UR-14, UR-11, UR-01. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-06 — Trading-day boundary config schema and DST handling

| Field | Content |
|---|---|
| **Exact question** | How are reset boundaries represented/configured (`SERVER_MIDNIGHT`, `SERVER_HHMM`, `FIXED_UTC_OFFSET_HHMM`, timezone id), what DST behavior applies, and what tolerance defines `EXACT_AT_BOUNDARY` vs `DELAYED_CAPTURE`? |
| **Current source behavior (VERIFIED)** | Store day key = server `yyyymmdd` (`StateStore.mqh:60`); EA day reset uses local `TimeCurrent().day` (`MoneyManager.mq5:303`). No HH:MM/offset config, no capture status. Session manager has simple DST helpers for sessions (`Include/Session/SessionManager.mqh`) but not wired as trading-day reset authority. |
| **Available options** | Store policy enum + hour/minute + offset minutes (+ optional tz label string); define `EXACT_AT_BOUNDARY` if `abs(ActualCaptureTime - ScheduledBoundary) <= toleranceSec` (tolerance configurable). DST: explicit "broker/server clock as-is" vs offset-based rules — must be profile-documented. |
| **Advantages / disadvantages** | Server-as-is simplest; offset/tz flexible but error-prone. |
| **Financial/operational risks** | Wrong boundary misattributes daily DD and min-days (high for prop). |
| **Recommended default** | **RECOMMENDED:** default `SERVER_MIDNIGHT` on effective server date; allow `SERVER_HHMM` and `FIXED_UTC_OFFSET_HHMM` as explicit config; `EXACT_AT_BOUNDARY` tolerance default **60s** (provisional, needs approval); require profile to state DST assumption (no silent DST inference). |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-08, §3.4, UR-01. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-07 — Cashflow resolution outcomes and non-weakening reference changes

| Field | Content |
|---|---|
| **Exact question** | What explicit user-confirmed resolution outcomes are allowed for detected/ambiguous cashflow events, and under what (if any) confirmed cases may protective references change without violating "never automatically weaken protection"? |
| **Current source behavior (VERIFIED)** | No detection, no ledger, no manual-review workflow (S-02/E). |
| **Available options** | Outcomes: classify as `DEPOSIT`, `WITHDRAWAL`, `BROKER_CREDIT/BONUS`, `FEE/ADJUSTMENT`, `TRADE_RECONCILED`, or `UNKNOWN_KEEP_LOCKED`; actions: keep baselines unchanged, adjust baselines/HWM by explicit signed amount, or rebaseline/reset period **only** with explicit confirmation + audit + conservative constraints. "Non-weakening" examples (policy-dependent): withdrawal may require reducing static baseline/HWM allowance or keeping stricter view; deposit may be ignored for trailing HWM (no retrospective lowering) or handled per approved rule. |
| **Advantages / disadvantages** | Strict lock safest but operationally heavy; flexible resolutions usable but risky if misapplied. |
| **Financial/operational risks** | Any incorrect reclassification can weaken protection or unfairly block trading. |
| **Recommended default** | **RECOMMENDED:** default state = `requiresManualReview` + block risk-increasing actions for unresolved/ambiguous deltas; permitted confirmed actions must be enumerated and audited; **never** auto-apply; allow only changes that are provably non-weakening for the active model/ref or that are explicit "new baseline/reset" actions with strong confirmation. Exact matrix is **user policy**. |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-10, U-17, U-16, UR-04, UR-12, §3.3. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-08 — Upward HWM catch-up after verified offline/startup gap

| Field | Content |
|---|---|
| **Exact question** | After identity/integrity verification, if live equity exceeds persisted durable HWM (gap while offline), should system auto-apply `HWM=max(durable,live)` or hold for explicit confirmation? |
| **Current source behavior (VERIFIED)** | `EnsureBaselines/SyncPeaks` always bump to current (`StateStore.mqh:98-99,338-340`, `Protection.mqh:47-51`). No gap recording, no verification gate. |
| **Available options** | (A) **Auto catch-up post-verification** to `max` and record startup-gap event (captures true new high but relies on verification). (B) **Hold at durable HWM** and require confirmation before upward move (stricter, may understate HWM until confirmed). (C) Treat as `UNPERSISTED_PEAK_SUSPECTED` when evidence of missed persistence exists (§3.3) and block/require review. |
| **Advantages / disadvantages** | (A) Accurate trailing anchor after clean gap; (B/C) conservative against false/dirty states. |
| **Financial/operational risks** | Auto catch-up on bad/incomplete verification can mis-set HWM; failing to catch up can understate trailing DD allowance in some models (model-dependent). |
| **Recommended default** | **RECOMMENDED:** if **no** durability/integrity suspicion and identity+integrity verified, allow **(A) `max(durable,live)` with recorded startup-gap event**; if any suspicion (dirty/incomplete history/cashflow ambiguity), force **(C)** manual review and block risk-increasing actions. User must confirm policy. |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-16, §3.3, U-17, U-11. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-09 — Total-restriction recovery/manual-authorization workflow

| Field | Content |
|---|---|
| **Exact question** | What is the defined recovery/manual-authorization workflow for total/Max-DD (and other non-daily) restrictions, including non-recoverable cases, and which actions (if any) are allowed while HWM-dirty/protective-blocked? |
| **Current source behavior (VERIFIED)** | No persistent total breach lockout workflow; cooldown auto-clears on expiry (`Protection.mqh:129-137`); no HWM-dirty state. |
| **Available options** | Define per model/profile: `NON_RECOVERABLE_IN_PERIOD` (prop), `RECOVERABLE_ON_RESET_EVENT` (explicit baseline/reset with audit), or `MANUAL_AUTH_REQUIRED` (confirmed override with reason). While protective-blocked/HWM-dirty: allow only risk-reducing/close/diagnostic actions (recommended) vs allow none except recovery. |
| **Advantages / disadvantages** | Strict non-recoverable matches some prop rules; configurable recovery needed for personal accounts/errors. |
| **Financial/operational risks** | Unauthorized recovery defeats protection; excessive blocking harms operability. |
| **Recommended default** | **RECOMMENDED:** default **MANUAL_AUTH_REQUIRED** with explicit confirmation + audit for any total-restriction clear/reset in personal mode; prop profiles may set `NON_RECOVERABLE_IN_PERIOD` as configured rule; while HWM-dirty or fail-safe active allow **risk-reducing and read-only/diagnostic actions only** (no new/increased exposure). User must confirm. |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-15, U-16, §3.3, §3.7, U-17. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-10 — Migration/artifact retention policy

| Field | Content |
|---|---|
| **Exact question** | What retention policy applies to migration artifacts and previous valid state versions (count/size/age, naming, location, including HWM/durability artifacts)? |
| **Current source behavior (VERIFIED)** | Single `.bak` overwritten on save (`StateStore.mqh:159-174`). No migration originals/log retention. |
| **Available options** | Keep N last-known-good snapshots + pre-migration original + migration logs; rotate by count/age/size; store under `MoneyManager\archive\` or alongside state with deterministic names; include integrity metadata. |
| **Advantages / disadvantages** | More retention aids recovery/forensics; increases disk use and management complexity. |
| **Financial/operational risks** | Too little retention blocks recovery; too much without cleanup can bloat FILE_COMMON storage. |
| **Recommended default** | **RECOMMENDED (provisional):** retain at least **pre-migration original (once per migration)** + **last 5 known-good committed snapshots** + **migration log entries** (append/rotate by size/count), bounded total size (e.g. configurable, default modest). Exact numbers/location **need approval**. |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-12, U-01, §3.3 (durability artifacts). |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-11 — Lifecycle/aggregation key and hedging/netting/INOUT decomposition

| Field | Content |
|---|---|
| **Exact question** | What is the stable lifecycle aggregation key and how are hedging, netting, partial closes, and INOUT reversals decomposed into a complete trade/final outcome? |
| **Current source behavior (VERIFIED)** | TradeLifecycle emits per-deal events keyed by deal/order/`positionId` with `PositionStillOpen` heuristic and INOUT comment (`Include/Trade/TradeLifecycle.mqh:41-53,110-158`). EA/Protection account per deal (`MoneyManager.mq5:368-378`). Statistics aggregates by `positionId` opportunistically (`Include/Statistics/Statistics.mqh`). No dedupe/reconciliation. `IsHedgingAccount()` helper exists (`Include/Utils/Common.mqh:107`) but not used in inspected aggregation paths. `Docs/contracts.md` notes netting/hedging parity deferred. |
| **Available options** | (A) **Hedging:** lifecycle key = `(boundIdentity, positionId/ticket lineage, symbol, magic)` per position; (B) **Netting:** key = `(boundIdentity, positionIdentifier/positionId lineage per symbol+side context)` with volume-to-flat finalization; INOUT = close-component of existing exposure + linked successor exposure component evidenced by deals. (C) Use MT5 history `HistorySelectByPosition`/deal iteration for reconciliation where available (not currently used in source — **BLOCKED_BY_SOURCE for current impl**). |
| **Advantages / disadvantages** | Position/identifier-based keys align with MT5; heuristics risky without runtime validation. History reconciliation improves correctness but depends on broker history completeness. |
| **Financial/operational risks** | Wrong key/decomposition => double-count or missed PnL/streaks; high impact on DD/protection. |
| **Recommended default** | **RECOMMENDED:** define explicit per-account-margin-mode rules: hedging by position ticket/id lifecycle; netting by position identifier/volume-to-flat with deal-ordered decomposition and successor linkage for reversals; require unique deal-id idempotency and restart reconciliation from checkpoint; mark `degraded/HISTORY_INCOMPLETE` when evidence insufficient (§3.6). **Must be validated in hedging and netting demos (TD-02) before freeze.** |
| **User approval mandatory?** | **Yes** (semantic choice) + **runtime evidence required**. |
| **Dependencies** | U-05,U-06,U-07, §3.1,§3.5, A, TD-02. |
| **Status** | **NEEDS_USER_DECISION / BLOCKED_BY_SOURCE** (runtime semantics unverified). |

### UR-12 — Broker fees, credits, and adjustments not representable in deal fields

| Field | Content |
|---|---|
| **Exact question** | How are broker fees/credits/bonuses/adjustments not captured in `DEAL_PROFIT/COMMISSION/SWAP` classified, attributed, and surfaced (especially for cashflow detection and realized PnL integrity)? |
| **Current source behavior (VERIFIED)** | Realized components taken only from deal fields (`MoneyManager.mq5:374`, `TradeLifecycle.mqh:125-127`). No balance-operation classification. |
| **Available options** | (A) Treat unexplained balance deltas as `cashflow_event` with `requiresManualReview` (U-10). (B) Allow configured adjustment categories with audited manual classification. (C) Attempt inference from history operations (not implemented; broker-dependent). |
| **Advantages / disadvantages** | (A) safest; (B) operationally flexible; (C) unreliable/complex. |
| **Financial/operational risks** | Misattribution can distort realized PnL, DD, and prop metrics. |
| **Recommended default** | **RECOMMENDED:** default **(A)** — do not include non-deal balance operations in trading realized PnL; detect/record as cashflow/integrity events requiring review unless explicitly and evidentially classified per approved workflow (UR-07). |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-10, UR-07, UR-04, U-17. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-13 — `RealizedRiskRef` default and allowed options (numbering ambiguity resolved as item)

| Field | Content |
|---|---|
| **Exact question** | For `REALIZED_ONLY` daily policy, what is the explicit `RealizedRiskRef` denominator (and allowed options) used to compute allowed/used % and remaining budget? |
| **Current source behavior (VERIFIED)** | No `REALIZED_ONLY` policy and no `RealizedRiskRef` concept; current daily ref is day-start balance in protection paths (`Protection.mqh:69-76,87-93`). |
| **Available options** | `DayStartBalance`, `DayStartEquity`, `InitialBaseline*` (static), or profile-configurable. |
| **Advantages / disadvantages** | Day-start balance consistent with realized-balance movement; day-start equity consistent with equity-based profiles; baseline aligns to static targets but less "daily". |
| **Financial/operational risks** | Incompatible choice distorts % and breach timing. |
| **Recommended default** | **RECOMMENDED:** default **`DayStartBalance`** for `REALIZED_ONLY` (provisional), allow `DayStartEquity` as configured alternative; must be explicitly stored/configured per profile/rule (no inference). |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | U-04, §3.2, UR-01, UR-02. |
| **Status** | **NEEDS_USER_DECISION**. |

### UR-14 — Valid-trading-day/multi-day lifecycle attribution details (numbering ambiguity resolved as item)

| Field | Content |
|---|---|
| **Exact question** | When a lifecycle spans multiple trading days, which day(s) receive min-trading-day credit and how are consistency inputs attributed (final-outcome day only vs any day with qualifying realized component), per prop rule? |
| **Current source behavior (VERIFIED)** | No lifecycle final-outcome accounting; prop counts days on local day change during `RecordTradingDay` calls and pushes same-day profit snapshots (`PropFirm.mqh:39-47`, `MoneyManager.mq5:376`). No multi-day lifecycle model. |
| **Available options** | (A) **Final-outcome day only** for streak/min-trading-day credit (default proposed in §3.1.4), with daily realized PnL/consistency components attributed to each deal's `DealDayId`. (B) Credit any day with qualifying activity/partial realization. (C) Fully prop-rule configurable. |
| **Advantages / disadvantages** | (A) Clear and aligned with "completed trade" outcomes; (B/C) may match specific firm definitions but more complex and easier to dispute. |
| **Financial/operational risks** | Wrong attribution can invalidate prop compliance metrics. |
| **Recommended default** | **RECOMMENDED:** (A) as baseline default, but **configurable per prop profile/rule**; daily realized PnL always attributed by deal day for DD/profit components (§3.1.4) to avoid hiding losses. |
| **User approval mandatory?** | **Yes**. |
| **Dependencies** | UR-05, UR-11, U-06, U-07, U-09, UR-01. |
| **Status** | **NEEDS_USER_DECISION**. |

---

## 4. Recommended Defaults (consolidated, NOT approved)

- **U-01:** `persistenceSchemaVersion=2`, `MM_CONTRACT_VERSION` unchanged absent public contract change.
- **U-02/U-03:** explicit selectable Static/Trailing total DD with separate Daily/Total balance-equity refs.
- **U-04:** default daily enforcement `EQUITY_SNAPSHOT` (`DayStartEquity-CurrentEquity`, denominator `DayStartEquity`).
- **U-05/U-06/U-07:** lifecycle-level net realized aggregation with deal-id dedupe; profit/consistency from realized outcomes; streaks from final lifecycle outcomes with `eps_pnl` breakeven and no auto daily reset.
- **U-08/U-09:** single trading-day time service, server default, configurable boundaries, persisted `tradingDayId`.
- **U-10/U-17:** detect/record cashflows, never auto-weaken, ambiguity => manual review + fail-safe.
- **U-11:** bind to Login+Server+AccountMode+Profile(+prop id).
- **U-12:** retain migration original/log and previous known-good artifacts (bounded policy).
- **U-13/U-14:** named epsilons and explicit `DISABLED` limit states.
- **U-15/U-16:** daily clears only on valid rollover; total requires defined/manual recovery; strict durable HWM restore, save-on-new-high, block on undurably-saved latest HWM/unpersisted-peak suspicion.
- **UR defaults (provisional):** templates non-authoritative (UR-01), `ProfitRef=DayStartBalance` (UR-02), `WORST_OF` off by default (UR-03), conservative epsilons needing numeric approval (UR-04), valid day = final lifecycle outcome by default (UR-05/UR-14), `SERVER_MIDNIGHT` + tolerance provisional (UR-06), cashflow unresolved => review/lock (UR-07), conditional auto HWM catch-up only when verified clean (UR-08), manual-auth/ risk-reducing-only while blocked (UR-09), bounded artifact retention (UR-10), margin-mode-specific lifecycle keys with dedupe/reconciliation (UR-11), non-deal balance ops excluded from trading PnL pending review (UR-12), `RealizedRiskRef=DayStartBalance` provisional (UR-13).

---

## 5. Items Requiring Explicit User Decision (summary)

All **U-01..U-17** and **UR-01..UR-14** require explicit user approval/choice of values or policies (none approved). Highest-risk unresolved choices: UR-01 (firm mappings), UR-03/UR-04/UR-06 (policy/numeric), UR-07/UR-08/UR-09 (recovery/catch-up), UR-11/UR-14 (lifecycle semantics), UR-13 (realized-only ref). Blockers where source/runtime evidence is insufficient: UR-11 hedging/netting runtime parity and history reconciliation behavior (TD-02), MT5 durability/atomicity guarantees (platform), exact historical equity reconstruction (generally unavailable).
