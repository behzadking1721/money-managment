# Getting Started

## Prerequisites
- **MetaTrader 5** (desktop) with MetaEditor.
- A trading account (demo recommended first): Personal / Prop-firm / Crypto as applicable.
- Permission to run EAs and automated trading on the target symbol/chart.

## Install & Build
1. Place the project in your MT5 data folder or a mapped path so MetaEditor can see it:
   - `MoneyManager.mq5` (EA entry) and the `Include/`, `Tests/`, `Docs/` folders from this repo.
   - Typical layout: `MQL5/Experts/MoneyManager.mq5` and `MQL5/Include/...` (or compile from the repo path if configured).
2. Open **MetaEditor**, load `MoneyManager.mq5`, and press **F7 (Compile)**.
   - Target: **0 errors, 0 warnings**. A compiled `MoneyManager.ex5` is produced.
3. In **MetaTrader 5**, enable **Algo Trading** (toolbar) and ensure the EA is allowed in *Tools → Options → Expert Advisors*.

## Attach to a Chart
1. Open a chart for the symbol you want to trade.
2. Drag `MoneyManager` onto the chart (or double-click it in Navigator).
3. In EA properties:
   - **Common**: allow algo trading, DLL/WebRequest only if/when required by your setup.
   - **Inputs**: configure account/risk/prop/news/session/UI options (see below).
4. Confirm the panel appears on the chart. Check Experts/Journal for initialization and log messages.

## Important Inputs
> Exact names may vary slightly; refer to the Inputs tab for authoritative labels.

### Account & Risk
- **Account Mode**: `Personal` / `Prop` / `Crypto` (drives defaults, guards, stats context).
- **Sizing Mode**: Auto risk % or Manual lot.
- **Risk % / Manual Lot**, **Min/Max Risk %**.
- **Daily/Weekly/Monthly Loss %**, **Daily Profit % (lock/target)**, **Max Drawdown %**.
- **Max Trades/Day**, **Max Consecutive Losses**, **Cooldown (minutes)**.
- **Slippage (points)**.

### Trailing / Break-even / Exits
- **BE mode/points**, **Trailing mode/value**, **Max minutes in trade** (0 = disabled).

### Prop Firm
- **Enable Prop Firm**, **Preset** (e.g. FTMO/MFF/FundedNext/The5ers), **Prop mode** (challenge/funded). Rules integrate with DD/guard logic.

### News / Session / Spread
- **News enabled/blackout/offline-block**, **minutes before/after**.
- **Session filter**, **Max/Warn spread (points)**.

### UI
- **Language FA** (EN/FA toggle also available in panel), **Magic number**.

> Active profile settings (Personal/Prop/Crypto) may override/effective-combine with inputs for limits/risk/news/spread. Use the Stats/Main UI profile controls to switch/export/import.

## Panel & Workflow
### Drag & Plan (new trade)
1. Select **Buy** or **Sell** (button or hotkey) to activate drag mode.
2. Drag **Entry/SL/TP** lines on the chart. Preview shows direction, market/pending type, lot, risk %, risk $, R:R, spread, and guard/risk/stop status.
3. Adjust sizing mode/risk as needed. Save/apply a template with **T** (geometry + risk settings).
4. Press **Send/Enter** to preflight and send:
   - Warnings/instability may prompt confirmation.
   - **BLOCK** reasons prevent send and are shown/logged (no silent send).
   - On success the plan deactivates/clears per UI flow.

### In-trade Management
1. Select a position (**P** or UI control) on the current symbol (EA magic filtered where applicable).
2. Drag SL/TP to modify (server-synced), or use **BE**, **Trail**, **Partial (50%)**, **Close** controls.
3. Multi/symbol-wide close actions require explicit confirmation/opt-in.

### Stats & Profiles
- Toggle **Stats** tab (`K`): view KPIs (trades, WR, PF, expectancy, Avg R, Max DD, net, duration) and active profile/mode.
- **CSV** export, **Next/Export/Import** profile (import expects `MQL5/Files/MoneyManager/profile_import.json` by default).

## Hotkeys
- `H` — Hide/show panel
- `D` — Toggle drag mode
- `B` / `S` — Buy / Sell drag
- `R` — Toggle sizing mode (Auto risk% ↔ Manual lot)
- `T` — Save/apply drag template
- `Enter` — Preflight & send current plan
- `Esc` — Cancel/clear drag
- `P` — Select/manage position on chart
- `K` — Toggle Main/Stats tab
- Mouse — Drag Entry/SL/TP (and selected position SL/TP) lines

## Files & Data (`MQL5/Files/MoneyManager/`, FILE_COMMON)
- `state_<login>.json` (+ `.lock`, `.bak`, `.tmp`) — persisted state per account.
- `profiles_<login>.json` — profiles store; profile export/import JSON files.
- `MoneyManager_trades.csv` — exported trade history (when requested).
- `logs/mm_<login>.log` (+ rotated files) — runtime logs.

Back up this folder before upgrades or major configuration changes.

## Safety Notes
- Always validate on **demo** before live/prop use.
- Auto-risk requires a valid SL; guards may block sends (DD, spread, news, session, permissions, prop rules).
- News data may be stale/manual depending on provider/connectivity; offline behavior follows configured policy (warn by default unless blackout/block enabled).
- Review `Docs/tech-debt.md` and `Docs/test-checklist.md` for known limitations and validation steps.
