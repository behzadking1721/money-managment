# Phase 2.1 — StateStore Foundation (Corrected)

**Status:** Implemented and corrected in workspace (not committed).  
**Scope:** StateStore persistence foundation only (schema versioning, minimal protective/config persistence, reliable staged save/validation, last-known-good preservation, deterministic recovery/integrity, safe legacy migration, explicit continuity resolution, operational-state safety integration, minimal EA/UI integration, isolated tests).  
**Out of scope (not changed):** drawdown/HWM formulas, trade lifecycle accounting redesign, PropFirm engine redesign, daily trading-day service implementation, cashflow accounting, strategies, Martingale/position sizing. `MM_CONTRACT_VERSION` remains `1`. `Include/Core/Contracts.mqh`, `Include/Core/SimpleJson.mqh`, and `Include/Core/ExecutionRouter.mqh` are unchanged.

## 1. Privacy and Account Data Policy

- **Never persisted / no registry:** Account Login, Broker Server, passwords/credentials, personal identity, and Prop Firm identifiers are not written to StateStore artifacts. No persistent account identity registry is introduced.
- **MT5 account data:** Balance, Equity, Margin/Free Margin/Margin Level, Floating PnL, open positions, available trading history, and symbol specs/restrictions may be read in memory for operational/runtime calculations and explicit user-confirmed initialization only. Live metrics are not treated as persisted truth by StateStore.
- **No external transmission:** implementation adds no network/external transmission of account information.
- **Runtime-only detection:** runtime account-switch detection uses `AccountInfoInteger(ACCOUNT_LOGIN)` in memory only (never persisted, never logged as an identifier value) for best-effort in-session detection and `REASON_ACCOUNT` deinit handling where provided. Logger base name remains non-identifying (`mm`).
- **Pre-existing out-of-scope concern:** `Include/Profiles/Profiles.mqh` still uses login-keyed storage paths/names (`profiles_<login>.json`, login-based `Init`) and was not modified in Phase 2.1; document for follow-up.

## 2. Architecture and Safety Model

### 2.1 StateStore (`Include/State/StateStore.mqh`)
- **Schema:** `MM_STATE_SCHEMA_VERSION` (2) persisted as `schemaVersion`, independent of `MM_CONTRACT_VERSION`.
- **Minimal persisted payload:** schema version, account mode, active profile/template ids, trade counters/period keys/time metadata, day-start/peak baseline fields as persisted protective state, UI state, and symbol sizing/template config. No forbidden identifiers. No invented historical financial values.
- **Separation of concerns:** StateStore stores/returns in-memory state and does not read MT5 or compute/invent financial values. `SyncPeaks()` is a compatibility no-op. `GetSymbolState` reads validated in-memory state only.
- **Continuity-conservative model (corrected, F-01/F-02):** continuity cannot be proven without forbidden persistent identity/registry. A valid persisted/legacy/backup-restored protective state may be loaded into memory for preservation, but **it is never auto-applied as operational continuity and never auto-rebased/reset**. Store remains blocked for risk-increasing actions until explicit user resolution.
  - On restart/fresh ambiguity: restored protective state is preserved and `RequiresExplicitResolution()`/manual review is set; `IsOperational()` is false.
  - On runtime account switch detection: store is explicitly blocked pending resolution (`BlockPendingExplicitResolution`) while preserving prior persisted protective evidence/state; no silent discard/rebase.
- **Explicit resolution paths (corrected):**
  - `RestoreExistingState(continuityExplicitlyEstablished, explicitUserConfirmed)`: restores/persists existing in-memory protective state as operational **only** when continuity is explicitly established and explicitly confirmed. Not auto-called. Denied when continuity is uncertain/unproven.
  - `InitializeNewProtectiveStateFromCurrent(..., explicitUserConfirmed)` / `BeginSafeInitFromCurrentConfirmed(...)`: initializes **new** protective state from explicitly provided current MT5/runtime values **only with explicit user confirmation**. Preserves previous persisted evidence (`.pre_init.*`) before replacement, resets protective counters/period keys, preserves minimal non-protective config in memory where available, and becomes operational only after validated persistence succeeds.
  - `BeginSafeInitFromCurrent(...)` (compatibility): rejects implicit/auto calls to prevent auto-rebase (returns false).
- **Staged save/validation/promotion (corrected, F-03/F-04/F-05):** lock -> serialize canonical payload -> structural+semantic validation -> write temp -> read-back temp parse/schema/semantic validation -> backup handling -> promote -> post-promotion read/validate verification -> explicit status. No success before validated promotion+verification.
  - **Validation:** rejects implausible payloads, unsupported/future schema, missing/invalid required fields (e.g. `schemaVersion`, `accountMode`), invalid bounds/ranges/non-finite/non-negative numeric protective fields, and forbidden identity fields in current-schema artifacts.
  - **Backup safety:** primary->backup rotation occurs only when current primary is fully valid current-schema and trusted/known-good in runtime. Invalid/corrupt primary is preserved as evidence and does **not** replace backup. Parseable-but-invalid/untrusted candidates do not demote last known-good backup.
  - **Failure semantics:** temp/write/promote/verify failures preserve evidence where applicable, do not report operational success, and leave store blocked/requiring explicit resolution/review.

### 2.2 EA/UI integration (`MoneyManager.mq5`, `Include/UI/PanelShell.mqh`, `Include/UI/UiStrings.mqh`)
- **No auto safe-init:** `OnInit`/runtime never auto-reset/rebase existing protective state. If store is not operational, EA logs/warns, keeps risk-increasing actions blocked, and exposes explicit resolution via UI.
- **Explicit user confirmation flow:** "Resolve" UI action calls `HandleStoreResolveRequest()` -> `RequestExplicitNewProtectiveInit()` which shows `MessageBox` confirmation with explicit reset/continuity warning. Only on explicit confirmation are runtime baselines re-established from current MT5 values and `InitializeNewProtectiveStateFromCurrent(..., true)` called.
- **Runtime account switch:** best-effort in-session marker comparison and `REASON_ACCOUNT` handling refresh current runtime metrics/views and call `BlockPendingExplicitResolution(...)`; previous persisted protective evidence/state is preserved and risk-increasing actions remain blocked until explicit resolution. No persistent identity is used.
- **Risk-reducing management preserved:** BE/trail/time-exit and existing-position management continue to run on tick even when store is blocked. New risk-increasing actions are gated by router preflight (`STATE_NOT_OPERATIONAL`) and UI/send guards.
- **Persistence policy:** `g_store.Save()` on deinit/day-reset only when store is operational (`StoreReadyForRiskIncreasing()` / `IsOperational()`).

### 2.3 Execution safety (F-07)
- **Order-opening/exposure-increasing path:** `UI -> CExecutionRouter::Send -> Preflight -> Risk/Stops/Guards` and `Preflight` rejects with `STATE_NOT_OPERATIONAL` when store is not operational. UI `TrySend` also blocks when store is blocked.
- **Direct trade primitives:** `COrderManager`/`CExecutionPolicy` contain `CTrade` execution helpers but are not on the user-facing send path; EA does not instantiate `COrderManager` for order entry. `CPositionManager`/`CPositionDragTool` are used for position modification/close/BE/trail/partial-close (risk-reducing or position-management actions) and remain available when store is blocked.
- **Conclusion:** no user-facing order-opening/exposure-increasing path was found bypassing router/store operational gating in modified/inspected paths; risk-reducing management remains available.

## 3. Account-Switch and Restart Behavior

- **Runtime account switch (detected in-session):** refresh current MT5 metrics/views, do not reuse previous live/protective/drawdown/trading history for the new context, preserve previous persisted protective evidence/state, block new risk-increasing actions until explicit user resolution. Safe risk-reducing position management remains available.
- **After terminal/EA restart:** continuity cannot be proven without persistent identity (forbidden). Restored persisted protective state is preserved but not auto-applied/auto-rebased; store blocks new risk-increasing actions until explicit resolution. Explicit restore is not assumed possible without explicitly established continuity; explicit new protective initialization from current MT5 values is available with user confirmation and evidence preservation.
- **Limitation (documented):** account switching/identity continuity cannot always be identified after restart without persistent identity. Behavior is intentionally conservative and may require explicit reinitialization/manual resolution.

## 4. Tests Added/Updated (Isolated)

| Artifact | Purpose | Status |
|---|---|---|
| `Tests/Phase2_1/StateStore_Foundation_Test.mq5` | Updated/extended isolated cases: fresh init blocked + implicit init rejected (F-01), restart continuity-uncertain preserves restored protective baselines/counters/UI/config and blocks (F-01/F-02), explicit confirmed init replaces baselines/counters only after confirmation, corrupt primary + valid backup recovery remains blocked pending explicit resolution and uses backup data, corrupt primary+backup blocked/manual review, legacy migration drops login and requires explicit resolution, future schema fail-safe, stale tmp/invalid backup do not break validated save, semantically invalid primary rejected in favor of valid backup, runtime switch-like block preserves restored state, `GetSymbolState` in-memory default. | **Not executed (MetaTrader 5 / MetaEditor unavailable).** |
| `Tests/Phase1/StateStore_Test.mq5` | Updated for corrected semantics: fresh/reload/legacy require explicit resolution (not auto safe-init), implicit init rejected, explicit confirmed init required, restored state/config preserved on continuity-uncertain reload, privacy checks, corrupt artifacts blocked. | **Not executed (MetaTrader 5 / MetaEditor unavailable).** |
| Other existing tests | Unchanged and not executed. | **Not run.** |

## 5. Compile/Execution Checks

- **MetaEditor/MT5 compile:** **not run** (MetaEditor/terminal compiler not found in this environment). No compile pass/fail can be claimed.
- **Scripted test execution:** **not run** (MT5 runtime unavailable). Exact results unavailable.
- **Static checks performed:** reviewed modified sources for F-01..F-07 corrections, confirmed `MM_CONTRACT_VERSION` remains `1`, confirmed StateStore uses `MM_STATE_SCHEMA_VERSION` independently, confirmed no account login/broker/server/credential fields added to persisted payload/logs, confirmed router `STATE_NOT_OPERATIONAL` gate unchanged, confirmed risk-reducing position management paths remain outside router send gate, `git diff` reviewed for scope.

## 6. Known Limitations and Unresolved Issues

- **Restart continuity:** cannot be proven without persistent identity (forbidden). Restored protective state is preserved but not auto-applied; explicit resolution is required. `RestoreExistingState` requires explicitly established continuity and is therefore not safely satisfiable in the restart-ambiguous case with current policy/inputs.
- **Runtime switch detection:** best-effort in-session marker/`REASON_ACCOUNT` only; cannot identify all restart-time account changes without forbidden persistent identity.
- **Profiles module:** `Include/Profiles/Profiles.mqh` remains login-keyed and out of scope (pre-existing privacy concern).
- **Durability/parser:** MQL5 file APIs lack documented fsync guarantees; minimal flat/tagged-key JSON parsing/validation is structural and best-effort within parser limitations.
- **Validation confidence:** compile/runtime validation not possible in this environment; tests are source-level only until run in MT5.

## 7. Files Changed (Phase 2.1 correction pass)

- **Modified:** `Include/State/StateStore.mqh`, `MoneyManager.mq5`, `Include/UI/PanelShell.mqh`, `Include/UI/UiStrings.mqh`, `Tests/Phase1/StateStore_Test.mq5`, `Tests/Phase2_1/StateStore_Foundation_Test.mq5`, `Docs/Implementation/PHASE_2_1_STATESTORE.md`
- **Unchanged by this correction:** `Include/Core/Contracts.mqh`, `Include/Core/SimpleJson.mqh`, `Include/Core/ExecutionRouter.mqh`, unrelated modules
- **Untracked/existing (not modified by correction logic except docs present):** `Docs/Implementation/PHASE_2_1_IMPLEMENTATION_PLAN.md`, `Docs/Implementation/PHASE_2_1_CRITICAL_AUDIT.md`, `Docs/Design/*`, `Docs/SKILLS_CATALOG.md`
