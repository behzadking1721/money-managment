# Skills Catalog — Money Management (MT5 MQL5)

Project: `D:\Amoozesh\programing\money managment`  
Platform: MetaTrader 5 | Language: MQL5 | EA version: `1.70` | `MM_VERSION`: `1.0.0` | Contract: `1`  
Branch: `phase1-foundation` | Audit baseline commit: `f6b4af8`  
Catalog created: 2026-11-18

## Purpose

Project-specific Agent Skills for safe development, review, testing, and
documentation of the Money Manager EA. Skills are grounded in the audited source
and docs, not generic MQL5 assumptions. Planned or unverified behavior must be
labeled as such.

## Discovery and invocation

- **Location:** `.kilo/skills/<skill-name>/SKILL.md` (project-level).
- **Loading:** Skills are discovered at session start; use `/reload` to pick up
  changes in the same environment.
- **Invocation:** The agent loads a skill when a task clearly matches its
  `description`, or when explicitly requested (e.g. "use the `position-sizing`
  skill" / invoke via the `skill` tool with `name`).
- **Naming rule:** Frontmatter `name` matches the directory name.
- **Note:** `.kilo/.gitignore` currently ignores `.kilo/*` except `.kilo/plans/`;
  skill files are therefore ignored by Git unless ignore rules are updated. No
  ignore rules were modified by this task.

## Skills

| Skill | Path | Primary responsibility | Activation (use when) | Key dependencies / references |
|---|---|---|---|---|
| `mql5-development` | `.kilo/skills/mql5-development/SKILL.md` | MQL5 syntax/style, MT5 API usage, includes, error handling, trade ops, type/resource safety, project conventions | Editing `.mq5/.mqh`, fixing compile/API issues, implementing trading logic | `MoneyManager.mq5`, `Include/Core/*`, `Docs/contracts.md`, `Docs/architecture.md` |
| `mql5-architecture` | `.kilo/skills/mql5-architecture/SKILL.md` | Module boundaries, dependency direction, lifecycle/orchestration, frozen interfaces, Core/UI separation, extension patterns | Adding guards/listeners/modules/UI actions, refactor planning, deciding code ownership | `Docs/architecture.md`, `Docs/MODULE_STATUS.md`, `Docs/contracts.md`, `CExecutionRouter`, `CGuardEngine`, `CStateStore` |
| `risk-management` | `.kilo/skills/risk-management/SKILL.md` | Capital preservation: per-trade risk, DD/loss/profit limits, exposure, trade/streak limits, prop restrictions, guard validation; no Martingale | Changing/reviewing risk limits, budgets, guard enforcement, prop risk behavior | `CRiskEngine`, `MM_GuardConfig`, `CProtection`, `CPropFirm`, `risk-management`↔`drawdown-control` |
| `position-sizing` | `.kilo/skills/position-sizing/SKILL.md` | Lot sizing formulas: auto risk %, manual lot, normalization, tick specs, SL distance, commissions, auxiliary methods status | Sizing bugs, lot/cap review, symbol-spec math (FX/JPY/metals/crypto), ATR/Kelly/optimal-f questions | `CRiskEngine`, `CLotSizing` (aux), `CStopsValidator`, `references/formulas.md`, `trading-math-validation` |
| `drawdown-control` | `.kilo/skills/drawdown-control/SKILL.md` | Equity/balance/daily/total DD, high-water marks, remaining DD, reset/restart behavior, guard lockout semantics | DD/protection/prop baseline issues, reset behavior, restart persistence, trailing/static interpretation | `CProtection`, `CPropFirm`, `CStateStore`, `ProtectionGuard`, `PropGuard`, `Docs/TECHNICAL_DEBT.md` |
| `trading-math-validation` | `.kilo/skills/trading-math-validation/SKILL.md` | Independent verification of sizing, P/L, DD, RR, KPIs, rounding, boundaries; evidence-based verdicts | Formula changes, numeric discrepancies, pre-approval of financial math | `references/test-cases.md`, `scripts/Verify-Math.ps1`, `Tests/Phase2/*`, `Tests/IntegrationTest.mq5` |
| `mql5-testing` | `.kilo/skills/mql5-testing/SKILL.md` | Compile/script/manual/regression testing using actual MT5 workflow and repo tests; evidence discipline | Running or adding tests, regression planning, Strategy Tester/demo validation, reporting results | `Tests/**`, `Docs/test-checklist.md`, `Docs/phase1-test-results.md`, `references/test-matrix.md` |
| `git-quality-control` | `.kilo/skills/git-quality-control/SKILL.md` | Safe Git inspection, staging, commits, rollback guidance; protect uncommitted/user work | Status/diff/review, preparing commits, avoiding accidental changes | `.gitignore`, `.kilo/.gitignore`, `CHANGELOG.md`, `Docs/DEVELOPMENT_BASELINE.md` |
| `technical-documentation` | `.kilo/skills/technical-documentation/SKILL.md` | Accurate docs for architecture, modules, interfaces, formulas, config, baseline/status/debt/roadmap | Updating docs, recording status, documenting formulas/debt, correcting drift | `Docs/*`, `README.md`, `CHANGELOG.md`, all skills |

## Supporting files

| Path | Purpose |
|---|---|
| `.kilo/skills/position-sizing/references/formulas.md` | Verified sizing derivations and worked examples (FX/JPY/metals/crypto, caps, floor). |
| `.kilo/skills/trading-math-validation/references/test-cases.md` | Independent financial test-case matrix (sizing, DD, prop, stats, edge cases). |
| `.kilo/skills/trading-math-validation/scripts/Verify-Math.ps1` | Executable PowerShell verifier (29 self-tests; PASS at audit time). |
| `.kilo/skills/mql5-testing/references/test-matrix.md` | Feature-to-test mapping, gaps, and evidence requirements. |

## Responsibility boundaries (avoid duplication)

- **`mql5-development`**: how to write correct MQL5 in this codebase.
- **`mql5-architecture`**: where code belongs and how modules connect.
- **`risk-management`**: what must/must not be allowed for capital protection.
- **`position-sizing`**: how lots are computed from risk and symbol specs.
- **`drawdown-control`**: how DD is defined, measured, gated, and reset.
- **`trading-math-validation`**: independent proof that numeric results are correct.
- **`mql5-testing`**: how to execute and evidence tests in MT5.
- **`git-quality-control`**: how to manage repository changes safely.
- **`technical-documentation`**: how to record verified facts and status.

## Audit summary (project-specific facts embedded in skills)

- **Entry/orchestration:** `MoneyManager.mq5` (root), `OnInit/OnDeinit/OnTick/OnTimer/OnChartEvent/OnTradeTransaction`.
- **Active execution path:** Drag/Panel → `CExecutionRouter::Preflight` (state → risk → stops → guards) → `CExecutionPolicy`/`CTrade`.
- **Active UI:** `CPanelShell`; `UI/Panel.mqh` is legacy/unwired.
- **Authoritative sizing:** `CRiskEngine`; `CLotSizing/StopLoss/TakeProfit/OrderManager` are auxiliary or unwired.
- **Risk/DD formula:** `(slDistance/tickSize)*tickValue + costs`, floor-to-step, DD/aggregate caps, equity peak DD and realized daily loss.
- **Verified gaps:** weekly/monthly loss guard fields inert; cooldown not activated; DD/prop baselines reset on restart and not restored from persisted peaks; live news fetch stub/manual placeholder events; `Tests/Phase4` empty; docs/test-path drift; hedging/netting parity not fully evidenced.
- **Testing:** MQL5 scripts only, MetaEditor/manual execution, CI disabled, no Strategy Tester suite.

## Validation performed (2026-11-18)

| Check | Result |
|---|---|
| Skill directories and `SKILL.md` files (9/9) | PASS |
| YAML frontmatter (`name`, `description`) present in all skills | PASS |
| `name` matches directory for all skills | PASS (`mql5-development`, `mql5-architecture`, `risk-management`, `position-sizing`, `drawdown-control`, `trading-math-validation`, `mql5-testing`, `git-quality-control`, `technical-documentation`) |
| Supporting files exist | PASS (`position-sizing/references/formulas.md`, `trading-math-validation/references/test-cases.md`, `trading-math-validation/scripts/Verify-Math.ps1`, `mql5-testing/references/test-matrix.md`) |
| Internal skill references checked against created files | PASS |
| Application source files modified | NONE (`MoneyManager.mq5`, `Include/**`, `Tests/**/*.mq5`, existing `Docs/*` unchanged) |
| Independent math verifier executed | PASS — `Verify-Math.ps1`: 29 PASS, 0 FAIL |
| MQL5 compile/tests executed by agent | NOT RUN (MetaEditor/MT5 runtime not available in this environment) |

## Maintenance

- **When code changes:** update the owning skill(s), `Docs/MODULE_STATUS.md`,
  `Docs/TECHNICAL_DEBT.md`, and this catalog in the same change set.
- **When a gap is fixed:** move status from PARTIAL/INERT/MISSING to IMPLEMENTED
  only with code reference and test/evidence; remove stale warnings.
- **When formulas change:** update `position-sizing/references/formulas.md`,
  `trading-math-validation` references/script, and run `Verify-Math.ps1`.
- **When tests change:** update `mql5-testing/references/test-matrix.md`,
  `Docs/test-checklist.md`, and evidence docs.
- **When contracts change:** follow `Docs/contracts.md` (version bump + migration),
  update `mql5-architecture` and `technical-documentation`.
- **Review cadence:** re-audit skills against source before major releases or
  after risk/guard/execution/state changes.
- **Keep skills focused:** add detail to `references/`; avoid duplicating
  unrelated instructions across skills.

## Known catalog limitations

- Skills reflect the audited snapshot (`f6b4af8`); future code changes can make
  statements stale until maintained.
- `.kilo/skills/` is currently git-ignored by `.kilo/.gitignore`; committing these
  skills requires an intentional ignore-rule change (not performed).
- MQL5 runtime behavior, broker-specific results, and MetaEditor compile status
  were not executed by this agent; evidence-dependent claims remain unverified.
