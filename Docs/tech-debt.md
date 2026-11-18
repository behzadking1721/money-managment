# Technical Debt & Follow-ups

Tracked items remaining after Phase 7 code-complete (v1.0.0, compile 0/0). Prioritize by risk to capital protection and correctness.

## High Priority
- **Netting vs hedging parity (full validation/finalization)**
  - Lifecycle normalization and statistics aggregation handle position-id/symbol fallbacks and partial/in-out cases, but end-to-end parity must be validated on real **hedging and netting** accounts (open/partial/close/reverse, multi-position symbols, ticket vs position id semantics).
  - Verify risk aggregation, open-position tracking, and in-trade controls behave identically where expected across account margin modes.
- **Strategy Tester coverage**
  - No automated Strategy Tester suite included. Add reproducible tester scenarios for risk/DD caps, guards, execution outcomes, and lifecycle/stats accounting (where UI-independent) to complement demo/manual checks.
- **Full DD integration & accounting depth**
  - Weekly/monthly loss tracking and enforcement are present in config/guards but require authoritative, fully validated accounting across resets/sessions.
  - Prop-firm consistency/profit-target/min-trading-days enforcement is partially implemented; validate against specific firm rules/presets and edge cases.
  - Ensure daily reset keys/day-start baselines align with selected server/local/NY reset policy in all environments (time fallback cases).

## Medium Priority
- **Live news provider integration**
  - `NewsManager` supports staleness/source and manual/cache behavior; live fetch (e.g. ForexFactory/WebRequest) and richer calendar parsing/impact-to-currency mapping need full provider-backed integration and resilience testing.
  - Validate blackout windows, offline-block policy, and source labeling under real connectivity conditions.
- **Partial-fill remainder handling**
  - Partial-fill/partial-close events are logged and aggregated; broker/order-type-specific remainder behavior (keep vs cancel remainder) remains policy-dependent and should be validated per symbol/broker.
- **Open-risk estimation gaps**
  - `CalcOpenRiskMoney` prefers tracked SL/risk and live-position fallback; positions without SL or unmanaged/manual positions cannot be fully quantified. Consider explicit handling/policy (warn/block/cap) per mode.
- **Execution policy completeness**
  - Continue validating retcode coverage across brokers (retryable/terminal/unknown) and any filling/expiration requirements per symbol.
- **State/profile/template persistence completeness**
  - Core state/profile persistence exists; verify full persistence/restore of all UI preferences, templates, and per-symbol settings across restarts and upgrades (schema migration paths).

## Low Priority / Polish
- **UI/UX refinements**
  - ATR snap, RR-lock handles, visual vs virtual SL/TP modes, and additional drawer controls/tabs as specified in the frozen plan can be further refined.
  - Continued bilingual copy/tooltip audit for consistency and encoding across terminals.
- **Observability**
  - Expand structured log coverage/levels as needed for field diagnostics (while respecting file size/rotation).
- **Phase 1 evidence & tagging**
  - Complete and record real execution evidence in `Docs/phase1-test-results.md`; tag `v0.1.0-phase1` only when acceptance criteria and evidence are satisfied and pushed (per project process).

## Notes
- `MoneyManager.ex5` and local artifacts (`money managment.zip`, `CORE ENGINE.txt`, `.continue/`) are environment-specific; keep them out of commits unless explicitly required.
- Re-run compile (0/0) and relevant scripts/manual checks after any debt remediation.
