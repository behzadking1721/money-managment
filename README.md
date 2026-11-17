# Money Manager Expert Advisor (MT5)

Modular MQL5 money-management EA for **Personal / Prop / Crypto** accounts with drag-and-drop trade placement (market & pending), live risk/lot/RR preview, unified pre-send guards, in-trade management, and lifecycle-based statistics.

> Status: **Phase 1 (foundation)** in progress — contracts, file-based StateStore, TradeLifecycle. See `.kilo/plans/1794908270901-mt5-money-management-dragdrop-plan.md` and `CHANGELOG.md`.

## Repository Structure

- `Experts/` — EA entry points (`MoneyManager.mq5` / phase entry scripts as added)
- `Include/` — modular libraries
  - `Core/` (contracts, risk, stops, execution), `Trade/` (order/position/lifecycle), `Guards/`, `State/`, `News/`, `Session/`, `Profiles/`, `Stats/`, `UI/`
- `Tests/` — unit-style scripts/helpers and manual checklists per phase
- `Docs/` — contracts, architecture, phase test results
- `.kilo/plans/` — frozen implementation plan

## Build

1. Open MetaEditor (MetaTrader 5, build ≥ current stable; minimum tested build recorded in `CHANGELOG`/release notes).
2. Place or symlink the repo into your terminal data folder (e.g. `MQL5/Experts` & `MQL5/Include`), or compile from a mapped path.
3. Compile `Experts/MoneyManager.mq5` (or root `MoneyManager.mq5` during transition). Target: **0 errors, 0 warnings**.

## Run

1. Attach the EA to a chart in MT5.
2. Select **Account Mode** (Personal / Prop / Crypto) and active profile/template.
3. Use drag-and-drop lines for Entry/SL/TP with live preview; confirm to send (guards must pass).
4. State persists per account in `MQL5/Files/MoneyManager/` (see `Docs/contracts.md`).

## Tests

- Build and test locally in MetaEditor/MetaTrader 5 (target: **0 errors, 0 warnings**).
- **Per-phase:** run unit-style scripts in `Tests/` and the manual demo checklist in `Docs/`; record evidence (logs/screens/Strategy Tester outputs when applicable) in `Docs/phase<N>-test-results.md`.
- **Phase 1:** State serialize/restore (incl. migration/fail-safe), lifecycle event mapping & reject sink, lock/restart behavior — see `Tests/Phase1/` and `Docs/phase1-test-results.md`.
- No phase is complete until acceptance tests pass and results are committed.

## Configuration & Safety

- Defaults favor safety (prop DD caps, news offline = warn unless blackout configured, multi-position actions opt-in).
- Back up `MQL5/Files/MoneyManager/` before updates. Profiles/templates/settings support Import/Export (per plan).
- Source delivery and IP/ownership are defined in the project contract (outside this repository).

## License / Ownership

To be specified in the project/contract agreement.
