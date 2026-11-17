# Phase 2 Preparation (Risk/Execution/Sizing) — Started

> Phase 1 DoD is not yet complete (local tests/evidence pending). Phase 2 implementation work here is **scaffolding/prep** to unblock immediate start after Phase 1 sign-off.

## Delivered scaffolding
- `Include/Core/RiskEngine.mqh` — `CRiskEngine`
  - **Risk basis:** `Equity` (Personal default), `BalanceDay`, `AllowedDD` (Prop default = `min(remaining Daily DD, remaining Max DD)` money budget).
  - **Per-lot risk formula:** `perLot = (|entry-sl|/point * point / tickSize) * tickValue + commissionPerLot (+ swapEstimate if enabled)`.
  - **Auto sizing:** `riskMoney = basis * risk%`, clamped by profile bounds and **aggregate/DD caps** (`openRisk + newRisk ≤ remaining DD budgets`), `lot = floor(riskMoney/perLot, step)` with min/max/volume caps; blocks if no budget or below min lot.
  - **Manual lot:** carries lot, computes `riskMoney/risk%/RR` preview; **No-SL (SL=0)** blocks auto-risk and blocks preview validity (per frozen A).
  - **RR helper:** `|TP1-entry| / |entry-SL|`.
- `Include/Core/StopsValidator.mqh` — `CStopsValidator`
  - Min distance = `max(SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL) * point`.
  - Pending entry placement vs Ask/Bid + min distance; SL/TP side/distance validation; `OrderCalcMargin` sufficiency + high-usage warning.
- `Include/Core/ExecutionPolicy.mqh` — `CExecutionPolicy` / `MM_ExecPolicy`
  - Slippage (per-symbol/template resolved), retry/no-retry retcode classification per frozen spec, partial-fill policy (`Keep` default / `Cancel` / `Reprice-retry`), retcode→reason mapping.

## Integration notes (to complete in Phase 2)
- Wire `MM_RiskContext.openRiskMoney` from live positions (SL distance) — conservative, aggregate open+new.
- Resolve per-symbol/template `MM_ExecPolicy.maxSlippagePoints` and commission/swap estimates from `Profile/Template/SymbolInfo` (+ overrides for crypto).
- Pre-send pipeline: `RiskEngine.Calculate` + `StopsValidator` + `GuardEngine.CanExecute` (Phase 3) + `ExecutionPolicy` send with retry handling and reject-sink reporting.
- Add deterministic unit/script tests for FX/JPY/crypto sizing, caps, and retcode handling.

## Open (confirm during Phase 2 implementation)
- Exact conservative aggregation for hedged/correlated positions (default: no netting credit, as frozen).
- Swap estimate source/precision per broker (profile override supported by plan).