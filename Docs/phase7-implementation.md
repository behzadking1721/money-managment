# Phase 7 (Hardening) — Implementation Notes

## Delivered
- **`Include/Core/Logger.mqh`**: `CMMLogger`/`g_mmLog` file logger in `MQL5/Files/MoneyManager/logs/` (`FILE_COMMON`), rotation by size and bounded file count, with `Print` mirroring for EA/guard/execution/trade/news/state events.
- **EA wiring (`MoneyManager.mq5`, v1.70)**: logger initialization and lifecycle logging; real aggregate open risk fed into `MM_RiskContext.openRiskMoney` via `CStatistics::CalcOpenRiskMoney(InpMagic,"")`; risk/DD/day-start context integrated from `CProtection`/`CStateStore` baselines and peaks plus active profile limits; prop-firm remaining/used Daily DD and Max DD wired from `CPropFirm` helpers (fallback to protection/profile limits); guard config populated with effective profile/input limits, session-allowed state, and news state (`HasData/IsStale/SourceTag` + blackout), applied via `CGuardEngine::ApplyNewsState`; trade-deal close recording updates protection/profit counters and logs; day-reset/state sync/save hooks added.
- **`Include/Guards/GuardEngine.mqh`**: `ApplyNewsState(...)` helper to apply news availability/staleness/blackout flags to guard config.
- **`Include/PropFirm/PropFirm.mqh`**: rule/baseline sync and helpers for daily-loss ref, max-DD ref, used %, and remaining Daily/Max DD money (equity/balance reference aware).
- **`Include/Protection/Protection.mqh` / `Include/State/StateStore.mqh`**: day-start balance/equity and peak balance/equity tracking, DD%/remaining DD money helpers, persisted baselines/peaks with migration-safe load/save and logging.
- **`Include/News/NewsManager.mqh` / `Include/UI/NewsBanner.mqh`**: source/staleness tracking (`live/cache/manual/stale`), `HasData/IsStale/SourceTag/LastUpdate` API, stale-age config; banner displays source and bilingual-safe labels.
- **`Include/Statistics/Statistics.mqh`**: partial-close aggregation into tracked open trades (realized P/L/commission/swap/volume, remaining risk/volume sync, finalize on full close or in/out), `CalcOpenRiskMoney` for tracked/live positions, CSV export logging.
- **`Include/Trade/TradeLifecycle.mqh`**: hedging/netting-aware open/close/partial/in-out normalization (position id/deal entry handling, partial vs full close detection), request/order/position event logging, and guard/exec reject logging.
- **`Include/Core/ExecutionPolicy.mqh` / `Include/Core/ExecutionRouter.mqh`**: unknown/unclassified retcode handling and logging, partial-fill logging/policy note, retry/terminal/route reject logging, preflight guards/operational checks retained.
- **`Include/Core/StopsValidator.mqh`**: symbol property/price gap guards and validation logging (point/tick value/size/volume bounds, margin/price checks).
- **UI/UX (`Include/UI/UiStrings.mqh`, `Include/UI/PanelShell.mqh`, `Include/UI/DragTool.mqh`, `Include/UI/PreviewOverlay.mqh`)**: expanded bilingual EN/FA labels and tooltips, button/label tooltips in panel shell, drag-line tooltips, and preview/status text consistency.
- **`Tests/IntegrationTest.mq5`**: script-based integration smoke checks for logger/news staleness, protection DD/remaining calculations, prop-firm DD helpers, execution retcode classification (incl. unknown), stops validation on live symbol, statistics event aggregation/open-risk fallback, and guard behavior (news stale warn/block, session block).

## Edge cases / behavior notes
- Retcodes: known retryable/terminal/success sets preserved; unknown codes classified as `RETCODE_UNKNOWN` and logged.
- Partial fills/closes: request partial-fill and deal partial-close/in-out events are logged and aggregated in statistics; execution remainder handling remains policy/broker dependent (`keep` default semantics, cancel-remainder noted for caller).
- Symbol/magic/suffix: operations use provided/broker symbol names and configured magic where applicable; symbol property gaps block validation with reason/logging.
- Netting/hedging: lifecycle and statistics use position identifiers/symbol fallbacks and live position state to distinguish partial vs full close; parity should be validated per account mode in demo.
- News offline/stale: warns by default, blocks only when offline-block/blackout policy requires it; banner/source reflects availability/staleness.

## Known limitations / follow-up
- Weekly/monthly loss accounting, consistency/profit-target enforcement depth, and provider-backed live news fetch remain partial/integration follow-ups.
- Aggregate open-risk estimation prefers tracked SL/risk and live-position fallback; positions without SL cannot be fully risk-quantified.
- `MoneyManager.ex5` and unrelated local artifacts are not part of Phase 7 commits.

## Verification
- MetaEditor F7 compile/test execution not run by agent (environment constraint). **Pending:** user MetaEditor compile (target 0 errors/0 warnings) and demo/script verification; record results/evidence as appropriate before phase completion/tagging.
