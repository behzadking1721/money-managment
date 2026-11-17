# Phase 1 Tests

## Scope
- StateStore serialize/restore (incl. schema `version` migration hook, per-symbol/template state)
- TradeLifecycle `OnTradeTransaction` → `TradeEvent` normalization & dispatch
- Reject-reason sink recording (execution + guard contract)
- SimpleJson round-trip (supported subset)
- Manual demo: open/close/modify/partial + restart + multi-chart lock + stale lock + reject

## Scripted (run in MT5 as Scripts)
- `SimpleJson_Test.mq5`: round-trip on state-like keys, quotes/backslash/slash, Persian text passthrough, negative/decimal, bools, defaults, empty values.
- `StateStore_Test.mq5`: init/save/reload, per-symbol & UI restore, legacy `version=0` migration path.
- `Lifecycle_Map_Test.mq5`: request-failure reject, partial-fill event, guard-reject sink/dispatch. **Note:** deal-add (open/close/partial-close in netting vs hedging) requires live/demo transactions — covered in manual checklist.

## Manual demo checklist (evidence required)
1. Attach EA on demo chart; place market order → verify OPEN event logged.
2. Modify SL/TP → verify MODIFY event.
3. Partial close → verify event(s) & fields; **record netting vs hedging** behavior (if only one account type available, state which was tested and which remains Phase 2 debt).
4. Close position → verify CLOSE event with profit/commission/swap fields.
5. Restart terminal/EA → verify StateStore restores per-symbol sizing/template, UI state, counters (server-time reset respected; if server unavailable, `timeFallback` warning visible in log/UI and behavior documented).
6. **Multi-chart (same account):** load EA on 2 charts → shared state, lock contention/retry, **no duplicate counter increments / no double-send in guarded paths** (writer/reader behavior evidenced).
7. **Stale lock:** create stale `state_<login>.lock` (old ts) → verify takeover after timeout, warning logged, recovery consistent.
8. Force reject (e.g. invalid stops) → verify reject-reason sink entry (code/message/context/retcode).
9. **State migration:** place state file with older/missing `version` → verify load/migrate. Place future `version` (> supported) → verify **fail-safe: load fails, store non-operational, no overwrite, EA must not trade**.
10. Record MetaEditor compile log (0 errors/warnings) and MT5 build.

## Pass criteria
- All scripted assertions pass; manual checklist completed with evidence (logs/screens/notes) in `Docs/phase1-test-results.md` attached to phase commit/PR. No `v0.1.0-phase1` tag until pass.
