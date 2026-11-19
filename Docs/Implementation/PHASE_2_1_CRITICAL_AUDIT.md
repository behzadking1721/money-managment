# Phase 2.1 Critical Audit (Read-Only)

**Scope:** focused audit of completed Phase 2.1 implementation (StateStore foundation, persistence/recovery, EA safe-init/account-switch integration, execution safety).  
**Mode:** read-only (no source/test modifications, no commits/pushes).  
**Audited files (primary):** `Include/State/StateStore.mqh`, `MoneyManager.mq5`, `Include/Protection/Protection.mqh`, `Include/Core/ExecutionRouter.mqh`, `Include/Core/ExecutionPolicy.mqh`, `Include/Core/OrderManager.mqh`, `Include/Core/PositionManager.mqh`, `Include/UI/PanelShell.mqh`, `Include/Core/Contracts.mqh`.

## 1. Safe Initialization Audit (Highest Priority)

### 1.1 Key source references

| Component | Reference |
|---|---|
| Store safe-init API | `Include/State/StateStore.mqh:432-474` `BeginSafeInitFromCurrent(...)` |
| Store operational/readiness gates | `Include/State/StateStore.mqh:423-426` `IsOperational/RequiresSafeInit/RequiresManualReview/IsContinuityCertain` |
| Store init/load/commit/status | `Include/State/StateStore.mqh:410-421` `Init`, `584-644` `LoadInternal`, `371-387` `CommitValidatedContent`, `389-395` `FailBlocked`, `119-124` `SetStatus`, `126-138` `ResetToSafeDefaultsMemoryOnly` |
| Store save paths | `Include/State/StateStore.mqh:476-477` `Save`, `479-582` `SaveInternal` |
| EA safe-init orchestration | `MoneyManager.mq5:236-239` `StoreReadyForRiskIncreasing`, `241-273` `EnsureSafeStoreInitFromCurrent`, `301-368` `OnInit` |
| EA runtime switch handling | `MoneyManager.mq5:233-234` marker/global, `275-299` `HandleRuntimeAccountSwitchIfDetected`, `383-424` `OnTick`, `426-432` `OnTimer` |
| Protection init/baselines/counters | `Include/Protection/Protection.mqh:6-35` fields+`Init`, `37-46` `NewDay`, `47-51` `SyncPeaks`, `52-57` `RecordTrade`, `61-67` accessors, `69-105` DD calcs, `129-139` trade/cooldown checks |

### 1.2 Question-by-question answers

**Q1. Which protective values are reset during safe initialization?**

- **StateStore (`BeginSafeInitFromCurrent`, `StateStore.mqh:437-474`):** sets `m_mode` and conditionally `m_activeProfileId` (`:441-442`); resets protective counters/period keys/time metadata to neutral: `m_tradesDay/Week/Month=0`, `m_dayKey/weekKey/monthKey=0`, `m_lastResetServer=0`, `m_timeFallback=false` (`:444-446`); replaces persisted baseline/peak fields with caller-provided values: `m_dayStartBalance/Equity`, `m_peakEquity/Balance` (`:448-451`); resets continuity/safety flags and marks operational before save attempt (`:454-460`); persists canonical state (`:462`). It **does not** explicitly reset `m_symbolCount/m_symbols`, `m_ui`, or `m_activeTemplateId` (contrast `ResetToSafeDefaultsMemoryOnly` `:126-138` which does reset UI/symbol count). It does **not** persist or restore loss streaks/cooldowns/lockout fields because StateStore currently has no such fields.
- **EA orchestration (`EnsureSafeStoreInitFromCurrent`, `MoneyManager.mq5:241-273`):** calls `g_prot.Init()` (`:245`, `Protection.mqh:26-35`) which resets runtime protection state to current MT5 values: `m_startBalance`, `m_dayStartBalance/Equity`, `m_peakEquity/Balance`, `m_dailyProfit/Loss=0`, `m_dayStart=TimeCurrent()`, `m_tradesToday=0`, `m_consecutiveLosses/Wins=0`, `m_cooldownUntil=0`, `m_hasRules=false`. Passes `g_prot.DayStartBalance/Equity` and runtime peaks (derived after init from current MT5) into store safe init (`:246-253`). Reinitializes prop baseline/context (`:255-260`) via `g_prop.Init()` and optional enable/sync.
- **Net effect (current runtime protection context):** runtime day-start/start/peak baselines, daily profit/loss, trades-today counter, consecutive loss/win streaks, and cooldown are reset/rebased to current-account "fresh" values by `CProtection::Init`; store protective baseline/peak fields and counters/period keys are reset/replaced as above.

**Q2. Can safe initialization erase or weaken an existing daily or total drawdown restriction?**

**Yes (CRITICAL).** 
- Daily DD in protection is measured from `m_dayStartBalance/Equity` and accumulated `m_dailyLoss` (`Protection.mqh:69-73,87-93,107-114,170-171` in `MoneyManager.mq5`); total/max DD from peak/start references (`Protection.mqh:79-85,94-105,120-128,172,131,184`). 
- `EnsureSafeStoreInitFromCurrent` calls `g_prot.Init()` (`MoneyManager.mq5:245`) resetting day-start/peak/start to current balance/equity and `m_dailyLoss=0` (`Protection.mqh:28-34`), and seeds store baselines/peaks from those current values (`MoneyManager.mq5:246-253`, `StateStore.mqh:448-451`). 
- If the account is already in drawdown (equity below prior peak/day-start), rebasing peak/day-start to current values makes `CurrentDrawdownPct`, daily loss, remaining DD, and guard/risk budgets appear healthier or zero even though a prior restriction should still apply. This can weaken existing daily/total drawdown restrictions and permit risk-increasing actions once safe init completes.

**Q3. Can it reset peak equity, day-start equity, loss streaks, cooldowns, or lockout state?**

- **Peak equity / peak balance:** **Yes.** Runtime: `g_prot.Init()` sets `m_peakEquity` to current equity and `m_peakBalance` to current balance (`Protection.mqh:31-32`); passed to store (`MoneyManager.mq5:248-253`, `StateStore.mqh:450-451`).
- **Day-start equity / day-start balance:** **Yes.** Runtime: set to current in `g_prot.Init()` (`Protection.mqh:29-30`); store set from caller (`StateStore.mqh:448-449`).
- **Loss streaks (consecutive losses/wins):** **Yes (runtime).** `g_prot.Init()` resets `m_consecutiveLosses=0`, `m_consecutiveWins=0` (`Protection.mqh:34`); guards consume `g_prot.ConsecutiveLosses()` and cooldown checks (`MoneyManager.mq5:174-175`, `Protection.mqh:130-139`). Store does not persist streaks.
- **Cooldowns:** **Yes (runtime).** `g_prot.Init()` sets `m_cooldownUntil=0` and `CheckCooldown/CheckConsecutiveLoss` depend on it (`Protection.mqh:20,34,130-139`; `MoneyManager.mq5:175`).
- **Lockout state:** **Partially/indirectly.** `CProtection` has no explicit lockout flag, but daily/max DD, trade-count, streak/cooldown and guard decisions (`MoneyManager.mq5:153-176,211`) effectively gate trading. Resetting/rebasing these can remove an effective lockout. Prop/session/news/permission guard states are reinitialized/refreshed separately; store has no persisted lockout state.

**Q4. Does it happen automatically after restart?**

**Yes.** On restart `OnInit` loads store (`MoneyManager.mq5:307`), then if `RequiresSafeInit() || RequiresManualReview() || !StoreReadyForRiskIncreasing()` it automatically calls `EnsureSafeStoreInitFromCurrent(...)` (`:351-355`). `LoadInternal`/`CommitValidatedContent` mark any discovered persisted state (primary/backup, including legacy) as continuity-uncertain and not operational (`StateStore.mqh:382-385,601-604,620-622`), and fresh/no-state also requires safe init (`:632-641`), so the automatic branch is taken in these cases. `EnsureSafeStoreInitFromCurrent` attempts to establish operational state via `BeginSafeInitFromCurrent`+save (`MoneyManager.mq5:253`, `StateStore.mqh:454-474`).

**Q5. Does it happen automatically after account switching?**

**Yes, for runtime-detected switches.** `HandleRuntimeAccountSwitchIfDetected` runs from `OnTick` and `OnTimer` (`MoneyManager.mq5:386,428`), compares in-memory marker, and on change calls `EnsureSafeStoreInitFromCurrent("account_switch")` (`:275-299`, especially `:296`). This is automatic (no user confirmation). **Not guaranteed after terminal/EA restart** because continuity cannot be proven without persistent identity (see Q7, §2).

**Q6. Can risk-increasing actions resume without explicit user confirmation?**

**Yes.** 
- `BeginSafeInitFromCurrent` sets `m_operational=true`, clears `m_safeInitRequired/m_manualReviewRequired`, and returns true only if validated save succeeds (`StateStore.mqh:454-473`); on save failure it re-blocks (`:463-470`).
- `EnsureSafeStoreInitFromCurrent` does not prompt for confirmation; it logs/UI-warns on failure and only reports readiness on success (`MoneyManager.mq5:262-272`).
- Execution path for new/risk-increasing orders is gated by router preflight `m_store.IsOperational()` (`ExecutionRouter.mqh:84-85`, `110-125`) and UI/drag send flows go through router preflight/send (`PanelShell.mqh:314-343`, `448` passes router). Once store becomes operational automatically, router/store gate no longer blocks on this basis (other guards/risk checks still apply).

**Q7. What happens if a previous valid state exists but account continuity cannot be proven?**

- **Store load:** if primary or backup is a valid/legacy candidate, `LoadInternal` commits it via `CommitValidatedContent(..., continuity certain = never here)` which sets status `MM_STORE_ERR_CONTINUITY_UNCERTAIN`, `operational=false`, `safeInitRequired=true` (`StateStore.mqh:371-387,595-623`). It preserves legacy evidence (`:600,619`) but does **not** auto-persist a canonical continuity-blocked copy (`:604` comment/return path). 
- **EA behavior:** `OnInit` sees `RequiresSafeInit`/not ready and **automatically** performs `EnsureSafeStoreInitFromCurrent("continuity_check")` (`MoneyManager.mq5:351-355`), which rebases protection/store to current MT5 baselines and, if save succeeds, makes store operational (`MoneyManager.mq5:245-273`, `StateStore.mqh:437-474`). 
- **Result:** prior valid protective baselines/counters loaded in memory are discarded by safe init overwrite (`StateStore.mqh:444-451`) and not carried forward as protective restrictions for the (potentially different) account context; the system may become ready for risk-increasing actions without explicit user confirmation. This is conservative on *not trusting continuity* but **unsafe on protection preservation** because it can weaken/reset restrictions rather than requiring manual resolution while keeping blocking in force.

## 2. Account-Switch Detection Audit

### 2.1 Inspected uses of `ACCOUNT_LOGIN`, `OnInit`, `OnTick`, `OnTimer`, and account-change handling

| Symbol/handler | References | Purpose/notes |
|---|---|---|
| `ACCOUNT_LOGIN` | `MoneyManager.mq5:278` `long marker = AccountInfoInteger(ACCOUNT_LOGIN);` (inside `HandleRuntimeAccountSwitchIfDetected`), `MoneyManager.mq5:349` `g_rtAccountMarker = AccountInfoInteger(ACCOUNT_LOGIN);` (inside `OnInit`) | Read account login number into runtime-only marker for comparison. **Not written to StateStore, not logged, not transmitted.** |
| `OnInit` | `MoneyManager.mq5:301-368` | Initializes modules, loads store, sets runtime marker, performs automatic safe-init when not ready. |
| `OnTick` | `MoneyManager.mq5:383-424` | Calls `HandleRuntimeAccountSwitchIfDetected()` (`:386`), performs trading-day/protection updates, keeps risk-reducing position management active (`:400-416`), refreshes risk/guards/UI. |
| `OnTimer` | `MoneyManager.mq5:426-432` | Calls `HandleRuntimeAccountSwitchIfDetected()` (`:428`), refreshes alerts/risk/guards. Timer set in `OnInit` (`:364`). |
| `OnDeinit` | `MoneyManager.mq5:370-381` | Conditional save only if `StoreReadyForRiskIncreasing()` (`:378`). |
| `OnTradeTransaction` | `MoneyManager.mq5:451-470` | Forwards to lifecycle; updates runtime protection/profit counters on closed deals. No store persistence of forbidden identity. |
| `OnChartEvent` | `MoneyManager.mq5:434-449` | UI hotkeys/actions routed to panel/drag/router; no account identity handling. |
| MQL5 account-change events | **None implemented/found.** Search for `OnAccount`, `ACCOUNT_CHANGE`, and account-event handlers in `MoneyManager.mq5` and `Include/**` returned no EA account-change event handler. | Current design uses polling-based detection in tick/timer handlers. |

**Other repository uses (context, outside current EA safe-init integration):** `Include/Profiles/Profiles.mqh:139` historically references login-based paths; Phase 2.1-modified StateStore/EA/tests do not persist account login.

### 2.2 Assessment

- **Unnecessary read of `ACCOUNT_LOGIN` in current implementation:** the runtime detection **does read** `ACCOUNT_LOGIN` in memory (`MoneyManager.mq5:278,349`) to detect account changes. This is used only for comparison (marker stored in `g_rtAccountMarker`, `:234,282,288,349`) and is not persisted/logged/transmitted. Given the privacy policy forbids persisting/introducing identifiers into persistent files/registries (satisfied) and runtime switch detection is required, the read is functionally motivated; it is still a direct account identifier read and is avoidable only if a reliable non-identifier change signal exists.
- **Reliable MT5 event-based approach without polling an account identifier:** **no direct MQL5 EA event for account change was found/used** (no `OnAccountChange`/equivalent; implemented EA handlers are `OnInit/OnDeinit/OnTick/OnTimer/OnTradeTransaction/OnChartEvent` as above). A purely event-driven, restart-survivable, identifier-free detection mechanism is not provided by these handlers. Non-identifier proxies (balance/equity/currency/leverage/company/name changes) are either sensitive, unavailable as events, or not reliable/unique for proving account continuity. **Conclusion:** event-based detection without polling an identifier is not demonstrably available in the current MQL5 EA handler set; polling remains necessary for runtime detection, but restart continuity cannot be proven without forbidden persistent identity (handled conservatively by blocking, though see F-01/F-02 for auto-rebaseline concern).

## 3. Persistence Safety Audit

### 3.1 Save path (`StateStore.mqh:479-582`)

| Branch/step | Evidence | Assessment |
|---|---|---|
| Precondition block when continuity uncertain/manual review (unless fresh safe-init save) | `:482-490` sets error status and returns false | Prevents persisting continuity-uncertain state in normal save path. `BeginSafeInitFromCurrent` uses `SaveInternal(true)` after setting safe flags (`:454-462`). |
| Serialize/validate content | `:492-497` | Invalid serialized payload fails before file ops. |
| Lock acquisition | `:499-503` | Failure returns explicit status, no promotion. |
| Temp handling | `:510` deletes pre-existing temp; `:512-517` write temp or fail; `:519-528` read+validate temp or preserve `.invalid`, delete temp, fail | Temp validated before promotion. |
| Last-known-good protection before risky promotion | `:530-542` if primary exists and is valid candidate (`TryLoadCandidate` allows legacy marker parsing for validity check) copy primary->bak (`:536`); if primary invalid preserve `.corrupt` and keep existing bak as last-known-good (`:539-541`, `backupOk = FileIsExist(bakFull)`); if backup cannot be ensured abort (`:544-551`) preserving tmp `.nobackup` | Does **not** overwrite existing backup with invalid primary content. Backup refresh copies current primary bytes when parseable. |
| Promotion | `:553-558` `FileMove(tmp->dst)` then fallback `WriteTextFile(dst,tmpRead)` if move fails (only after backupOk path) | No explicit pre-delete of dst before move; fallback overwrite occurs only in backup-preserved path. |
| Post-promotion verification | `:560-566` read promoted and require valid current-schema candidate | Prevents success on failed verification. |
| Success/failure reporting | success: set known-good/status ok and return true (`:568-573,581`); failure: set promote/verify failed, operational false/safe-init+manual-review true, log error, return false (`:574-581`) | **Failed promotion/verification is not reported as success.** |

### 3.2 Load/recovery path (`StateStore.mqh:584-644`, helpers `338-387,389-395`)

| Branch/step | Evidence | Assessment |
|---|---|---|
| Candidate discovery | `:591-593` read primary/bak if exist+readable | Deterministic inputs. |
| Primary evaluation | `:595-612` if `TryLoadCandidate(primary,true,...)` preserve legacy evidence if needed and commit; on future schema preserve `.future` and `FailBlocked` (`:608`); on other invalid preserve `.corrupt` and continue to backup (`:609-611`) | Corrupted/future primary preserved. Future schema does not fall through to unsafe recovery. |
| Backup evaluation | `:614-630` same deterministic handling; recovery marked backup/continuity-uncertain in commit (`:620-622`) | Corrupted/future backup preserved. |
| No artifacts | `:632-641` fresh state, safe-init required, returns true (initialized but blocked for risk-increasing) | No unsafe baseline reconstruction from prior files. |
| Artifacts existed but none valid | `:643` `FailBlocked("no_valid_state_artifact", MM_STORE_ERR_RECOVERY_FAILED, true)` resets memory to safe defaults and sets blocked/manual-review (`:389-395`) | No silent apply. |
| Continuity handling on valid restore | `CommitValidatedContent` always sets `MM_STORE_ERR_CONTINUITY_UNCERTAIN`, `operational=false`, `safeInitRequired=true` (`:382-385`) | Prevents auto-authorizing risk-increasing actions from restored state alone. |

### 3.3 Recovery precedence

**Deterministic precedence:** primary valid/legacy-migratable candidate first (`:595-605`) → backup valid/legacy-migratable candidate second (`:614-623`) → no artifacts fresh/safe-init-required (`:632-641`) → otherwise blocked recovery failure (`:643`). Future-schema candidates are blocked with evidence (`:608,626`) rather than downgraded to backup/seed.

### 3.4 Concrete counterexamples / issues

| ID | Severity | Finding | Evidence | Concrete counterexample |
|---|---|---|---|---|
| P-01 | **HIGH** | **Parseable backup can be replaced by a parseable current primary without stronger freshness/integrity semantics.** | `SaveInternal` copies current primary to backup whenever primary passes `TryLoadCandidate` (`StateStore.mqh:535-536`) before promotion. No monotonic/version/timestamp integrity marker compared. | If primary is parseable but semantically stale/regressed (or becomes the only surviving parseable copy), saving replaces backup with that primary (`:536`). A later corruption of the promoted primary causes recovery to load the regressed backup (`:614-623`). When primary is invalid, code correctly preserves it as `.corrupt` and keeps existing backup (`:539-541`). |
| P-02 | **MEDIUM** | **Post-promotion verification failure after fallback overwrite can leave primary replaced while status reports failure/manual review.** | Fallback path may write `tmpRead` to dst (`StateStore.mqh:556`) then post-verify can fail (`:564-566`) leading to `ok=false` and blocked/manual-review status (`:574-578`) but dst remains overwritten content. | If `WriteTextFile(dst,tmpRead)` succeeds but subsequent read/validate fails due to transient IO/read issue, primary on disk may differ from pre-save known-good even though backup was preserved earlier; recovery will prefer primary on next load only if it later validates, else backup — deterministic but intermediate state degraded. |
| P-03 | **MEDIUM** | **`TryLoadCandidate` accepts payloads based on marker presence/JSON reader defaults without strong required-field or checksum integrity validation.** | Plausibility requires `{}`, `}`, and `schemaVersion`/`version` marker (`StateStore.mqh:266-273`); candidate load trusts `CJsonReader` defaults for many fields (`:275-336`, `347-357`). | A truncated/partially corrupted JSON file that still contains `schemaVersion` and braces may parse with defaulted zeros/empties and be treated as a valid candidate, enabling recovery/migration commit (then continuity-blocked) from semantically corrupted protective values. |

**No concrete counterexample found for:** "failed promotion reported as success" (save returns true only after verified promotion, `:568-573,581`); "corrupted or future-schema files not preserved" (evidence copies on invalid/future/legacy paths shown above); "non-deterministic recovery precedence" (fixed primary→backup→fresh→blocked order). "Last valid state deleted before another valid copy exists" is **not directly observed** in reviewed branches because backup is preserved/validated before fallback overwrite and aborts when backup cannot be ensured (`:530-551`), but P-02 shows a degraded overwrite-on-failed-verify window.

## 4. Execution Safety Audit

### 4.1 Paths that can open a new position or increase exposure

| Path | Evidence | Store/guard gating | Classification |
|---|---|---|---|
| UI drag/send -> `CPanelShell::TrySend` -> `CExecutionRouter::Send` | `PanelShell.mqh:230-233,248-249,304,314-343` (build plan, `router.Preflight`, confirm, `router.Send`) | `ExecutionRouter::Send` calls `Preflight` (`ExecutionRouter.mqh:113`); `Preflight` rejects `STATE_NOT_OPERATIONAL` when store present and not operational (`:84-85`) then runs risk/stops/guards (`:87-107`). `Send` executes only if preflight passed (`:113`). | **Risk-increasing (open/increase via market/pending execution). Blocked when store non-operational/safe-init unresolved (`IsOperational()` false).** |
| `CExecutionRouter::Send` -> `CExecutionPolicy::ExecuteWithRetry` -> `CTrade::OrderOpen/PositionOpen` | `ExecutionRouter.mqh:110-125`; `ExecutionPolicy.mqh:123-172` actual order placement at `:131-139` | Inherits router preflight gate (no direct external callers found bypassing router). | **Risk-increasing execution primitive, reached through gated router.** |
| `COrderManager` (`MarketOrder/LimitOrder/StopOrder/OCO/RetryMarketOrder`) | `Include/Core/OrderManager.mqh:11-73` places orders via `m_trade.PositionOpen/OrderOpen` (`:15,21,28,33-34,70`) | No internal store/guard checks. Repository search found **no call sites/instances** using `COrderManager` outside its own definition; EA/UI invoke router/position-manager flows. | **Potentially risk-increasing API, currently not wired into audited execution flow.** Not a demonstrated runtime bypass path. |
| `CPositionManager` (`MoveToBreakEven`, `TrailStop`, `PartialClose`, `TimeBasedExit`, `Close*`) | `Include/Core/PositionManager.mqh:10-62` modifies SL/TP or closes positions only | EA invokes BE/trailing/time exit on existing magic positions in `OnTick` regardless of store readiness (`MoneyManager.mq5:400-416`). These operations do not open new positions or increase volume/exposure. | **Risk-reducing/position-management actions; remain available.** |
| Drag/UI mode toggles, template/profile/stats actions | `PanelShell.mqh:230-312`, `MoneyManager.mq5:434-449` | No order placement; `Send` actions route through `TrySend`/router. | **Not risk-increasing execution.** |

### 4.2 Verification summary

- **All demonstrated new-position/increase-exposure paths are blocked when StateStore is non-operational or safe initialization unresolved:** **Yes, for router-mediated paths.** `StoreReadyForRiskIncreasing()`/`IsOperational()` require operational && !safe-init-required && !manual-review-required (`StateStore.mqh:423-425`, `MoneyManager.mq5:236-239`), and router preflight enforces store operational before send (`ExecutionRouter.mqh:84-85,113`). UI send path cannot bypass router (`PanelShell.mqh:314-343`).
- **Safe risk-reducing management remains available:** **Yes.** `CPositionManager` close/BE/trail/time-exit actions and EA’s position-management loop operate on existing positions without consulting store operational gate (`MoneyManager.mq5:400-416`, `PositionManager.mqh:10-62`).
- **Caveat:** `COrderManager` contains ungated order-placement methods but appears unused; if wired in future without router/guard integration it would be a bypass risk.

## 5. Findings Summary (by Severity)

| ID | Severity | Area | Finding |
|---|---|---|---|
| F-01 | **CRITICAL** | Safe init / protection | Automatic safe initialization resets/rebases runtime and store protective baselines to current MT5 values and clears daily loss/trades/streaks/cooldowns, which can erase or weaken existing daily/total drawdown restrictions and remove effective lockouts; after restart or runtime-detected account switch this can complete automatically and allow risk-increasing actions without explicit user confirmation once save succeeds. |
| F-02 | **HIGH** | Continuity handling | When a previous valid state exists but continuity cannot be proven, state is correctly marked continuity-uncertain, but `OnInit`/switch flow auto-runs safe init and discards restored protective baselines instead of keeping risk-increasing actions blocked pending explicit manual resolution/confirmation; this can silently apply a fresh baseline to an uncertain context from a protection-strength perspective. |
| F-03 | **HIGH** | Persistence / backup hygiene | Save refreshes backup from any parseable current primary (`StateStore.mqh:535-536`) without stronger freshness/integrity semantics, so parseable but semantically stale/regressed primary content can replace backup and later become recovery source (P-01). |
| F-04 | **MEDIUM** | Persistence validation | Candidate validation is marker/parse/default-based and may accept structurally plausible but semantically corrupted payloads (P-03), risking restore of defaulted protective values (still continuity-blocked, but degraded evidence quality). |
| F-05 | **MEDIUM** | Persistence promotion | Fallback overwrite plus failed post-promotion verification can leave primary replaced while operation fails and enters manual-review state (P-02); recovery remains possible via backup but intermediate on-disk state is less clear. |
| F-06 | **MEDIUM** | Account-switch detection | Runtime detection polls `AccountInfoInteger(ACCOUNT_LOGIN)` in memory (`MoneyManager.mq5:278,349`); not persisted/logged, but direct identifier read is used because no reliable event-based, restart-survivable, identifier-free MQL5 mechanism is available in current handlers. Restart continuity remains unprovable by design. |
| F-07 | **LOW** | Execution surface | `COrderManager` exposes ungated order placement APIs (`OrderManager.mqh:11-73`) currently unused in audited flow; future wiring without router/store/guard gates would create bypass risk. |

## 6. Concrete Failure Scenarios

1. **F-01 (daily/total DD weakened on restart):** Account had prior peak 10,000 and day-start equity 10,000; equity now 9,200. Terminal restarts, store loads previous valid state but marks continuity uncertain (`StateStore.mqh:382-385,601-604`), `OnInit` auto-runs safe init (`MoneyManager.mq5:351-355`), `g_prot.Init()`/safe-init set peaks and day-starts to 9,200/current and clear daily loss/streak/cooldown (`Protection.mqh:26-35`, `MoneyManager.mq5:245-253`, `StateStore.mqh:444-451`). Result: drawdown/remaining-DD calculations can report near-zero usage against new baselines, allowing new risk-increasing trades without explicit confirmation.
2. **F-01/F-02 (runtime account switch auto-rebaseline):** Terminal switches to different account at runtime. Tick/timer detects marker change and auto-calls safe init (`MoneyManager.mq5:275-299,386,428`), resetting protection/store baselines to new account’s current values and potentially unblocking trading automatically (`StateStore.mqh:454-473`). Correct to avoid cross-account reuse, but unsafe if interpreted as preserving prior protective restrictions.
3. **F-02 (valid previous state, continuity unprovable):** `state.json` contains valid protective/config state from prior run. On restart, continuity cannot be proven so store blocks (`StateStore.mqh:382-385`), yet EA immediately replaces in-memory protective baselines with fresh current values and may persist/enable them (`MoneyManager.mq5:351-355`, `StateStore.mqh:444-474`) with no manual confirmation.
4. **F-03 (backup regression):** Backup holds last known-good snapshot B1. Primary becomes parseable but semantically regressed state P2; next save copies P2 over backup (`StateStore.mqh:535-536`). Later promotion/write produces invalid primary; recovery loads P2 from backup (`:614-623`) instead of B1.
5. **F-04 (semantically corrupted but parseable state):** File truncated/corrupted yet retains `schemaVersion` and braces; reader defaults yield zeros/empty fields but candidate accepted (`StateStore.mqh:266-273,338-360,371-387`), leading to continuity-blocked restore from meaningless protective values.
6. **F-05 (verify failure after fallback write):** Move fails, fallback write to primary succeeds (`StateStore.mqh:553-558`), but post-promotion read/validate fails (`:560-566`). Function reports failure/manual-review (`:574-581`) yet primary has been overwritten; subsequent restart may recover from backup if primary invalid.

## 7. Recommended Minimal Corrections (no implementation performed)

| Finding | Minimal correction | Notes |
|---|---|---|
| F-01 | **Do not auto-enable risk-increasing actions on safe init when continuity is uncertain or prior protective context may exist.** Separate runtime metrics refresh from protective restriction reset: on restart/uncertain continuity or account switch, refresh runtime reads from current MT5 but keep store/router in blocked/manual-review (or explicit "await confirmation") state until user explicitly confirms reset/acknowledgment. Never derive new peaks/day-start baselines that weaken DD from current equity when prior valid state existed but cannot be proven continuous; prefer conservative lock over auto-rebaseline. | Touch `EnsureSafeStoreInitFromCurrent`/`OnInit`/`HandleRuntimeAccountSwitchIfDetected` flow and/or `BeginSafeInitFromCurrent` status semantics; keep minimal and within Phase 2.1 scope boundaries. |
| F-02 | **Gate resumption on explicit user confirmation** when `RequiresSafeInit` due to continuity uncertainty/manual review; preserve evidence/state and do not call weakening baseline reset automatically. | May require a small explicit confirmation API/state in store and EA/UI hook; avoid speculative redesign. |
| F-03 | Treat backup as last-known-good snapshot: only replace backup from primary when promotion is about to commit a newly validated canonical state and backup is absent/invalid or explicitly rotated; otherwise preserve existing valid backup until a verified successful promotion establishes a newer known-good generation (simple monotonic marker/counter or two-slot backup) while keeping deterministic recovery. | Keep file format simple and policy-compliant. |
| F-04 | Strengthen validation: require essential keys/ranges (schemaVersion, required numeric/string fields present, finite/non-negative where applicable) before accepting candidate; on suspicious/missing essentials treat as invalid and preserve evidence. | Stay within SimpleJson limitations. |
| F-05 | If fallback overwrite path is used and post-verify fails, attempt best-effort restore from preserved backup/last-known-good before returning failure (or mark explicit "primary suspect, backup intact" status) while never reporting success. | Must not delete only valid copy. |
| F-06 | Keep runtime marker in memory only and non-persisted/non-logged (already true); document that no reliable event-based, restart-survivable, identifier-free detection exists in current MQL5 EA handlers. | Policy/privacy constraints limit options. |
| F-07 | Do not wire `COrderManager` into live flow without routing through `CExecutionRouter`/guards/store operational checks, or add equivalent gating. | Preventive. |

## 8. Tests Required to Verify Each Correction

| Correction | Required tests (to add/run in MT5) | Expected verification |
|---|---|---|
| F-01 | (T-A1) Restart with persisted valid state representing DD in progress: simulate prior peak/day-start above current equity, restart/init; assert risk-increasing send blocked and no auto-rebaseline weakens DD without confirmation. (T-A2) Runtime account-switch simulation: marker change triggers flow; assert previous protective restrictions not silently weakened and risk-increasing blocked until explicit confirmation. (T-A3) Confirm streak/cooldown/trade counters not reset in a way that re-enables trading without approval. | `IsOperational()/StoreReadyForRiskIncreasing()` remains false or equivalent pending confirmation; `CProtection`/guard DD metrics do not improve solely due to restart/switch handling. |
| F-02 | (T-B1) Continuity-uncertain load with valid previous state requires explicit user resolution action before `Send/Preflight` allows risk-increasing; (T-B2) negative path ensures no auto-confirm code path. | Router `Preflight` rejects and UI/send path cannot proceed without explicit confirmation state transition. |
| F-03 | (T-C1) Sequence creating valid backup, then parseable-regressed primary, save/promotion, then corrupt primary: recovery must restore intended last-known-good (not regressed) per chosen generation rule. (T-C2) Existing primary-invalid keeps old backup intact. | Backup contents/generation verified by file inspection; deterministic recovery. |
| F-04 | (T-D1) Truncated/semantically incomplete payloads with schema marker treated as invalid and preserved as evidence, not accepted as valid recovery. (T-D2) Valid complete payload still accepted. | `LoadInternal` returns blocked/recovery-failed or skips candidate appropriately; evidence artifact created. |
| F-05 | (T-E1) Inject/force fallback-write + post-verify failure path: assert save returns failure, status manual-review/non-operational, and primary restored or backup recoverable/preferred deterministically. (T-E2) No success reported. | Return value/status/logs and post-restart recovery source. |
| F-06 | (T-F1) Runtime marker change detected only in memory and no `ACCOUNT_LOGIN`/identifier written to `state*` artifacts or logs; (T-F2) restart without identifier continuity blocks risk-increasing pending confirmation. | File/log scan clean of identifiers; behavior consistent. |
| F-07 | (T-G1) Static/code review test: no call sites to `COrderManager` order placement outside gated router path (or if added, router/guard/store checks invoked). | Search/assertion in CI/script or manual audit evidence. |

**Execution note:** no tests were run during this read-only audit; MetaTrader 5/MetaEditor runtime is required to execute the above.
