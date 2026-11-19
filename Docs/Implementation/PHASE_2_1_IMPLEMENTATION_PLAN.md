# Phase 2.1 Implementation Plan — StateStore Foundation

**Status:** Planning only (updated per final project decisions; no MQL5 source, contract, or test modifications performed)  
**Branch:** `phase1-foundation` (HEAD `f6b4af8`, working tree: untracked `Docs/Design/`, `Docs/SKILLS_CATALOG.md`, `Docs/Implementation/`)  
**Project priority:** Build a working, reliable MT5 Expert Advisor as soon as reasonably possible. Avoid unnecessary architectural complexity and prolonged design-only work.

## 1. Final Project Decisions (Authoritative for Phase 2.1)

### 1.1 Account data policy
The EA may read MT5-exposed financial/trading information (Balance, Equity, Margin, Free Margin, Margin Level, Floating PnL, open positions, available trading history, symbol trading specifications/restrictions).  
The EA must **not** collect or persist: Account Login, Broker Server, passwords/credentials, personal identity, or prop account identifiers.

### 1.2 Account switching behavior
The EA must support switching to another MT5 trading account. After a switch:
1. Refresh account data from MT5.
2. Recalculate account-dependent metrics using the new account's current data.
3. Never reuse the previous account's live financial values as the new account's values.
4. Never silently apply the previous account's protective baselines, drawdown state, or trading history to the new account.
5. If protective state continuity is uncertain, block new risk-increasing actions until safe initialization or manual resolution.
6. Preserve safe risk-reducing position management wherever possible.

Do not introduce a persistent account identity registry or unnecessary account-identification infrastructure.

### 1.3 StateStore simplification
Persist only the minimum internal protective state genuinely required by the EA. Separate current account metrics from persistent protective state. Do not let StateStore calculate or invent historical financial values. Avoid unnecessary abstractions and speculative features.

### 1.4 Development priority and scope control
Proceed with the existing modular roadmap. Complete **Phase 2.1** first, then move to **Phase 2.2**. Do not expand Phase 2.1 into unrelated modules. Do not wait for every unresolved Phase 1.3 decision; resolve only decisions necessary for the current module and document the rest for their relevant future phases.

**Context:** Phase 1/1.1/1.2/1.3 audit/design artifacts exist; contract is not frozen and `U-01..U-17`, `UR-01..UR-14` are not broadly approved. Phase 2.1 is limited to StateStore foundation hardening consistent with the decisions above and does not implement drawdown/HWM/trade-lifecycle/PropFirm/trading-day/cashflow/strategy/sizing logic.

## 2. Current Architecture and Relevant Source Files (Evidence)

| Area | File(s) | Evidence / Role |
|---|---|---|
| State persistence (primary target) | `Include/State/StateStore.mqh` | `CStateStore` (:26, :103): per-login `FILE_COMMON` files `MoneyManager\state_<login>.{json,lock,bak,tmp}` (`Init` :105-117). Persists `"version"` as `MM_CONTRACT_VERSION` (:191-192), `login` (:193), `accountMode`, `activeProfileId/template`, counters/keys/timestamps/timeFallback, day-start/peak baselines, `MM_UIState`, 64 symbol states. Public API used by callers: `Init`, `Save`, `AccountMode/SetAccountMode`, `UI/SetUI`, `GetSymbolState/SetSymbolState`, `IncTrade`, `TradesDay`, `TimeFallbackActive`, `IsOperational`, `StatePath`, `DayStartBalance/DayStartEquity`, `PeakEquity/PeakBalance`, `SyncPeaks` (and public lock/backup methods). |
| Public/shared contracts | `Include/Core/Contracts.mqh` | `MM_CONTRACT_VERSION 1` (:8), frozen/shared structs/enums/interfaces. **Must remain unchanged** for Phase 2.1. |
| JSON (de)serialization | `Include/Core/SimpleJson.mqh` | Minimal flat/tagged-key `CJsonBuilder`/`CJsonReader` (:11-131); no general object/array parsing. |
| Execution safety gate | `Include/Core/ExecutionRouter.mqh` | `Init(CStateStore*, IRejectSink*, ...)` (:54-58), preflight rejects `STATE_NOT_OPERATIONAL` when store present and not operational (:84-86). |
| EA orchestration / caller | `MoneyManager.mq5` | Global `CStateStore g_store` (:81). `OnInit` calls `g_store.Init()` at :237 but warns/logs on failure and continues to `INIT_SUCCEEDED` (:284); router wired with store at :242. Uses `SyncPeaks/Save/DayStartBalance/DayStartEquity` (:118-120, :222, :249, :294-295, :307-308, :381). No EA-level block on unsafe/non-operational store. |
| Existing tests | `Tests/Phase1/StateStore_Test.mq5` | Scripted init/save/reload (mode/UI/symbol), legacy `version:0` migration preserving `accountMode`, restores original bytes. `Tests/Phase1/README.md` documents manual future-version fail-safe/lock/stale-lock expectations. |
| Existing state docs | `Docs/contracts.md` | Current contract: per-login files/lock, backup+tmp+move, future-version fail-safe, migration/version bump rules. Policy now requires no persisted login/server/identity registry; align docs in implementation phase only where genuinely changed. |
| Baseline/status/debt | `Docs/DEVELOPMENT_BASELINE.md`, `Docs/MODULE_STATUS.md` (StateStore Partially Complete), `Docs/TECHNICAL_DEBT.md` (TD-04/05/17), `Docs/phase1-test-results.md` | Persistence/safety gaps and fail-safe surfacing context. |

**Caller/dependency map (verified):** runtime `CStateStore`/`StateStore` references exist only in `Include/State/StateStore.mqh`, `Include/Core/ExecutionRouter.mqh`, `MoneyManager.mq5`, and `Tests/Phase1/StateStore_Test.mq5`. `CGuardEngine` has no StateStore dependency.

## 3. Existing StateStore Behavior and Limitations (Evidence)

| Topic | Current behavior (evidence) | Limitation / risk vs final decisions |
|---|---|---|
| Schema/versioning | `"version"` coupled to `MM_CONTRACT_VERSION` (:191-192, :261-274). | Persistence schema not separated from public contract; migration coarse (no preserved original/loss tracking). |
| Forbidden/persistent identity data | Files keyed by login `state_<login>` (:105-117); payload stores `login/accountMode/activeProfileId` (:193-195, :275-277). No server, but login is persisted and used as storage key. | Conflicts with policy: must not persist Account Login/Broker Server/credentials/personal identity/prop identifiers and must not introduce a persistent account identity registry. |
| Load / missing/corrupt content | Missing file initializes from current account and saves (:247-256). Load parses with defaults, applies rollover/day-start resets to current on key change (:293-299), `EnsureBaselines()` bumps peaks to current (:91-100, :300), sets operational true (:301). No `.bak` restore, no integrity/structure validation, no parse-error detection. | Can seed/drift or silently apply prior/unsafe protective state; no deterministic recovery precedence or explicit continuity/manual-review signaling. |
| Save pipeline | Blocked if `!m_operational` (:178). Lock, best-effort `Backup` (:180-181), writes `.tmp`, deletes dst, moves tmp->dst, fallback direct write after backup attempt (:221-238), returns `ok` (:239-240). | No temp validation before promotion; dst deleted before confirmed durable promotion; fallback may overwrite without proof; pre-existing artifacts not explicitly handled; no explicit stage/status model; durability not guaranteed beyond MQL5 APIs. |
| Backup | Single `.bak` overwritten from current primary (:159-174). | Last-known-good can be replaced by bad/partial content. |
| Operational state / integration | `m_operational` false only for future version or missing-file save failure (:254-255, :268-273). Router gates preflight (:84-86). EA warns and continues on init failure (:237, :284). | Does not reflect corruption, migration ambiguity, save failure, or account-switch/continuity uncertainty; new risk-increasing actions may be possible outside safe state. |
| Symbol state load | `GetSymbolState` lazily re-reads file for unknown symbols (:315-321). | Bypasses in-memory validation/recovery context. |
| Responsibilities / baselines | Store mutates day-start/peak baselines and performs rollover (`EnsureBaselines/Save/Load/SyncPeaks`, :91-100, :184-189, :296-300, :338-340); EA also local-day resets (`MoneyManager.mq5:303-311`). | Mixes persistence with account/time-dependent behavior and can invent/rebase values; Phase 2.1 must not redesign DD/trading-day logic but must prevent unsafe persistence/operational authorization and preserve separation of current metrics from persistent protective state. |
| Legacy migration | `version<=0` treated as v1 and bumped in memory (:261-267); no original preserved, no field-level loss/continuity record. | Coarse/unsafe for legacy login-keyed or forbidden-field payloads. |

## 4. Proposed Changes by File and Module

> Implementation only after explicit approval. Scoped to Phase 2.1 foundation hardening.

| File | Planned changes | Notes / compatibility |
|---|---|---|
| `Include/State/StateStore.mqh` (**primary**) | **Schema/version:** add dedicated persistence schema version independent of `MM_CONTRACT_VERSION`; keep `MM_CONTRACT_VERSION` unchanged. **No forbidden persisted data / no identity registry:** stop persisting Account Login, Broker Server, credentials/passwords, personal identity, prop account identifiers; remove login-keyed persistent identity/registry behavior in favor of a simple non-identifying storage approach (details minimized in implementation) that never guesses or silently applies cross-account state. **Simplify persisted content:** persist only minimum internal protective state genuinely required and minimal non-forbidden config/state already required (e.g. UI, symbol/template/profile-selection as applicable), separated from current MT5 account metrics; do not calculate or invent historical financial values. **Reliable save:** lock -> protect last-known-good -> serialize minimal payload to temp -> validate temp (read/parse + schema/structure checks) -> promote only after validation -> deterministic cleanup; explicit stage/status results; never report success before validation+promotion; never delete only known-good before validated replacement is secure. **Deterministic recovery/integrity:** evaluate candidates in deterministic order, recover from validated backup/last-known-good when primary invalid, preserve evidence, distinguish normal/backup/degraded/manual-review outcomes, do not silently seed/apply unsafe or prior-account state. **Account-switch/continuity safety:** on init/load/reinit treat continuity conservatively (no persisted identity); never reuse previous live financial values or silently apply previous protective baselines/drawdown/trading history to a new/uncertain context; if continuity uncertain, require safe initialization or manual resolution and block new risk-increasing actions (explicit status). **Legacy migration:** recognize legacy v0/v1/login-keyed payloads as needed, preserve originals/evidence, migrate only safely interpretable minimal non-forbidden fields, drop forbidden identifiers, do not invent history; require safe reinit/manual review when applicability/continuity cannot be established safely. **Operational/status integration:** minimal status/result/recovery and continuity/safe-init flags; `IsOperational()` (and/or additive safe-to-trade-risk-increasing query) reflects integrity/recovery/migration safety and continuity/safe-init readiness. **API safety:** refactor `GetSymbolState` to use validated in-memory/committed state only. Keep existing public signatures/structs/call patterns backward compatible where possible; add only minimal additive members/methods. | Avoid abstractions/speculative features. Preserve existing DD/HWM/trade-day formulas/semantics except where strictly necessary for safe persistence/recovery/operational authorization and account-switch safety. Do not claim durability beyond MQL5 file APIs. |
| `Include/Core/SimpleJson.mqh` | **No change expected.** Minimal backward-compatible helper only if strictly necessary; prefer validation in StateStore using existing reader semantics. | Keep existing behavior stable. |
| `Include/Core/Contracts.mqh` | **No change planned.** `MM_CONTRACT_VERSION 1` and all existing definitions unchanged. | Persistence schema version is StateStore-owned. |
| `Include/Core/ExecutionRouter.mqh` | **Integration requirement:** preserve `STATE_NOT_OPERATIONAL` preflight/send gate (:84-86) for router-mediated risk-increasing paths. No formula/strategy/risk-threshold changes. | Additive-only if required to avoid bypass. |
| `MoneyManager.mq5` | **Integration requirement (minimal):** on init/reinit and when continuity is uncertain, refresh account data from MT5 and recalculate account-dependent metrics from current data; never reuse previous live/protective/drawdown/history values for a new/uncertain context. If store unsafe or continuity/safe-init not satisfied, block new risk-increasing actions until safe initialization or manual resolution (tighten warn-and-continue at :237/:284) while preserving safe risk-reducing position management wherever possible. | No unrelated refactors; do not weaken guards. |
| `Tests/Phase1/StateStore_Test.mq5` and/or new `Tests/Phase2_1/StateStore_Foundation_Test.mq5` | Add/adjust isolated repeatable tests for Phase 2.1 foundation cases (see §7). Prefer additive/new artifact; align with final policy (no persisted login/server/identity registry) while keeping still-valid behaviors compatible where practical. | Self-contained, cleanup artifacts, clear pass/fail. |
| `Docs/Implementation/PHASE_2_1_STATESTORE.md` (**implementation phase**) | Document architecture, schema/version policy, minimal persisted protective state vs current MT5 metrics, save/recovery/integrity flow, account-switch/continuity handling, operational semantics, legacy migration, limitations, tests/results, and deferred Phase 1.3 decisions not required for this module. | Required by spec. |
| `Docs/MODULE_STATUS.md`, `Docs/contracts.md`, `Docs/TECHNICAL_DEBT.md` | Update only if implementation status or documented behavior genuinely changes and remains consistent with final decisions; `MM_CONTRACT_VERSION` unchanged. | No speculative doc churn. |

## 5. New Interfaces and Status Definitions (Proposed, Minimal)

> Names indicative; keep simple, additive, and backward-compatible.

- **Constants/fields:** `MM_STATE_SCHEMA_VERSION` persisted independently of `MM_CONTRACT_VERSION`. Minimal state/status members: operational flag plus continuity/safe-init/manual-review/recovery indicators and last result/reason (simple fields or compact enum).
- **Persisted payload (minimum, non-forbidden):** schema/version and minimal integrity markers as needed; minimum internal protective state genuinely required; minimal required non-forbidden config/UI state (e.g. `MM_UIState`, symbol/template/profile-selection data as applicable). **Never persisted:** Account Login, Broker Server, credentials/passwords, personal identity, prop account identifiers, live current metrics as truth, or invented historical values. No persistent account identity registry.
- **Status/result model (simple):** outcomes for `OK`, lock/read/parse/schema-invalid, future-schema, temp-write/validate/promote/backup failure, recovery-from-backup, degraded/manual-review-required, continuity-uncertain/safe-init-required. Recovery source: primary-valid, backup/last-known-good, degraded, blocked/manual-review.
- **Operational semantics:** risk-increasing actions authorized only when state is integrity-valid, recovery/migration outcome is safe, and continuity is not uncertain (safe initialization complete). If unsafe/corrupt/unmigratable or continuity uncertain, block new risk-increasing actions until safe initialization or manual resolution. Safe risk-reducing position management remains possible wherever technically safe and independent of unsafe/uncertain persisted authorization.
- **Additive queries (only if needed):** e.g. `RequiresSafeInit()`, `RequiresManualReview()`, continuity/status reason helpers — keep minimal.

## 6. Save/Recovery Flow

### 6.1 Reliable Save Flow (deterministic, minimal)
1. **Precondition/status:** refuse/fail with explicit status when save is unsafe or recoverability cannot be preserved; do not report success.
2. **Acquire lock:** bounded retry/stale takeover (retain simple existing policy) with explicit lock-failure status.
3. **Protect last-known-good:** preserve/refresh validated backup or last-known-good before risky promotion; never overwrite with unvalidated content; never delete only known-good artifact.
4. **Write temp:** serialize minimal payload (dedicated schema version + required protective/config state, no forbidden identifiers, no invented history/live metrics) to `.tmp`.
5. **Validate temp:** close and verify temp readable/parseable and structurally/schema-valid before promotion.
6. **Promote:** promote validated temp to primary using safest simple sequence; remove/replace destination only when validated replacement and rollback/last-known-good safety are preserved.
7. **Cleanup and status:** deterministic safe cleanup of stale temp, set explicit success/failure and operational/safe-init impact. **No success before validation+promotion complete.**

**Durability note:** MQL5 file APIs do not provide documented power-loss/fsync guarantees; do not claim durability beyond available API behavior.

### 6.2 Deterministic Recovery and Integrity Flow (load/init/switch-safe)
1. **Refresh current context from MT5:** read current Balance/Equity/Margin/Free Margin/Margin Level/Floating PnL/open positions/available history context/symbol specs as needed for runtime metrics and safe initialization. Current metrics are runtime values, not persisted truth.
2. **Discover/load candidates deterministically:** evaluate canonical minimal artifacts (primary, validated backup/last-known-good, and explicitly supported legacy sources) without any persistent account identity registry.
3. **Validate:** for each candidate attempt read -> parse -> schema/version support -> required structural/integrity checks. Reject future/invalid/corrupt candidates with explicit status and preserved evidence.
4. **Recover/select:** primary-valid preferred; otherwise validated backup/last-known-good with explicit backup-recovered/degraded status; otherwise blocked/manual-review with no unsafe state applied.
5. **Continuity/account-switch rule:** never reuse previous account live financial values as new-account values; never silently apply previous protective baselines, drawdown state, or trading history to a new/uncertain context. Because forbidden identifiers are not persisted and no identity registry exists, continuity may be uncertain; require safe initialization or manual resolution and block new risk-increasing actions until resolved.
6. **Safe initialization:** recalculate account-dependent metrics and establish in-memory protective context from current MT5 data per safe rules; apply only minimal persisted state that is safe under continuity policy. Never invent historical financial values.
7. **Commit state:** set explicit operational/continuity/manual-review status and persist canonical migrated/safe form only when it does not destroy evidence or violate safety.

## 7. Legacy Migration Strategy

| Case | Handling |
|---|---|
| Legacy schema/content (`version` missing/`0`/v1-era, flat tagged payload) | Recognize as legacy; preserve original artifact/evidence before mutation. Migrate only safely interpretable minimal non-forbidden fields; do not invent history/values. |
| Legacy login-keyed files/payload (`state_<login>.*`, stored `login`/server-like fields) | Do not persist Account Login/Broker Server or create an identity registry. Do not guess ownership/applicability to current MT5 account. Use deterministic safe handling that avoids silent cross-account application; when applicability/continuity uncertain, preserve evidence and require safe initialization/manual resolution with new risk-increasing actions blocked. |
| Forbidden fields in legacy payload | Drop and never re-persist Account Login, Broker Server, passwords/credentials, personal identity, prop account identifiers. |
| Uninterpretable/ambiguous/missing essential data | Do not invent historical financial values or history. Mark continuity uncertain/not fully verified and/or require manual review/safe init; block risk-increasing actions until safe. |
| Future persistence schema version | Fail safe: no unsafe apply/overwrite, preserve artifacts, explicit non-operational/manual-review status. |
| Migration output | Write canonical minimal payload with dedicated persistence schema version and no forbidden identifiers only after safe validation/promotion and without destroying preserved originals/evidence. |

## 8. ExecutionRouter and EA Integration Requirements

| Requirement | Current state | Planned integration (implementation) |
|---|---|---|
| Block new risk-increasing actions when unsafe/not ready | Router preflight rejects `STATE_NOT_OPERATIONAL` (`ExecutionRouter.mqh:84-86`). | Preserve as mandatory gate for router-mediated execution/preflight; ensure status reflects integrity, recovery, migration, and continuity/safe-init readiness. |
| Safe init and account-switch handling | EA warns on init failure but continues (`MoneyManager.mq5:237,284`); no continuity handling. | On init/reinit/uncertain continuity, refresh MT5 data and recalculate account-dependent metrics from current data; never reuse/silently apply previous live/protective/drawdown/history values for new/uncertain context; block new risk-increasing actions until safe initialization or manual resolution. |
| Risk-reducing / existing-position management | Some position-management paths are outside router send flow. | Preserve safe risk-reducing position management wherever technically safe and possible even when new risk-increasing actions are blocked; do not weaken guards. Document path-specific limitations. |
| No weakening of guards | Guard engine runs after operational gate in preflight. | No changes to guard thresholds/formulas; persistence/continuity safety must not bypass guards. |

## 9. Test Cases and Validation Methods

### 9.1 Test approach
- **Type:** isolated, repeatable MQL5 script-based tests (consistent with `Tests/Phase1/*.mq5`), minimal complexity, clean up artifacts.
- **Location (proposed):** `Tests/Phase2_1/StateStore_Foundation_Test.mq5` (and brief notes if useful); adjust `Tests/Phase1/StateStore_Test.mq5` only as needed for compatibility with final policy/still-valid behaviors.
- **Execution:** MetaTrader 5/MetaEditor against demo/test terminal with access to `MQL5/Files/Common/MoneyManager`. **Not executed in this planning step; pass/fail must not be claimed without execution.**

### 9.2 Planned cases (minimum necessary for Phase 2.1)
| ID | Scenario | Expected result |
|---|---|---|
| T2.1-01 | Fresh init/save/load round-trip | Dedicated persistence schema version written (separate from `MM_CONTRACT_VERSION`), minimal required non-forbidden state persisted, no Account Login/Broker Server/credentials/personal/prop identifiers, load returns explicit valid status. |
| T2.1-02 | Save success path | Temp written/validated, promotion succeeds, explicit success only after validation+promotion, primary readable/valid. |
| T2.1-03 | Save failure / pre-existing temp-backup artifacts | Explicit failure/status on induced/testable failure paths, last-known-good preserved, deterministic handling of pre-existing `.tmp`/`.bak`, no false success. |
| T2.1-04 | Corrupt/partial primary with valid backup | Deterministic recovery from validated backup/last-known-good, evidence preserved, status distinguishes backup recovery from normal load. |
| T2.1-05 | Corrupt/invalid state with no valid backup | No silent unsafe apply/seed of prior protective state or current values as invented history; explicit degraded/manual-review/non-operational status blocking new risk-increasing actions until safe init/manual resolution. |
| T2.1-06 | Legacy v0/v1 and login-keyed/forbidden-field payloads | Original preserved, only safely interpretable minimal non-forbidden fields migrated, forbidden identifiers dropped/not persisted, no invented historical values, continuity handled safely (uncertain => safe-init/manual-review/blocking as defined). |
| T2.1-07 | Future schema version | Fail-safe: no unsafe apply/overwrite, artifacts preserved, explicit status. |
| T2.1-08 | Continuity uncertain / safe-init gating (incl. account-switch safety) | Status blocks new risk-increasing actions until safe initialization/manual resolution; no reuse/silent apply of previous live/protective/drawdown/history values; current metrics sourced from MT5 refresh/recalculation (validated by observable status/flow where scriptable). |
| T2.1-09 | `GetSymbolState` safety & regression | Reads use validated in-memory/committed state; still-valid UI/symbol/config behaviors preserved within simplified/minimal scope. |

### 9.3 Validation methods and evidence
- Script pass/fail counters and diagnostics; capture MT5 logs and produced state/backup/artifact files.
- **Static verification:** `MM_CONTRACT_VERSION` unchanged; no persisted login/server/credentials/personal/prop identifiers; no identity registry; no drawdown/HWM/trade-lifecycle/PropFirm/trading-day/cashflow/strategy/sizing logic changes; no unrelated modules modified.
- **Compile:** MetaEditor compile of modified artifacts in implementation phase if available (report actual results; no claims without execution).
- **Manual checks:** account-switch and relevant stale-lock/multi-chart scenarios; report if not runnable.

## 10. Risks, Dependencies, and Unresolved/Deferred Decisions

| Item | Type | Impact / handling |
|---|---|---|
| Continuity without forbidden identifiers/registry | Necessary constraint | Login/Server not persisted and no identity registry allowed, so continuity may be uncertain. Default to safe behavior: never silently apply prior protective baselines to uncertain context and block new risk-increasing actions until safe initialization/manual resolution. Any stronger continuity mechanism deferred unless trivial, safe, and policy-compliant. |
| Legacy login-keyed files / ownership ambiguity | Migration risk | Existing `state_<login>.*` artifacts may exist; migration must not guess ownership and must not re-persist forbidden fields. Preserve evidence and require safe init/manual review when applicability uncertain. |
| MQL5 file durability limits | Platform limitation | No guaranteed power-loss/fsync/atomicity beyond APIs; use temp-validate-promote and last-known-good preservation but claim no guarantees. |
| `SimpleJson` minimal parser/writer | Technical constraint | Validation/recovery must work within flat/tagged-key limitations; avoid breaking existing consumers. |
| Broad Phase 1.3 decisions (U-01..U-17, UR-01..UR-14) | Deferred except 2.1 necessities | Resolve only what is necessary now: separate persistence schema version, reliable save/recovery/integrity, minimal safe persisted protective state (policy-compliant), and operational/account-switch safety. Defer drawdown formulas/semantics, HWM durability model, trade-lifecycle accounting, trading-day authority/boundary policy, cashflow ledger, PropFirm governance/redesign, and other non-essential decisions to relevant future phases with documentation. |
| EA init/safety tightening | Integration risk | Blocking new risk-increasing actions on unsafe/uncertain continuity affects availability but is required for safety; preserve risk-reducing management and existing guards. |
| Existing mixed responsibilities in StateStore/EA | Scope boundary | Day-key rollover and baseline mutations exist today; Phase 2.1 must not redesign DD/trading-day logic but must ensure persistence/status cannot authorize unsafe actions or invent historical values. |

## 11. Implementation Order and Completion Criteria

### 11.1 Implementation order (after explicit approval)
1. **StateStore scaffolding (minimal):** add persistence schema version constant, simple status/result/recovery and continuity/safe-init fields, and minimal additive helpers without caller breakage.
2. **Persistence content simplification:** implement minimal persisted payload separated from current MT5 metrics; remove persistence of forbidden identifiers and any identity registry concepts.
3. **Deterministic recovery/integrity:** candidate validation, schema/structure checks, backup/last-known-good recovery, evidence preservation, and explicit degraded/manual-review outcomes.
4. **Legacy migration:** preserve originals, migrate only safely interpretable minimal non-forbidden fields, handle legacy login-keyed artifacts without guessing ownership, enforce continuity-uncertain/safe-init blocking where needed.
5. **Reliable save pipeline:** temp write -> validate -> promote with last-known-good protection, deterministic cleanup, and explicit stage/status results (no success before validation+promotion).
6. **Operational and account-switch safety integration:** ensure `IsOperational`/safe-init/continuity status blocks new risk-increasing actions; refactor `GetSymbolState` to validated in-memory state; preserve router gate.
7. **EA integration (minimal):** refresh MT5 data and recalculate account-dependent metrics on init/reinit/uncertain continuity, enforce no reuse/silent apply of prior live/protective/drawdown/history values, block new risk-increasing actions until safe init/manual resolution, preserve safe risk-reducing management.
8. **Tests and documentation:** add/adjust isolated Phase 2.1 tests, record honest execution results, and create `Docs/Implementation/PHASE_2_1_STATESTORE.md`; update other docs only if genuinely required and consistent with policy (`MM_CONTRACT_VERSION` unchanged).

### 11.2 Completion criteria (Phase 2.1)
- Persistence schema version is separate from `MM_CONTRACT_VERSION`, and `MM_CONTRACT_VERSION` remains unchanged.
- StateStore persists no Account Login, Broker Server, credentials/passwords, personal identity, or prop account identifiers and introduces no persistent account identity registry.
- Persisted data is limited to minimum internal protective state/config genuinely required, separated from current MT5 account metrics; StateStore does not calculate or invent historical financial values.
- Save uses validate-before-promote flow, preserves last-known-good, returns explicit stage/status outcomes, and never reports success before validation+promotion.
- Recovery/integrity is deterministic with explicit normal/backup/degraded/manual-review outcomes, evidence preservation, and no silent unsafe apply/seeding of prior state.
- Legacy v0/v1 migration preserves originals, migrates only safely interpretable minimal non-forbidden fields, drops forbidden identifiers, and does not invent historical/protective/lifecycle data.
- Account-switch/continuity handling refreshes MT5 data, recalculates account-dependent metrics, never reuses or silently applies previous live/protective/drawdown/history values to a new/uncertain context, and blocks new risk-increasing actions until safe initialization or manual resolution while preserving safe risk-reducing position management where possible.
- `IsOperational`/safety status integration prevents new risk-increasing actions when store is unsafe or continuity/safe-init is not satisfied (router and minimal EA/init integration), without weakening existing guards.
- Isolated tests for the above are added and execution status/results are reported honestly.
- `Docs/Implementation/PHASE_2_1_STATESTORE.md` documents behavior, limitations, and deferred Phase 1.3 decisions not required for this module.
- No out-of-scope changes: no drawdown/HWM formula implementation, no trade-lifecycle accounting redesign, no PropFirm engine redesign, no daily trading-time service implementation, no cashflow accounting, no new strategies, no Martingale/position-sizing changes, no commits/pushes, no Phase 2.2 work.
