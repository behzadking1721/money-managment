# Test Checklist (Phases 1–7)

Use this checklist for demo/validation. Record evidence (screenshots, logs, Strategy Tester reports, CSV exports) in `Docs/phase1-test-results.md` and per-phase notes as applicable.

## Environment
- [ ] MetaTrader 5 + MetaEditor (stable build recorded).
- [ ] Compile `MoneyManager.mq5`: **0 errors, 0 warnings**.
- [ ] Algo trading enabled in terminal and EA properties; account connected.
- [ ] Test on demo first (Personal/Prop/Crypto modes as applicable). Validate both **hedging** and **netting** accounts where relevant.

## Phase 1 — Foundation (Contracts, State, Lifecycle)
### Build / Scripts
- [ ] `Tests/Phase1/SimpleJson_Test.mq5` passes (round-trip, tagged keys, escaping/unicode, defaults).
- [ ] `Tests/Phase1/StateStore_Test.mq5` passes (init/load/save, atomic write, `.bak`, migration hook, fail-safe on future version, server-time fallback behavior as designed).
- [ ] `Tests/Phase1/Lifecycle_Map_Test.mq5` passes (transaction → normalized `MM_TradeEvent` mapping, reject sink basics).

### Persistence & Recovery (Phase 12 / TD-05 TD-17)
- [ ] `Tests/Phase12/RecoveryEngine_Test.mq5` passes:
    - Fresh init: not operational, risk-increasing blocked, risk-reduction active, explicit resolution required.
    - Explicit new protective init: operational, risk-increasing allowed.
    - Simulated restart: continuity uncertain, state preserved, not operational, no auto rebase.
    - Corrupt primary + valid backup: backup fallback, blocked, risk-reduction active, original+backup preserved.
    - Corrupt primary + corrupt backup: blocked/manual review, no auto reset/rebase.
    - Future schema: blocked, no rebase, no overwrite.
    - Privacy: no login/server/broker key persisted.
    - Risk-reduction active invariant holds in all states.

### Manual / Integration
- [ ] State stored per account under `MQL5/Files/MoneyManager/` (`state_<login>.json|.lock|.bak|.tmp`).
- [ ] Restart-safe: per-symbol/template/UI-relevant persisted fields restore after EA/chart restart.
- [ ] Multi-chart/instance lock: second instance handles lock contention; stale lock takeover (default ~30s) logged/recovered.
- [ ] Version migration/fail-safe: older supported version migrates; unsupported future version marks store non-operational and blocks trading (no overwrite).
- [ ] Central reject sink receives execution/guard rejects (no parallel reject paths).

## Phase 2 — Risk, Stops, Execution
### Build / Scripts
- [ ] `Tests/Phase2/RiskEngine_Test.mq5` passes (auto vs manual sizing, risk basis, RR, no-SL block, aggregate open-risk + DD remaining caps, lot step/limits).
- [ ] `Tests/Phase2/StopsValidator_Test.mq5` passes (stops/freeze min distance, pending type/entry validity, margin, volume bounds, symbol property gaps).
- [ ] `Tests/Phase2/ExecutionPolicy_Test.mq5` passes (retryable vs terminal vs success/partial, unknown retcode classification/reason).

### Manual / Integration
- [ ] Auto risk% sizing produces valid lot and respects min/max/caps on FX, JPY, metals/crypto symbols as applicable.
- [ ] Manual lot mode respected and still subject to safety/validity checks.
- [ ] No-SL blocks auto-risk/send per design.
- [ ] Aggregate open risk + remaining Daily/Max DD cap sizing/sending correctly.
- [ ] Stops/freeze/invalid volume/margin/market-state rejections surfaced with clear reason codes/messages.
- [ ] Retry/terminal retcode behavior correct; partial fills logged/handled per policy.

## Phase 3 — Unified Guards
### Build / Scripts
- [ ] `Tests/Phase3/GuardEngine_Test.mq5` passes (priority order, ALLOW/WARN/BLOCK, first block, sink routing, preview without side effects).

### Manual / Integration
- [ ] **Permission/Connection** guard blocks when terminal/EA/account/symbol trading disallowed or disconnected.
- [ ] **Prop** guard enforces daily/max DD, trade/position/consistency/weekend rules as configured.
- [ ] **Protection** guard enforces daily/weekly/monthly loss, profit lock, max DD, trades/day, consecutive loss/cooldown.
- [ ] **News** guard: blackout blocks (when configured), stale/offline warns by default and blocks only when offline-block configured.
- [ ] **Session/Spread** guard: session filter and max/warn spread thresholds behave correctly.
- [ ] All BLOCK/WARN reasons reported to central status/reject sink and visible in UI/logs.

## Phase 4 — Drag & Drop UI & Live Preview
### Manual / UI
- [ ] Mini/Drawer panel renders; hide/show, mini toggle, language toggle (EN/FA), tabs (Main/Stats) work.
- [ ] Drag mode: create/drag **Entry/SL/TP** lines (TP1–TP3 as supported); buy/sell direction correct.
- [ ] Market vs pending auto-inference (limit/stop) correct; manual override if available.
- [ ] Risk% / manual-lot toggle updates sizing context; template save/apply (T) restores geometry+risk settings.
- [ ] Live preview shows direction, market/pending, entry/SL/TP, lot, risk%, risk money, R:R, spread, and guard/risk/stop status (ready/warn/blocked) with reasons.
- [ ] Instability/spread jump warning shown when detected.
- [ ] Confirm dialog before send; **no silent send**. Preflight blocks show reason; successful send clears/deactivates as designed.
- [ ] News banner and session badge update; status/log line reflects recent events/rejects.

### Hotkeys (UI/EA)
- [ ] `H` hide/show panel, `D` toggle drag, `B`/`S` buy/sell drag, `Enter` send, `Esc` cancel/clear drag, `K` toggle Stats tab, `P` select position.
- [ ] `R` toggle sizing mode (auto risk% ↔ manual lot), `T` save/apply template (per implementation).

## Phase 5 — In-trade Management
### Manual / UI
- [ ] Select open position (`P` or UI) and drag SL/TP with server sync/modify.
- [ ] Move to BE, apply trail step, partial close (e.g. 50%) work for selected position.
- [ ] Close-selected works; multi-position/symbol-wide close actions require explicit opt-in/confirmation.
- [ ] Magic/symbol filtering respected (EA-managed positions).
- [ ] Automated BE/trail/time-exit behaviors (inputs) operate on ticks as configured.

## Phase 6 — Statistics, Profiles, Alerts, CSV
### Manual / Integration
- [ ] Stats/KPIs update from trade lifecycle events: trades, win rate, PF, expectancy, Avg R, net, max DD, avg duration.
- [ ] Per-account-mode view/filter behaves correctly; R based on realized net P/L ÷ initial risk (planned-risk fallback where needed).
- [ ] CSV export writes trade history to `MQL5/Files/MoneyManager/MoneyManager_trades.csv` (or configured path) with expected columns.
- [ ] Profiles (Personal/Prop/Crypto): defaults load, switch/next works, persist per account, export/import JSON (`MoneyManager\profile_import.json` for import).
- [ ] Alerts fire with cooldown for guard blocks/warns (incl. DD/loss), news blackout, connection lost/restored, DD-cap/daily-loss events (per configuration/channels).

## Phase 7 — Hardening & Integration
### Build / Scripts
- [ ] `Tests/IntegrationTest.mq5` passes/smoke-checks: logger init, news staleness/source, protection DD/remaining, prop DD helpers, retcode classification incl. unknown, stops validation, stats aggregation/open-risk, guard decisions (stale warn/block, session block).

### Manual / Integration
- [ ] `g_mmLog` writes rotated logs under `MQL5/Files/MoneyManager/logs/`.
- [ ] Real open risk fed into risk context (tracked/live positions; partial-close aware).
- [ ] DD/day-start/peak baselines integrated from Protection/StateStore/Profile/Prop and reflected in guards/sizing.
- [ ] News staleness/source (`live/cache/manual/stale`) and offline/block behavior correct; banner shows source.
- [ ] Partial close/in-out events aggregated; hedging/netting position behavior validated on target account type.
- [ ] Unknown retcodes, symbol property gaps, magic/suffix cases logged and handled safely.
- [ ] Bilingual EN/FA labels and tooltips render correctly in panel/preview/drag elements.

## Final Acceptance
- [ ] All requested phase code compiled clean (0 errors, 0 warnings).
- [ ] Critical flows (drag preview → guard preflight → confirm → send/modify/close) verified on demo.
- [ ] Known limitations/debt reviewed in `Docs/tech-debt.md`; Phase 1 evidence/tag items completed as required.
- [ ] Backup `MQL5/Files/MoneyManager/` before upgrades/mode changes.
