# MT5 Money Manager — Drag & Drop, Risk & Guards (Implementation Plan)

## Goal
Evolve the existing MQL5 EA into a modular money-management tool for Personal/Prop/Crypto accounts with chart drag-and-drop trade placement (market & pending), live lot/risk/RR preview, strict pre-send guards, in-trade management, and reliable stats — with per-phase tests.

## Frozen Decisions & Constraints

### (A) Risk Definition
- **No-SL / SL=0:** treated as undefined risk → **BLOCK** auto-sizing & send in auto-risk mode; UI shows explicit error. Manual-lot mode still requires a valid SL for preview/R calculation (warn + block send if SL missing) unless an explicit, opt-in “no-SL” expert setting is enabled (default **off**).
- **Cumulative daily/open risk:** `RiskEngine` checks **aggregate** = risk of all currently open positions (by SL distance to market/entry for pending-as-configured) + risk of the new order/plan; must stay within allowed cap. Correlated/hedged positions counted conservatively (no netting credit unless explicitly configured later).
- **Risk% scope:** risk% is the **allowed budget over the configured basis** applied to the plan while **capped against aggregate exposure** — i.e. new-trade lot is sized from risk% but reduced/blocked so `(open_risk + new_risk) ≤ allowed_remaining`.

### (B) Prop DD — Details (configurable; defaults noted)
- **Daily DD basis:** configurable `Equity (live)` / `Balance (day-start)`; **default = Equity (live)** for intraday breach safety. Breach check uses the stricter of configured basis vs remaining allowed-DD cap.
- **Max DD type:** configurable `Static` (from initial/start balance or configured high-watermark anchor) / `Trailing` (trails peak equity/balance); **default = Static**. Trailing anchor source configurable (peak equity). Effective remaining Max DD = `maxDD_limit - currentDD_from_anchor`.
- **Daily reset time:** configurable timezone/source — `Server` / `Local` / `NY (America/New_York)` with hour:minute; **default = Server 00:00**. Used for daily counters and day-start balance snapshots (prop time-source = server by default, overridable).
- **Consistency rule (profit/day cap):** **optional, configurable** (default **off** for Personal; available/presettable for Prop). When enabled, blocks/warns per configured % of target/profit.

### (C) ExecutionPolicy
- **Slippage:** max allowed slippage (points) definable **per-symbol and per-template** (with global default).
- **Retcode handling (explicit):**
  - **Retry** (bounded, with backoff): `TRADE_RETCODE_REQUOTE`, `TRADE_RETCODE_PRICE_CHANGED`, `TRADE_RETCODE_PRICE_OFF`, `TRADE_RETCODE_TIMEOUT`, `TRADE_RETCODE_CONNECTION`, `TRADE_RETCODE_TOO_MANY_REQUESTS`, transient `TRADE_RETCODE_REJECT/ERROR` as configured.
  - **No-retry + BLOCK/fail with reason:** `TRADE_RETCODE_INVALID_STOPS`, `TRADE_RETCODE_INVALID_VOLUME`, `TRADE_RETCODE_INVALID_FILL`, `TRADE_RETCODE_INVALID_ORDER/PRICE/EXPIRATION`, `TRADE_RETCODE_TRADE_DISABLED`, `TRADE_RETCODE_MARKET_CLOSED`, `TRADE_RETCODE_NO_MONEY`, `TRADE_RETCODE_LIMIT_ORDERS/POSITIONS`, `TRADE_RETCODE_HEDGE_PROHIBITED/FIFO_CLOSE`, other terminal codes. All surfaced to `StatusLog`.
- **Partial fill:** configurable policy — `Keep` remainder (default) / `Cancel` remainder / `Reprice-&-retry` remainder within slippage & retry budget. Result logged and reflected in lifecycle/stats.

### (D) StateStore
- **Storage:** **file-based** in terminal/common data folder (structured JSON or INI-like key/value), **not** GlobalVariables for complex state. Atomic write (temp+replace) where possible.
- **Scope & concurrency:** **shared per account+EA instance scope** (keyed by account/magic/profile context) so multi-chart loads share state; guarded with a lightweight file lock/owner timestamp to prevent double-send, counter races, and inconsistent daily/cooldown locks.
- **Time source for locks/cooldowns/resets:** **server time** (default) for daily/weekly resets and cooldowns, especially Prop; configurable only where explicitly noted. Persist last-reset markers to survive restart.

### (E) News (provider-agnostic)
- **Source abstraction:** `INewsProvider` (Phase-1 = ForexFactory + local cache + manual). Swappable without core changes.
- **Currency mapping:** symbol → affected currencies set: split base/quote for FX/CFD pairs (e.g. `EURJPY` → `{EUR, JPY}`); metals/indices via configurable map; **crypto** mapped to its base asset + quote (e.g. `BTCUSD` → `{BTC, USD}`) with per-symbol/profile override.
- **Impact levels:** `low/med/high` each configurable to `ignore | warn | blackout`. **Default:** high = blackout (when blackout enabled), med/low = warn/ignore per profile defaults.
- **Timezone:** all event times normalized to a single internal epoch/UTC in `NewsManager`; display in user-selected tz.
- **Offline behavior:** default **warn** with “stale/cache” indicator; configurable blackout-on-stale. **Cache TTL** and **fetch retry count/backoff** configurable (sensible defaults, e.g. TTL 60 min, 3 retries).
- **Overrides:** per-event manual **edit/delete/move/impact** persisted in cache/overrides store.

### (F) Guards — Priority & Behavior
- **Evaluation order (reasons reported in this priority):** `Permission/Connection` → `Prop` → `Protection` → `News` → `Session/Spread` → `Stops/Margin/Execution validity`.
- **Block vs Warn (defaults):** **BLOCK** = permission/trade disabled, prop DD/limits, protection hard limits (daily/weekly/monthly/maxDD/cooldown/max trades when breached), invalid stops/margin/volume, configured news blackout; **WARN** = spread elevated (below hard cap), news upcoming/offline-stale (when not configured to block), swap/rollover, non-fatal conditions. Final send requires no BLOCK reasons.

### (G) Drag & Drop
- **ATR snap:** configurable **period** and **timeframe** (default period 14, timeframe = chart TF or template override).
- **Visual vs Virtual SL/TP:** `Server` (real broker SL/TP) default; `Virtual` (client-managed) opt-in with persistent **risk warning** in UI (gap/disconnect risk) and clear indicator. Behavior explicit per mode.
- **Market instability during drag:** if spread widens beyond threshold or price gaps/jumps, preview shows **warning**, auto-pauses/flags send; **no silent send** — re-confirm required.
- **Templates include:** geometry (Entry/SL/TP/partials lines & order-type intent) **plus** risk%/sizing mode and per-template params (slippage, snap prefs) so behavior restores per template (and still per-symbol persisted).

### (H) Stats
- **R definition:** `R = realized P/L (net of commission/swap when available) ÷ initial risk amount` of that trade (money risk at entry from initial SL distance & filled volume).
- **Max DD:** **peak-to-trough** on the equity curve (configurable sampling, e.g. per closed trade / periodic).
- **Segmentation:** stats tracked and viewable **per account-mode** (Personal/Prop/Crypto separated).

### (I) Quality & Delivery
- **UI language:** **bilingual-ready** (EN/FA) with resource strings; default EN, FA selectable.
- **Build/compat:** target **MetaTrader 5 (build ≥ current stable)**, MQL5; document minimum tested build in README.
- **Logging:** file log with **path, rotation/size cap, levels (info/warn/error/debug)**; reject reasons and lifecycle events recorded.
- **Backup/Restore:** export/import settings & profiles; **pre-update backup** of state/profile files documented/automated where feasible.
- **Ownership:** **source delivery & IP/ownership terms defined explicitly in the contract** (outside code; noted as delivery requirement).

### (J) Out of Scope (explicit)
- ML/AI or auto-optimization. Strategy backtesting (money-management only). Multi-account / multi-terminal sync (deferred/future phase).

### (K) Git, Tests & Process (mandatory per change)
- **Repo layout:** `Experts/`, `Include/`, `Tests/`, `Docs/`, plus `README` (build/run/test) and `CHANGELOG` (phase-based). Add `.gitignore` for MT5 artifacts (`*.ex5`, logs, local `data/`, tester caches as appropriate).
- **After every significant change:** commit with clear message, **push to GitHub**, and run the phase’s tests — record results (test log, Strategy Tester output, manual checklist) in the commit/PR. **No phase is “done” until its acceptance tests pass and are on GitHub.**

## Target Architecture (modules under `Include/`)
- `Core/` `RiskEngine.mqh`, `StopsValidator.mqh`, `ExecutionPolicy.mqh` (retcodes/slippage/partial-fill).
- `Trade/` `OrderService.mqh`, `PositionService.mqh`, `TradeLifecycle.mqh` (`OnTradeTransaction` dispatcher).
- `Guards/` `IGuard` + `GuardEngine.mqh` (`PermissionGuard`, `PropGuard`, `ProtectionGuard`, `NewsGuard`, `SessionSpreadGuard`, validity/margin) → `Allow/Block/Warn + reason`.
- `State/` `StateStore.mqh` (file-based JSON/INI, shared account-scope, lock, per-symbol/template & per-mode persistence).
- `News/` `INewsProvider.mqh`, `FFNewsProvider.mqh`, `NewsCache.mqh`, `NewsManager.mqh` (normalize tz, map currency, overrides, TTL/retry).
- `Session/` `SessionManager.mqh` (DST-aware schedule, session display/colors).
- `Profiles/` `ProfileService.mqh` (Personal/Prop/Crypto, templates incl. risk/mode/slippage/snap, Import/Export).
- `Stats/` `StatsService.mqh`, `TradeLogger.mqh` (CSV from lifecycle; R, equity peak-to-trough DD, per-mode).
- `UI/` `PanelShell.mqh` (Mini/Drawer), `NewsBanner.mqh`, `SessionBadge.mqh`, `StatusLog.mqh`, `DragTool.mqh` (`OnChartEvent`), `PreviewOverlay.mqh`, bilingual strings.
- `MoneyManager.mq5` thin orchestrator.

## Phased Plan & Validation (each phase: implement → test → commit/push with results)

### Phase 1 — Foundation: State, Lifecycle, Contracts, Repo
- **Tasks:** Repo scaffold (`Experts/Include/Tests/Docs`, README, CHANGELOG, `.gitignore`). Shared contracts (`TradePlan`, `GuardResult`, `RiskResult`, `SizingMode`, `AccountMode`, reasons). `StateStore` (file, lock, per-symbol+per-template, resets/cooldowns server-time, restart-safe). `TradeLifecycle` (`OnTradeTransaction` normalized events). Central log/reject-reason sink.
- **Acceptance:** restart restores per-symbol/template & counters; shared state safe across charts; lifecycle events on open/close/modify/partial; repo/docs in place.
- **Tests:** state serialize/restore & lock behavior; demo lifecycle after restart; results committed.

### Phase 2 — Risk/Execution & Accurate Sizing
- **Tasks:** `RiskEngine` (auto from risk% vs SL, basis by mode, aggregate open+new cap, min remaining Daily/Max DD cap, commission/swap est., tick/contract convert, manual mode, per-symbol/template). No-SL handling per (A). `StopsValidator` (stops/freeze/margin). `ExecutionPolicy` (slippage, retcode retry/no-retry, partial-fill policy). Pre-send block/warn+reasons.
- **Acceptance:** lots/risk$/RR correct on FX/JPY/crypto; aggregate & prop caps enforced; invalid stops/margin blocked with reason.
- **Tests:** deterministic calc cases; Strategy Tester/demo incl. partial-fill & retry/terminal retcodes; results committed.

### Phase 3 — Unified Guards
- **Tasks:** `GuardEngine` with priority (F): Permission/Connection, Prop (DD daily/max static|trailing, reset, consistency opt), Protection (daily/weekly/monthly, maxDD, profit lock, cooldown, max trades/consec), News (impact mapping, warn/blackout, offline stale), Session/Spread, validity/margin. Single `CanExecute(plan)` for preview+send.
- **Acceptance:** every decision returns reason; blocks prevent send; warn vs block per config/defaults.
- **Tests:** simulated day/week/reset/DD/news/spread/permission scenarios + demo; results committed.

### Phase 4 — Drag & Drop UI & Live Preview
- **Tasks:** `DragTool` (Entry/SL/TP1-3/partials), `OnChartEvent` drag, auto market/pending detection + override, reverse, snap (price/ATR period+TF), RR lock, +/- risk, template save/apply (geometry+risk/mode/slippage/snap). `PreviewOverlay` live Risk/Guard. `PanelShell` Mini/Drawer, `NewsBanner` (source/tz/countdown, impact color), `SessionBadge`, `StatusLog`. Visual/Virtual SL-TP modes with warnings. Spread/price-jump → warn, no silent send. Confirm before send.
- **Acceptance:** live updates; correct inference/override; blocked reasons visible; restart restores UI/template state.
- **Tests:** manual walkthrough (market, limit/stop, multi-TP, pending reprice/type flip, instability cases) + screenshots/logs; results committed.

### Phase 5 — In-Trade Management
- **Tasks:** Drag-modify SL/TP/BE on positions & pending (server sync, stops/freeze). BE, trailing/lock-profit, staged partial close, time/swap-aware actions. Bulk actions **opt-in + confirm + target/effect preview**.
- **Acceptance:** broker state synced; bulk only on confirmed selection; guards respected.
- **Tests:** demo BE/trail/partial, pending modify, bulk confirm; results committed.

### Phase 6 — Stats, Profiles, Alerts, CSV
- **Tasks:** `StatsService/TradeLogger` from lifecycle only (net P/L, R, duration). KPIs: WinRate, PF, expectancy, avg R, peak-to-trough max DD, streaks; per account-mode. CSV/export & snapshots. `ProfileService` Personal/Prop/Crypto + templates, Import/Export. Per-event alerts (incl. connection/news/guard). Backup/restore flow.
- **Acceptance:** KPIs/CSV match closed trades; profile round-trip; alerts correct.
- **Tests:** reconcile vs known trades; export→import equivalence; results committed.

### Phase 7 — Hardening & Integration
- **Tasks:** Suffix/magic, hedge vs netting, partial fills, requotes, symbol-info gaps/overrides, i18n strings (EN/FA), log rotation, input validation, UX polish, pre-update backup docs.
- **Acceptance:** no unhandled retcodes; guards/UI/state consistent across restart/symbol/chart changes.
- **Tests:** full regression (Tester + demo checklist) covering guards, drag, lifecycle/stats, prop caps, offline-news warn/blackout; results committed.

## Risks / Notes
- ForexFactory schema/availability changes → isolated `FFNewsProvider` + cache/manual fallback.
- Broker symbol-info gaps (esp. crypto) → manual overrides in profile.
- Chart drag/event limits in MT5 → encapsulate in `DragTool` with snap/confirm safeguards.
- Multi-chart shared state needs careful locking to avoid races/double-sends.

## Out of Scope (explicit)
- ML/AI or auto-optimization.
- Strategy backtesting (money-management/execution tooling only).
- Multi-account / multi-terminal synchronization (deferred).
