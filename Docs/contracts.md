# Shared Contracts (Phase 1, Frozen)

Version: **1.0** (struct `version` fields enable state migration).

## Design Rules
- All modules communicate via contracts in `Include/Core/Contracts.mqh`.
- No circular dependencies: `Contracts` has no project includes except MQL5 std where needed.
- Reject reasons carry `reasonCode` + EN/FA messages (bilingual-ready); UI may render directly or by code.
- Listener model: `ITradeEventListener` interface for testability.
- **Schema evolution:** any state/contract schema change **must bump `MM_CONTRACT_VERSION` (or relevant `version`) and implement an explicit migration hook**; loaders must remain backward-migrating and fail-safe on unknown future versions.
- **Reject sink (mandatory):** `IRejectSink` / `CTradeLifecycle` central sink is the single path for execution retcode rejects and guard decisions. **Phase 3 GuardEngine must route all BLOCK/WARN rejects through this sink; no separate/parallel reject logging paths are allowed.**

## Enums
- `AccountMode { ACCOUNT_PERSONAL, ACCOUNT_PROP, ACCOUNT_CRYPTO }`
- `SizingMode { SIZING_AUTO_RISK, SIZING_MANUAL_LOT }`
- `GuardDecision { GUARD_ALLOW, GUARD_WARN, GUARD_BLOCK }`

## Core Structs
- **TradePlan** (`version`): identity (symbol, magic, templateId/profileId), side/orderType, entry/sl/tp[], sizing mode & inputs, risk params, slippage, comment/context.
- **RiskResult** (`version`): computed lot, riskMoney, riskPct, rr, basis, capsApplied[], warnings[], valid/blocked flag.
- **GuardResult** (`version`): decision, guardId, priority, reasonCode, messageEN, messageFA, context (symbol/values).
- **TradeEvent** (`version`): event type (Open/Close/Modify/PartialFill/Reject), ids (ticket/order/deal), symbol, side, volume, price, sl, tp, profit, server/local time, retcode, reason.
- **Profile / Template** (`version`): ids, accountMode, sizing/risk defaults (per-symbol/template persisted), slippage/snap prefs, import/export metadata.

## StateStore (contract)
- File: `MQL5/Files/MoneyManager/state_<account_login>.json` (per account; mode & profiles inside).
- Lock: `state_<account_login>.lock` (owner/chart id, terminal pid, local ts, server ts). Acquire retries (bounded). **Stale lock** takeover if lock age > `staleSec` (default **30s**, local clock): 30s is long enough to cover normal save critical sections/retries but short enough to recover after a crash/hang without long downtime. Primary takeover signal is age (clock skew can misclassify — operational caveat); owner/pid recorded for diagnostics. On takeover a warning is logged.
- Atomic write: `Backup()` (single `.bak`, overwritten) → write `<state>.tmp` → move/replace to `<state>.json`. **Fallback:** if move fails, direct write is performed **only after `.bak` already exists**; failure is logged.
- Time: resets/counters use **server time** (`TimeTradeServer()`); if unavailable falls back to `TimeCurrent()` and sets explicit `timeFallback=true` with a **logged warning** (prop-risk relevant). UI/ops must surface this warning so resets/counters are not assumed server-accurate.
- Fail-safe: if loaded state `version > MM_CONTRACT_VERSION`, store becomes **non-operational** (`IsOperational()==false`), load fails, no overwrite. **Integration requirement:** EA/orchestrator and any send/modify path **must gate on `IsOperational()==true` and refuse all trading/actions** when false (true fail-safe, not warn-only).
- Counters/resets/cooldowns keyed to effective server time; persisted markers survive restart.
- Migration: loader reads `version`; `<=0` treated as v1, `<current` migrated forward (explicit hook), `>current` fails safe (no overwrite). **Schema change ⇒ bump version + migration hook.**

## TradeLifecycle (contract)
- Single source: `OnTradeTransaction` → normalized `MM_TradeEvent` → dispatch to registered `ITradeEventListener`.
- Central reject-reason sink: `RecordReject` (execution/retcode) and `RecordGuardReject` (guard BLOCK/WARN) — **both** must flow to the same sink (see `IRejectSink` / `RecordGuardReject`). BLOCK emits `MM_EVENT_REJECT`.
- **Event semantics (Phase 1):**
  - `DEAL_ADD` + `DEAL_ENTRY_IN` → `OPEN`. `DEAL_ENTRY_OUT/INOUT` → `CLOSE` (full or position-reducing; consumers may inspect remaining position/volume — hedging/netting aware handling refined in later phases/tests).
  - `REQUEST` failure retcode (not done/placed/partial) → reject sink record. `DONE_PARTIAL` → `PARTIAL_FILL` event carrying filled volume/price from result.
  - `ORDER_UPDATE`/`POSITION` transaction → `MODIFY`.
- **Netting vs hedging (Phase 2 tech debt):** MT5 deal stream differs by account margin mode; Phase 1 normalizer is conservative (records deal facts). Full parity for partial-close-in-netting and position aggregation is **deferred/validated in Phase 2** with explicit demo tests (record in `Docs/phase1-test-results.md` if only one mode tested).
- Idempotency: listeners must tolerate duplicate delivery on retry/replay where unavoidable.

## Phase 1 Decisions (resolved)
- **Format:** JSON (minimal project serializer/parser for known schema; no external dependency). Limitations: `Docs/simplejson-limitations.md`.
- **State file:** `state_<account_login>.json` (single per account).
- **Listeners:** `ITradeEventListener` interface (observer-style registration).
- **Reject text:** `reasonCode` + `messageEN` + `messageFA` in contracts; UI may select by locale. Unified sink for execution + guards.
