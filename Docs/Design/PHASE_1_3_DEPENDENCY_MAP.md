# Phase 1.3 — Dependency Map (Decisions & Implementation)

**Project:** `D:\Amoozesh\programing\money managment`  
**Date:** 2026-11-18  
**Basis:** `PHASE_1_3_SOURCE_VERIFICATION.md`, `PHASE_1_3_DECISION_REGISTER.md`, Phase 1.2 design. **Design/audit only — not approved, no implementation authorized.**

---

## 1. Decision Dependency Graph (logical)

### 1.1 Foundational (must resolve early)
| Decision(s) | Depends on | Rationale | Can postpone until after core persistence impl? |
|---|---|---|---|
| **U-01** (persistence schema versioning) | None (policy), but constrains all persisted additions | Determines migration mechanism and coordination with `MM_CONTRACT_VERSION` (`Contracts.mqh:8`, `StateStore.mqh:261-276`). | **No** — required before schema/migration design freeze. |
| **U-11** (identity binding Login+Server+Mode+Profile) | U-01 | State key/path/layout and load/apply gates depend on identity model (`StateStore.mqh:105-117`). | **No** — core to safe restore/write scoping. |
| **U-17** (fail-safe on disagreement, no silent rebaseline) | U-11, U-10, U-16 | Defines behavior for all mismatch/integrity/cashflow/HWM cases (S-06,S-07). | **No** — safety principle for restore/write flows. |
| **U-08** (single trading-day time service + configurable boundaries) | UR-06 | Eliminates split authority (`MoneyManager.mq5:303-311`, `StateStore.mqh:185-189,296-299`) and enables `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus`. | **No** — prerequisite for correct daily/HWM/capture semantics. |
| **U-13/U-14** (epsilons/precision, explicit DISABLED limits) | UR-04 (values) | Cross-cutting comparison/config semantics. | **Partially** — policy/representation should be fixed before enforcement math; exact epsilon values can be tuned with approval but must exist before freeze. |

### 1.2 Financial model decisions (must resolve before calculation/guard unification)
| Decision(s) | Depends on | Rationale | Postpone after core persistence? |
|---|---|---|---|
| **U-02/U-03** (Static/Trailing, separate Daily/Total balance-equity refs) | UR-01 (preset/mode mapping) | Core DD model and formula selection (`Protection.mqh`, `PropFirm.mqh`). | **No** for formula/contract definition; specific preset mappings (UR-01) must be confirmed before prop-accurate enforcement. |
| **U-04** (daily enforcement policy + mandatory denominator coupling) | U-03, U-08, UR-03, UR-13, §3.4 | Defines daily numerator/denominator and baseline capture requirements. | **No** for enforcement contract. |
| **UR-13** (`RealizedRiskRef` for REALIZED_ONLY) | U-04, UR-01 | Required for coupled denominator in REALIZED_ONLY. | **No** if REALIZED_ONLY supported at launch; else can defer policy only if feature disabled explicitly. |
| **UR-03** (`WORST_OF` composition/selector) | U-04, UR-04, UR-13 | Component evaluation and reporting. | **Yes, safely deferrable** if `WORST_OF` explicitly disabled/not supported until later (recommended default). |
| **UR-02** (`ProfitRef`) | U-05,U-06,U-03 | Profit percent denominator. | **No** for consistent reporting/targets; value choice needed at freeze. |

### 1.3 Accounting/lifecycle decisions
| Decision(s) | Depends on | Rationale | Postpone after core persistence? |
|---|---|---|---|
| **UR-11** (lifecycle key, hedging/netting/INOUT decomposition, dedupe/reconciliation) | A (MT5/runtime evidence), TD-02, U-05 | Foundation for lifecycle PnL, streaks, valid-day attribution. `TradeLifecycle.mqh` and EA currently per-deal without dedupe. | **No** for correct accounting design; implementation may be phased but semantics must be chosen and evidenced before claiming correctness. |
| **U-05** (net realized PnL aggregation, costs, dedupe) | UR-11, UR-12, U-01 | Unique-deal aggregation and fee/cashflow handling. | **No** for contract; full parity may be phased with explicit limitations. |
| **U-06** (profit target/consistency from realized outcomes) | U-05,U-07,U-09,UR-01,UR-14 | Depends on lifecycle outcomes and day attribution. | **No** for definition; prop-specific mappings per UR-01. |
| **U-07** (streaks by final lifecycle outcome, eps/breakeven/reset) | UR-11, UR-04, U-08, U-15 | Outcome unit and persistence/clear rules. | **No** for definition. |
| **UR-05/UR-14** (valid trading day, multi-day attribution) | U-09, UR-11, UR-01 | Min-trading-days/consistency semantics. | **No** for prop rule correctness; can be profile-configurable but default must be chosen. |

### 1.4 Day/baseline/HWM/cashflow/recovery decisions
| Decision(s) | Depends on | Rationale | Postpone after core persistence? |
|---|---|---|---|
| **U-09** (persisted `tradingDayId`, once-per-id count) | U-08, UR-05, UR-14 | Idempotent day counting. | **No** (core persistence/time behavior). |
| **§3.4 baseline capture (U-08 related)** | U-08, UR-06, U-17 | `ScheduledBoundary/ActualCaptureTime/BaselineCaptureStatus`, delayed/offline handling. | **No**. |
| **U-16 + §3.3** (strict durable HWM, save-on-new-high, block on dirty/unpersisted) | U-11, U-17, UR-08, UR-09, U-01 | Durability protocol and restore semantics. | **No** for safety-critical HWM behavior. |
| **UR-08** (upward HWM catch-up policy) | U-16, U-17 | Gap handling after verification. | **No** (affects trailing DD correctness). |
| **U-10** (cashflow detect/record, no auto-weaken) | UR-04, U-17 | Detection thresholds and review gating. | **No** for safety policy; classification workflow detail can be staged (UR-07) but default lock behavior required. |
| **UR-07** (cashflow resolution outcomes/matrix) | U-10, U-17, UR-12, UR-09 | Manual-confirmed actions and audit. | **Partially** — unresolved deltas must default to review/lock immediately; full resolution UX/matrix can follow core. |
| **UR-12** (non-deal fees/credits/adjustments) | U-10, UR-07 | Attribution vs cashflow/integrity. | **Partially** — default exclude-from-trading-PnL + review is required; advanced classification can be deferred. |
| **U-15** (restriction clearing/recovery scope) | U-08,U-09, UR-09, U-16 | Daily vs total lock lifecycle. | **No** for rule definition. |
| **UR-09** (total recovery/manual-auth workflow, allowed actions while blocked) | U-15, U-16, U-17, §3.7 | Operational recovery and prop non-recoverable cases. | **No** for total-breach semantics; detailed UX steps can follow but policy must be defined. |
| **U-12/UR-10** (migration/artifacts retention) | U-01 | Recovery/forensics durability. | **No** for migration safety design; retention tuning (counts/size) can be finalized, but retention mechanism required. |

### 1.5 Governance/config
| Decision(s) | Depends on | Rationale | Postpone after core persistence? |
|---|---|---|---|
| **UR-01** (preset/mode mappings) | U-02..U-04,U-06,U-08,UR-02,UR-03,UR-05,UR-06,UR-13, §3.7 | Firm/profile-specific authoritative values. | **Partially** — engine must be configurable; specific firm mappings require user/contract confirmation (can ship as unverified templates with explicit confirmation). |
| **§3.7 prop profile governance** | U-11, UR-01, U-12 | Versioned/audited rule source, effective date, overrides. | **No** as governance model for prop enforcement; full UI/tooling can be staged. |

---

## 2. Dependency Matrix (compact)

| Item | Must be resolved before | Blocked by / needs |
|---|---|---|
| U-01 | schema v2, migration, all new persisted fields | user decision |
| U-11 | safe load/save/restore scoping | U-01 |
| U-17 | restore/fail-safe implementation behavior | U-10,U-11,U-16 |
| U-08, UR-06 | day rollover, baseline capture, `tradingDayId` | user policy/DST/tolerance |
| U-02,U-03,U-04 | DD calc unification, guards/risk parity | UR-01 mappings, UR-03, UR-13 |
| UR-11 | lifecycle aggregation, U-05,U-06,U-07, UR-05,UR-14 | runtime hedging/netting evidence (TD-02), MT5 semantics |
| U-05,U-06,U-07 | realized metrics, streaks, prop progress | UR-11,UR-12,U-09,UR-04 |
| U-09, UR-05, UR-14 | min-trading-days/consistency attribution | U-08, UR-11, UR-01 |
| U-16, §3.3, UR-08 | durable HWM, restart safety | U-11,U-17, platform write guarantees |
| U-10, UR-07, UR-12 | cashflow integrity handling | UR-04 thresholds, user workflow |
| U-15, UR-09 | lockout lifecycle and recovery | U-08,U-16,UR-01 (prop non-recoverable) |
| U-12, UR-10 | migration/recovery artifacts | U-01, storage policy |
| U-13, UR-04, U-14 | enforcement comparisons/config validity | numeric/user policy |

---

## 3. Recommended Resolution Order (safe path to freeze)

1. **Policy/contract decisions (user approval):** U-01, U-11, U-17, U-08+UR-06, U-02,U-03,U-04, UR-02, UR-13, UR-04, U-13,U-14, U-15, U-16+UR-08+UR-09, U-09+UR-05+UR-14, U-10+UR-07+UR-12, U-05,U-06,U-07+UR-11, UR-01 (mappings/governance), UR-03, UR-10.
2. **Evidence tasks (before freeze/claiming correctness):** hedging vs netting deal/lifecycle parity (TD-02), crash/power-loss HWM durability behavior on target platform, restart + boundary capture scenarios, history completeness/reconciliation feasibility (UR-11/§3.6).
3. **Design freeze artifacts:** update Phase 1.2/Phase 1.3 docs to reflect approved choices, freeze formulas/schema/time/identity/durability contracts, then authorize implementation.

---

## 4. What Can Be Safely Postponed (after core persistence implementation, if explicitly bounded)

| Item | Conditions for safe deferral |
|---|---|
| **UR-03 `WORST_OF`** | Feature disabled by default/config; only approved single-policy modes enabled and tested. |
| **UR-07 full resolution matrix UX** | Default remains `requiresManualReview` + block risk-increasing actions for unresolved cashflow; no auto-weakening paths exist. |
| **UR-12 advanced fee/credit classification** | Non-deal balance ops excluded from trading realized PnL and routed to review/integrity handling. |
| **UR-01 verified firm presets** | Shipped as editable templates marked unverified (`TEMPLATE`) requiring explicit confirmation; no claims of firm accuracy. |
| **UR-10 retention tuning** | Minimum safe retention (pre-migration original + bounded last-known-good set + log) implemented; exact counts/size adjustable later. |
| **Rich governance UI/audit tooling** | Governance fields persisted/audited in data model; manual/admin path acceptable initially. |

**Not safely postponable:** U-01,U-02,U-03,U-04,U-08,U-09,U-10,U-11,U-15,U-16,U-17, baseline capture status semantics, HWM durability/blocking, deal-id dedupe/idempotency principles, and restore-before-init safety — these are correctness/safety-critical given D1–D10/R1–R9.

---

## 5. Architecture Readiness for Contract Freeze

**Not ready.** Core decisions unresolved (all U/UR pending approval), source conflicts unremediated in design-approved form, and runtime evidence gaps remain (UR-11 hedging/netting, HWM crash durability, history completeness). Proceed to freeze only after §3 order steps 1–2 and explicit user approval.
