# Phase 2 (Risk/Execution/Sizing) — Implementation & Test Notes

## Implemented
- `Include/Core/RiskEngine.mqh` (`CRiskEngine`, `MM_RiskContext`, `ENUM_MM_RISK_BASIS`)
  - **Basis:** `Equity` (Personal default), `BalanceDay`, `AllowedDD` (Prop default) = `min(remainingDailyDDMoney, remainingMaxDDMoney)` money budget with fallback to equity when unspecified.
  - **Per-lot risk:** `perLot = (|entry-sl| / tickSize) * tickValue + commissionPerLot (+ swapEstimate when enabled)` (account-currency). Symbol via `SYMBOL_POINT/TICK_VALUE/TICK_SIZE`.
  - **Auto sizing:** `requestedMoney = basis * risk%` (bounded by min/max risk%), capped by `portfolioBudget = requestedMoney - openRiskMoney` and by `DD budget after open = min(remDaily,remMax) - openRiskMoney` (strictest). `lot = floor(riskMoney/perLot, step)` conservative (never exceed risk), normalized to step digits; blocks if no budget or `lot < volume_min`.
  - **Manual lot:** computes risk money/%/RR; **blocked** if aggregate/DD budget exceeded or SL invalid/missing.
  - **No-SL:** SL distance <= 0 → **blocked/invalid** (auto-risk and preview) per frozen spec.
  - **Aggregate open risk:** `CalcOpenRiskMoney(magicFilter,symbolFilter)` sums SL-distance risk of open positions (conservative; positions without SL counted as 0 here — must be guarded/capped by higher-level rules). `BuildContext` populates live equity/balance and open risk.
  - **RR:** `|TP1-entry| / |entry-SL|`.
- `Include/Core/StopsValidator.mqh` (`CStopsValidator`, `MM_StopsCheck`)
  - Min distance `max(SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL) * point`.
  - Pending inference (drag auto-detect): buy below/above market → Limit/Stop; sell inverse. Pending entry, SL/TP, margin (`OrderCalcMargin`), volume bounds, trade-mode checks. `ValidatePlan` full pre-send gate.
- `Include/Core/ExecutionPolicy.mqh` (`CExecutionPolicy`, `MM_ExecPolicy`)
  - Retryable: REQUOTE/PRICE_CHANGED/PRICE_OFF/TIMEOUT/CONNECTION/TOO_MANY_REQUESTS/REJECT/ERROR. Terminal block: INVALID_STOPS/VOLUME/FILL/ORDER/PRICE/EXPIRATION, TRADE_DISABLED, MARKET_CLOSED, NO_MONEY, LIMIT_ORDERS/POSITIONS, HEDGE_PROHIBITED, POSITION_CLOSED. Success: DONE/DONE_PARTIAL/PLACED.
  - Slippage via deviation points (per-symbol/template resolved), bounded retry with delay, partial-fill policy recorded (`Keep` default / `Cancel` / `Reprice-retry` flag for caller).
- `Include/Core/ExecutionRouter.mqh` (`CExecutionRouter`, `MM_ExecResult`)
  - Preflight: `StateStore.IsOperational` gate → `RiskEngine.Calculate` → `StopsValidator.ValidatePlan`; failures reported to `IRejectSink` (central sink). `Send`: preflight + apply policy + execute with retry; exec failures reported to sink. Hook point for `GuardEngine` (Phase 3) before send.

## Scripted tests (run locally in MT5)
- `Tests/Phase2/RiskEngine_Test.mq5`: auto-risk sizing/step-cap, RR≈2, no-SL block, manual lot, aggregate-open-risk cap/block, AllowedDD (min daily/max minus open) cap.
- `Tests/Phase2/StopsValidator_Test.mq5`: valid/invalid SLTP (buy/sell), no-SL, pending type inference, margin ok for min lot.
- `Tests/Phase2/ExecutionPolicy_Test.mq5`: retryable vs terminal vs success classification and reason mapping.

## Deterministic scenarios to verify per symbol class (demo/tester)
- **FX (5-digit, e.g. EURUSD):** 1% of 10k equity, 20-pip SL → expected ~0.50 lots (approx, subject to tick value/step/commission).
- **JPY pair (3-digit, e.g. USDJPY):** correct tick-value conversion (point/tick differs) — lot/risk money matches hand calc.
- **XAUUSD/CFD:** contract/tick specs respected.
- **Crypto:** profile overrides for commission/tick when broker info differs.
- **Caps:** set `remainingDailyDDMoney`/`remainingMaxDDMoney` and `openRiskMoney` so request exceeds budget → reduced or blocked; confirm `cap:aggregate_open_risk`/`cap:DD_remaining`.
- **Stops:** SL inside stops/freeze level and pending too close to market → blocked with `INVALID_STOPS`.
- **Execution:** simulate/observe requote/timeout retry and terminal (invalid stops, no money) no-retry.

## Integration pending (next phases / wiring)
- Source `remainingDailyDDMoney/remainingMaxDDMoney/dayStartBalance` from Protection/Prop guards & StateStore (Phase 3) and per-symbol/template slippage/commission/swap from Profiles.
- Insert `GuardEngine.CanExecute(plan)` in `ExecutionRouter.Send` before dispatch (Phase 3).
- Refine partial-fill remainder actions (cancel/reprice) per broker/order and lifecycle accounting.
- Netting/hedging open-risk aggregation parity (Phase 2 tech debt from Phase 1).