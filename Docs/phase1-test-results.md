# Phase 1 Test Results

Status: **PENDING — NOT EXECUTED** (template). Phase 1 is **not complete** until build and all tests pass with evidence recorded here and committed/pushed.

## Environment
- MT5 build: _TBD_
- MetaEditor compile: _TBD (0 errors / 0 warnings required — attach log)_
- Account/login (demo): _TBD_
- Account mode tested (hedging/netting): _TBD_
- Symbol(s): _TBD_
- Date (server): _TBD_

## Scripted / Unit-style
| Test | Result | Evidence/Log |
|---|---|---|
| SimpleJson round-trip (escapes, `\`/`"`/`/`, Persian, neg/decimal, bool, defaults, empty) | pending | |
| StateStore serialize/restore (per-symbol, UI, counters) | pending | |
| StateStore version migration/fail-safe (v0/legacy) | pending | |
| StateStore atomic write + single `.bak` behavior | pending | |
| StateStore stale-lock takeover (timeout recovery) | pending | |
| StateStore server-time fallback (`timeFallback`) behavior | pending | |
| Lifecycle request-failure → reject sink | pending | |
| Lifecycle partial-fill event | pending | |
| Lifecycle guard-reject sink/dispatch contract | pending | |
| Lifecycle deal-add open/close/partial (netting & hedging) | pending (manual/live) | |

## Manual Demo Checklist
| Step | Expected | Result | Evidence |
|---|---|---|---|
| Open (market) | `MM_EVENT_OPEN` logged | pending | |
| Modify SL/TP | `MM_EVENT_MODIFY` logged | pending | |
| Partial close | correct event/fields (netting vs hedging noted; if one tested, record other as Phase 2 debt) | pending | |
| Close | `MM_EVENT_CLOSE` with P/L, commission, swap | pending | |
| Restart EA/terminal | state restored (symbol/template/UI/counters, server-time reset) | pending | |
| Multi-chart same account (writer/reader+retry) | shared lock, no duplicate counters/sends | pending | |
| Stale lock recovery | takeover after timeout, warning logged, state consistent | pending | |
| Forced reject (invalid stops) | reject sink reasonCode+context+retcode | pending | |
| State migration (old/missing version) | migrate/load per contract | pending | |
| Future version (> supported) | fail-safe: load fails, `IsOperational()==false`, no overwrite, EA/orchestrator blocks all trading actions | pending | |
| timeFallback (server unavailable) | explicit warning in log/UI; behavior documented | pending | |
| MetaEditor build | 0 errors / 0 warnings (log attached) | pending | |

## Notes / Known Limitations Observed
- SimpleJson: see `Docs/simplejson-limitations.md`.
- **Phase 2 tech debt (netting vs hedging):** deal normalization/partial-close and position aggregation parity are Phase 1-conservative; verify in demo, record tested account mode here, and finalize in Phase 2.
- DoD: **no `v0.1.0-phase1` tag until all required tests pass and evidence is committed/pushed.**
