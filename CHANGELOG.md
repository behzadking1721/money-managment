# Changelog

All notable changes to this project are documented here (phase-based).

## [v0.1.0-phase1] - Unreleased (Phase 1: Foundation)

### Added
- Repository skeleton: `Experts/`, `Include/`, `Tests/`, `Docs/`, `.kilo/plans/` with frozen implementation plan.
- Project docs: `README.md`, `CHANGELOG.md`, `.gitignore` (MT5 artifacts, logs, local data, sensitive sets, `.continue`, tracked only `.kilo/plans`).
- Frozen shared contracts (`Include/Core/Contracts.mqh`, `Docs/contracts.md`): `AccountMode`, `SizingMode`, `GuardDecision`, `TradePlan`, `RiskResult`, `GuardResult`, `TradeEvent`, `Profile`, `Template` with schema `version` for state migration.
- Unified reject sink contract: `Include/Core/RejectSink.mqh` (`IRejectSink`); `CTradeLifecycle::RecordGuardReject` for guard BLOCK/WARN + execution rejects.
- File-based `StateStore` per account (`MQL5/Files/MoneyManager/state_<login>.json`): shared lock (owner/pid recorded) + stale-lock takeover (default 30s, logged), **atomic** write (tmp→move, fallback direct **after** `.bak`), single `.bak`, server-time counters/resets with explicit `timeFallback` + warning, fail-safe non-operational on future `version` (no overwrite / no trading), restart-safe per-symbol/template persistence, version migration hook.
- `TradeLifecycle` (`OnTradeTransaction`) normalizing to `TradeEvent`, `ITradeEventListener` dispatch, central reject-reason sink (execution + guards contract). Unified reject path mandated for Phase 3 (`IRejectSink`, no parallel sinks).
- Phase 1 tests/checklists & scripts: `Tests/Phase1/SimpleJson_Test.mq5`, `StateStore_Test.mq5`, `Lifecycle_Map_Test.mq5`, manual checklist, `Docs/phase1-test-results.md` (pending real execution), `Docs/simplejson-limitations.md`.

### Notes
- Build and functional testing are performed locally in MetaEditor/MT5; evidence recorded in `Docs/phase1-test-results.md`.
- **Phase 1 not complete until:** local MetaEditor build (0 errors/warnings) and all Phase 1 tests (incl. multi-chart lock, stale-lock recovery, state migration, netting/hedging event cases as applicable) are executed and evidence recorded in `Docs/phase1-test-results.md`, then committed/pushed and tagged `v0.1.0-phase1`.
- **Phase 2 tech debt:** netting vs hedging deal/partial-close normalization and position aggregation parity in `TradeLifecycle` (Phase 1 conservative) — validate in demo and finalize in Phase 2.
- MT5 minimum build: TBD (record after compile verification).
- SimpleJson is minimal (known/tagged keys only) — see limitations doc.

## [0.0.1] - Prior state
- Initial prototype modules and `MoneyManager.mq5`/`MoneyManager.ex5` present before Phase 1 restructure.
