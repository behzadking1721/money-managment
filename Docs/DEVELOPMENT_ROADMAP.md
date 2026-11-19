# Development Roadmap

## Planning Principles
- **Improve, do not rebuild:** preserve existing working architecture/modules and extend them incrementally.
- **Preserve core capabilities:** BUY/SELL, Market and Pending (Limit/Stop) orders, interactive Entry/SL/TP chart lines, automatic and manual lot sizing, optional Multi-TP (max five targets initially), Break Even and Trailing (off by default), Personal Account default mode, optional configurable Prop Firm mode, Risk Guardian, News and Trading Sessions, Statistics/Reporting.
- **Safety defaults:** automatic trading and position-management behaviors remain optional and disabled by default unless explicitly configured.
- **Single-account assumption:** design and validation target one connected trading account.
- **No assumed rewrites:** if equivalent functionality exists, reuse/refine it; new code only where gaps are verified.

## Phase 1 — UI/UX Modernization

- **Objective:** Modernize and stabilize the existing chart UI (panel, drag planning, preview, position tools) for clarity, responsiveness, and safer operator workflows without changing trading logic semantics.
- **Existing modules to reuse:** `Include/UI/PanelShell.mqh`, `DragTool.mqh`, `PreviewOverlay.mqh`, `PositionDragTool.mqh`, `NewsBanner.mqh`, `SessionBadge.mqh`, `StatusLog.mqh`, `UiStrings.mqh`, `UI/Panel.mqh` (reference/legacy only if needed), `MoneyManager.mq5` UI wiring.
- **Expected changes:**
  - Improve layout/state handling (mini/drawer, tabs, visibility), control grouping, and feedback consistency.
  - Refine drag interactions (handles, snapping cues, instability/invalid-state messaging) and preview readability.
  - Expand/normalize bilingual EN/FA labels and tooltips; audit encoding/rendering.
  - Preserve existing hotkeys/actions where possible; document any UI-only behavior changes.
- **Dependencies:** Stable contracts for plan/risk/guard preview data; no backend behavior changes required.
- **Acceptance criteria:**
  - User can activate/deactivate planning, switch modes, and read lot/risk/RR/guard status clearly in EN/FA.
  - Existing send/clear/position actions remain reachable and functionally unchanged.
  - No regression in chart object lifecycle (create/update/destroy/redraw).
- **Relevant tests:** `Docs/test-checklist.md` (UI/manual), targeted manual chart-event verification; `Tests/IntegrationTest.mq5` only where UI-independent behavior overlaps.

## Phase 2 — Trade Planner Improvements

- **Objective:** Enhance planning accuracy and usability for Entry/SL/TP configuration and risk inputs while reusing current drag/plan contracts.
- **Existing modules to reuse:** `UI/DragTool.mqh`, `UI/PreviewOverlay.mqh`, `Core/Contracts.mqh` (`MM_TradePlan`), `Core/RiskEngine.mqh`, `Core/StopLoss.mqh`, `Core/TakeProfit.mqh`, `Core/StopsValidator.mqh`.
- **Expected changes:**
  - Improve plan editing ergonomics (precision, step adjustments, template save/apply behavior, reset/cancel flows).
  - Add/finish planner affordances where gaps are verified (e.g. clearer pending vs market inference, RR visibility/lock UX hooks if absent).
  - Ensure SL/TP methods/utilities are consistently surfaced or intentionally left manual with clear behavior.
- **Dependencies:** Phase 1 UI baseline (recommended); validated symbol/tick/point data handling.
- **Acceptance criteria:**
  - Planner produces valid `MM_TradePlan` values for supported scenarios; preview updates reflect edits immediately.
  - Invalid geometry/SL states are clearly indicated and blocked before send.
  - Existing planner functionality is preserved.
- **Relevant tests:** `Tests/Phase2Test.mq5` (if applicable), manual drag/preview scenarios per `Docs/test-checklist.md`.

## Phase 3 — Market and Pending Order Workflow

- **Objective:** Ensure complete, reliable workflows for BUY/SELL Market, Buy/Sell Limit, and Buy/Sell Stop orders (including pending geometry and execution paths).
- **Existing modules to reuse:** `Core/ExecutionRouter.mqh`, `Core/ExecutionPolicy.mqh`, `Core/StopsValidator.mqh`, `Core/OrderManager.mqh`, `UI/DragTool.mqh`, `UI/PanelShell.mqh`, `Utils/Common.mqh` (order type enums).
- **Expected changes:**
  - Verify and, if needed, complete pending order placement/modification paths and UI intent mapping.
  - Clarify/validate handling of Stop-Limit/OCO representations only if required by verified gaps (do not expand scope without need).
  - Improve retcode/reject feedback for order-type-specific failures.
- **Dependencies:** Phases 1–2 for UX/plan correctness; broker symbol/order-type support.
- **Acceptance criteria:**
  - Supported order types can be planned, validated, confirmed, and submitted (or cleanly rejected with reason).
  - Entry/SL/TP geometry rules enforced for market and pending cases.
  - No silent-send behavior; rejects routed through central sink/status.
- **Relevant tests:** `Tests/Phase2Test.mq5`, `Tests/IntegrationTest.mq5` (retcode/stops checks), demo/manual broker validation.

## Phase 4 — Automatic Lot Sizing and Risk Calculations

- **Objective:** Strengthen correctness, transparency, and configurability of auto-risk and manual-lot sizing under all supported account/profile contexts.
- **Existing modules to reuse:** `Core/RiskEngine.mqh`, `Core/LotSizing.mqh`, `Core/StopsValidator.mqh`, `Profiles/Profiles.mqh`, `Protection/Protection.mqh`, `PropFirm/PropFirm.mqh`, `Statistics/Statistics.mqh` (open risk), `UI/PreviewOverlay.mqh`.
- **Expected changes:**
  - Reconcile/clarify sizing method coverage (`CRiskEngine` vs `LotSizing.mqh`) and expose only verified, supported methods in UI/docs.
  - Improve handling/reporting of commission/swap estimates, aggregate/open risk, DD budgets, and min/max/step constraints.
  - Ensure live profit/loss and risk previews reflect current plan and account state accurately.
- **Dependencies:** Accurate context refresh (`RefreshRiskContext`), validated baselines/peaks/DD data.
- **Acceptance criteria:**
  - Auto-risk computes bounded lots consistent with SL distance, basis, caps, and symbol constraints.
  - Manual lot override is respected but still subject to safety/validity checks as designed.
  - Preview and preflight results match for the same plan/context.
- **Relevant tests:** `Tests/Phase2Test.mq5`, `Tests/IntegrationTest.mq5` (open-risk/stats), manual edge-case checks (no SL, min lot, DD-capped).

## Phase 5 — Position Management

- **Objective:** Improve in-trade management controls (BE, trailing, partial/close, time exit, SL/TP modification) with safe defaults and clear confirmations.
- **Existing modules to reuse:** `Core/PositionManager.mqh`, `UI/PositionDragTool.mqh`, `UI/PanelShell.mqh`, `MoneyManager.mq5` tick handlers, `Trade/TradeLifecycle.mqh`, `Alerts/Alerts.mqh`.
- **Expected changes:**
  - Validate and refine BE/trailing/time-exit triggers and parameters; keep features optional/off by default unless configured.
  - Improve position selection, drag-to-modify feedback, and partial/full close workflows (including multi-position symbol cases where applicable).
  - Ensure lifecycle/statistics updates remain consistent after modifications and partial closes.
- **Dependencies:** Phases 3–4 for stable execution/sizing context; verified magic/symbol/position identification behavior.
- **Acceptance criteria:**
  - Position actions execute only on intended selections and respect confirmations/safety checks.
  - BE/trailing/time-exit apply according to configuration without unintended automation.
  - UI/status/log reflect outcomes and rejects accurately.
- **Relevant tests:** Manual position-management scenarios, `Tests/IntegrationTest.mq5` (stats/lifecycle-related checks), demo validation on hedging/netting as applicable.

## Phase 6 — Multi-TP Functionality

- **Objective:** Deliver/complete optional Multi-TP support with safe defaults and clear execution semantics (initial maximum five targets).
- **Existing modules to reuse:** `Core/Contracts.mqh` (`tpPrice[]`, `tpCount`), `Core/TakeProfit.mqh`, `Core/OrderManager.mqh`/`ExecutionRouter.mqh`, `UI/DragTool.mqh`, `UI/PreviewOverlay.mqh`, `UI/PanelShell.mqh`.
- **Expected changes:**
  - Align UI/plan/contracts/constants to support up to five TP targets when enabled; keep Multi-TP disabled by default.
  - Define and implement verified behavior for multi-target execution/management (e.g. split positions/orders or staged exits) consistent with existing architecture and broker constraints.
  - Expose target distribution/levels clearly in planner/preview with validation.
- **Dependencies:** Phases 2–5; broker/order-model constraints (especially netting vs hedging) must be verified before finalizing semantics.
- **Acceptance criteria:**
  - When disabled, behavior matches current single-TP flow.
  - When enabled, up to five TP targets can be configured, previewed, validated, and executed/managed per defined behavior with correct accounting.
  - Rejects/limitations are explicit when broker/account mode cannot support requested configuration.
- **Relevant tests:** New/updated scripted checks for TP planning/execution logic as needed, `Tests/IntegrationTest.mq5` extensions, extensive demo/manual validation.

## Phase 7 — Personal Account Configuration

- **Objective:** Finalize and harden Personal Account mode as the default, user-friendly configuration path with transparent risk/protection settings.
- **Existing modules to reuse:** `Profiles/Profiles.mqh` (Personal defaults), `Protection/Protection.mqh`, `Guards/ProtectionGuard.mqh`, `RiskEngine.mqh`, `UI/PanelShell.mqh`, `State/StateStore.mqh`.
- **Expected changes:**
  - Refine personal-mode defaults, profile fields, and UI exposure for daily/weekly/monthly limits, cooldowns, trade caps, and risk basis/options.
  - Ensure day-start/baseline/peak tracking and reset behavior align with selected policy and are visible/diagnosable.
  - Keep prop-specific constraints inactive unless explicitly enabled.
- **Dependencies:** Phase 4 risk correctness; state/profile persistence reliability.
- **Acceptance criteria:**
  - Personal mode is default and fully operable without prop configuration.
  - Configured personal limits correctly warn/block per guard/risk design and are persisted/restored.
  - No prop-firm rules are enforced implicitly in personal mode.
- **Relevant tests:** Manual configuration/persistence scenarios, `Tests/Phase3Test.mq5` and `Tests/IntegrationTest.mq5` coverage where applicable.

## Phase 8 — Optional Prop Firm Configuration

- **Objective:** Complete optional, user-configurable Prop Firm mode with accurate rule application and clear separation from Personal mode.
- **Existing modules to reuse:** `PropFirm/PropFirm.mqh`, `Guards/PropGuard.mqh`, `Profiles/Profiles.mqh` (Prop profile), `Protection/Protection.mqh`, `RiskEngine.mqh`, `UI/PanelShell.mqh`, `State/StateStore.mqh`.
- **Expected changes:**
  - Validate and extend preset/rule mapping (daily/max DD reference, position limits, weekend/news/trade constraints, consistency/profit-target/min-days where supported).
  - Improve UI/config workflow for enabling prop mode, selecting presets, and overriding parameters safely.
  - Ensure DD remaining/used calculations and enforcement align with configured reference (equity/balance) and live baselines.
- **Dependencies:** Phase 7 account-mode separation; reliable protection/state baselines; verified prop rule semantics.
- **Acceptance criteria:**
  - Prop mode remains optional and explicit; disabling it restores personal/default behavior.
  - Enforced prop rules match configured values and are surfaced in preview/guards/status.
  - Unsupported or unverified firm-specific rules are labeled/handled explicitly (no false guarantees).
- **Relevant tests:** `Tests/Phase3Test.mq5`, `Tests/IntegrationTest.mq5`, targeted demo validation against selected prop presets/rules.

## Phase 9 — Risk Guardian and Account Protection

- **Objective:** Unify and harden all protective controls (loss limits, DD, cooldowns, streak/trade caps, permission/session/spread safeguards) into a predictable Risk Guardian layer.
- **Existing modules to reuse:** `Guards/GuardEngine.mqh`, `ProtectionGuard.mqh`, `PermissionGuard.mqh`, `SessionSpreadGuard.mqh`, `Protection/Protection.mqh`, `State/StateStore.mqh`, `Alerts/Alerts.mqh`, `UI/StatusLog.mqh`.
- **Expected changes:**
  - Close verified gaps in weekly/monthly enforcement, reset timing/policy handling, and cooldown/consecutive-loss logic.
  - Standardize guard priorities/messages/reasons and ensure preview and send decisions are consistent.
  - Improve operator visibility for active protections, breached limits, and blocked actions.
- **Dependencies:** Phases 7–8 (correct limit sources), robust state persistence and time handling.
- **Acceptance criteria:**
  - All enabled protective limits reliably warn/block as specified with clear reasons.
  - No trading action bypasses guard/preflight/state-operational checks.
  - Protection state survives restarts and recovers safely per `StateStore` contract.
- **Relevant tests:** `Tests/Phase3Test.mq5`, `Tests/IntegrationTest.mq5`, manual guard/breach simulations, `Docs/test-checklist.md`.

## Phase 10 — News and Trading Sessions

- **Objective:** Improve reliability and transparency of news/session awareness and their impact on trading permissions.
- **Existing modules to reuse:** `News/NewsManager.mqh`, `Session/SessionManager.mqh`, `Guards/NewsGuard.mqh`, `Guards/SessionSpreadGuard.mqh`, `UI/NewsBanner.mqh`, `UI/SessionBadge.mqh`, `Alerts/Alerts.mqh`, `Profiles/Profiles.mqh`.
- **Expected changes:**
  - Harden staleness/source handling and offline/manual/cache behavior; integrate live provider fetch/parsing only where feasible and verified.
  - Refine blackout window configuration, symbol/currency relevance, and policy (warn vs block) surfaced in UI/guards.
  - Validate session definitions/filter behavior against server time/DST and profile/input settings.
- **Dependencies:** Network/provider constraints for live news (if implemented), accurate time/session utilities.
- **Acceptance criteria:**
  - Session and news states are displayed accurately and consistently influence guards per configuration.
  - Stale/unavailable news data results in explicit, safe behavior (no silent assumptions).
  - Existing default-safe behavior is preserved when live data is unavailable.
- **Relevant tests:** `Tests/IntegrationTest.mq5` (news/session guard smoke checks), manual time-window and connectivity scenarios.

## Phase 11 — Statistics and Reporting

- **Objective:** Improve accuracy, completeness, and usefulness of trade statistics, KPIs, and exports for personal and prop contexts.
- **Existing modules to reuse:** `Statistics/Statistics.mqh`, `Trade/TradeLifecycle.mqh`, `Profiles/Profiles.mqh` (mode context), `UI/PanelShell.mqh` (Stats tab), `Alerts/Alerts.mqh` as needed.
- **Expected changes:**
  - Validate/fix KPI accounting for partial closes, commissions/swaps, duration, and netting/hedging edge cases as verified.
  - Refine open-risk reporting and per-mode/all-mode views; improve CSV schema stability/documentation.
  - Add reporting clarity in UI (filters/labels/totals) without breaking existing export workflows.
- **Dependencies:** Accurate lifecycle events and deal attribution (Phases 3, 5, 6 influence); stable persistence of identifiers where required.
- **Acceptance criteria:**
  - KPIs and exported records reconcile with broker history for validated scenarios.
  - Partial/in-out trades are represented consistently per defined accounting rules.
  - Stats remain available and non-blocking when data is incomplete (with explicit limitations).
- **Relevant tests:** `Tests/IntegrationTest.mq5`, scripted/statistical validation cases, manual reconciliation against demo account history.

## Phase 12 — Testing and Release Preparation

- **Objective:** Establish release confidence through verification, documentation alignment, and packaging/readiness checks without altering intended behavior.
- **Existing modules to reuse:** `Tests/Phase1Test.mq5`, `Phase2Test.mq5`, `Phase3Test.mq5`, `IntegrationTest.mq5`, `Docs/test-checklist.md`, `Docs/phase1-test-results.md`, `.github/workflows/compile.yml`, all baseline/debt/roadmap docs.
- **Expected changes:**
  - Execute/record compile and scripted/manual test evidence (including hedging vs netting where possible) and update evidence docs.
  - Resolve or explicitly defer documented high/medium findings with traceable decisions.
  - Align README/changelog/versioning notes and ensure release artifacts/configs are consistent.
- **Dependencies:** Completion/stabilization of prioritized phases above; access to demo accounts/brokers for validation.
- **Acceptance criteria:**
  - Clean compile (0 errors / 0 warnings target) and documented test outcomes for in-scope scenarios.
  - Critical/High issues addressed or formally accepted with mitigation and follow-up entries.
  - Documentation set (baseline, module status, roadmap, technical debt) reflects shipped behavior and known limitations.
- **Relevant tests:** Full `Tests/*` suite as applicable, `Docs/test-checklist.md`, Strategy Tester scenarios if/when added, CI compile workflow verification.

## Phase 14 — Protection & Prop Accounting Hardening (TD-04)

- **Objective:** Harden protection accounting and prop firm rule enforcement with deterministic test coverage, focusing on weekly/monthly loss tracking, reset policies, and prop accounting correctness.
- **Existing modules to reuse:** `Include/Protection/Protection.mqh`, `Include/PropFirm/PropFirm.mqh`, `Include/Guards/ProtectionGuard.mqh`, `Include/Guards/PropGuard.mqh`.
- **Expected changes:**
  - Fix week key calculation to anchor week 0 to the first Monday of the year (`WeekKeyMonday` in Protection.mqh).
  - Add deterministic tests for weekly/monthly loss calculation, reset behavior, commission/swap/fee inclusion, partial close accounting, DD checks, equity/balance reference, risk-increasing block, profit target, min trading days, consistency.
  - All tests compile clean (0 errors, 0 warnings).
- **Dependencies:** Phases 7–8 (correct limit sources), Protection/PropFirm modules.
- **Acceptance criteria:**
  - Weekly/monthly loss tracking is deterministic across resets.
  - Prop accounting (profit target, min trading days, consistency) is honestly reported as runtime-only/unverified where applicable.
  - Risk-increasing block works correctly when limits are breached; risk-reducing actions are never gated.
- **Relevant tests:** `Tests/Phase14/MinimalProtection_Test.mq5`, `Tests/Phase14/Protection_Prop_Test.mq5`.

## Persistence & Recovery (next phase priority — not an independent roadmap phase)

There is **no independent "Persistence and Recovery Engine" phase** in the roadmap. Persistence/recovery safety gaps are addressed as the next phase priority, mapping to tech-debt items **TD-05** (High: state persistence/migration/gating under restart/upgrade/corruption scenarios) and **TD-17** (High: time-fallback impacts on resets/counters if not fully surfaced/gated).

Implementation approach: build on existing `StateStore`/`Protection`/`TradeLifecycle`/`Statistics` (no rewrite of healthy code). `Include/State/RecoveryEngine.mqh` (`CRecoveryEngine`) orchestrates restart recovery:
- Never auto-resets/re-bases protective baselines when continuity uncertain.
- Blocks new risk-increasing actions until explicit resolution.
- Keeps risk-reducing position management (BE/trail/close) active even in failed/blocked recovery state.
- Preserves original state + `.bak`; no auto overwrite.
- No account identity (login/broker/server) persisted.
- Backward-compatible: prior `StateStore` schema versions remain migratable.

## Cross-Cutting Constraints (All Phases)
- Preserve and verify: BUY/SELL; Market, Pending Limit, Pending Stop; interactive Entry/SL/TP lines; auto/manual lot sizing; live risk/P&L preview; optional Multi-TP (max 5 initially, off by default); BE/Trailing (off by default); Personal default mode; optional configurable Prop Firm mode; Risk Guardian; News/Sessions; Statistics/Reporting.
- Maintain central reject/logging discipline and no-silent-send behavior.
- Any schema/contract evolution must follow versioning/migration rules in `Docs/contracts.md`.
- Label unverified behavior explicitly; do not claim parity or support without evidence.
