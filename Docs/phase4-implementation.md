# Phase 4 (Drag & Drop UI & Live Preview) — Implementation Notes

## Delivered
- **`Include/UI/UiStrings.mqh`**: bilingual EN/FA string helper (`CUiStrings`, `MM_LANG_EN/FA`) for panel/preview/status labels and help.
- **`Include/UI/StatusLog.mqh`**: UI-consumable status log implementing `IRejectSink` (execution + guard BLOCK/WARN) plus info/warn helpers; recent/last-line access.
- **`Include/UI/NewsBanner.mqh`**: chart banner showing next event title/currency/time/countdown, impact color, and source tag (`live/cache/manual/stale`).
- **`Include/UI/SessionBadge.mqh`**: session indicator using `CSessionManager` name/color.
- **`Include/UI/DragTool.mqh`**: draggable `OBJ_HLINE` set (Entry/SL/TP1-3) with `OnChartEvent` drag/change handling, buy/sell toggle & reverse, auto market/pending (limit/stop) detection + mode override, risk%/manual-lot sizing mode, +/- risk step, adjustable TP count, instability warning (spread jump), plan build, and template capture/apply (geometry + risk/mode/slippage per spec).
- **`Include/UI/PreviewOverlay.mqh`**: floating live preview recomputed on update — lot, risk%, risk$, RR, spread, pending/market type, and aggregated Risk/Stops/Guards state with block/warn reasons (guards via `Preview` no sink side-effects). Blocks/warns flagged (incl. instability, no silent send).
- **`Include/UI/PanelShell.mqh`**: Mini/Drawer shell (chart objects) with language toggle, drag controls, send/cancel/clear, risk +/- and template hooks, integrated banner/badge/preview/status. Hotkeys: `H` hide, `D` drag toggle, `B` buy-drag, `S` sell-drag, `Enter` send, `Esc` cancel/deactivate, `R` risk-mode toggle (wired in EA), `T` template save/apply (wired in EA). `TrySend`: instability re-confirm, preflight (risk+stops+guards) → confirm dialog → `ExecutionRouter.Send`, reject reasons surfaced to status/MessageBox.
- **`MoneyManager.mq5`**: Phase 4 orchestration wiring `StateStore/TradeLifecycle/GuardEngine/ExecutionRouter`, drag tool, panel shell, live risk/guard context refresh, and `OnTradeTransaction` dispatch.

## Spec coverage notes
- **Live preview & block visibility:** lot/risk/RR/guard reasons update per tick/drag; blocked state prevents confirm/send and shows reason.
- **Order inference:** auto market vs limit/stop from entry vs bid/ask with manual mode override.
- **Safety:** instability (spread jump) warning + explicit confirm; pre-send guard/risk/stops gate before final confirm.
- **Bilingual:** EN/FA toggle for core UI strings/help/labels (extensible).
- **Templates:** capture/apply geometry + risk/mode/slippage (persist/restore via StateStore to be fully wired in Profiles/State integration).

## Integration/polish pending
- Persist panel position/mini state, per-symbol/template sizing & templates via `CStateStore`/Profiles; richer template list.
- Full snap (ATR period/TF/price), RR-lock handle, multi-TP partial geometry, visual vs virtual SL/TP mode indicator/warning, and spread/price-jump pause logic refinement.
- News source-tag fidelity (`live/cache/manual/stale`) from provider/cache once `INewsProvider` wired; session filter schedule config; prop DD money remaining from Protection/Prop live accounting.
- Drawer tabs (Positions/Settings/Prop/Stats/Log/About) and broker-state sync for drag-modify (Phase 5).

## Tests
- Manual UI walkthrough required (market, buy/sell limit/stop, multi-TP, drag pending across price, instability/no-silent-send, block reasons, hide/mini/lang/hotkeys, restart/template behavior) — compile 0 errors/warnings locally; record evidence per project process.