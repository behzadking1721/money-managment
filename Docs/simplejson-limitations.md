# SimpleJson — Supported Scope & Limitations (Phase 1)

`Include/Core/SimpleJson.mqh` is a **minimal** builder/reader for the known, mostly flat/tagged-key schema used by `StateStore`. It is **not** a general-purpose JSON library.

## Supported (by design)
- Flat object key/value pairs written by `CJsonBuilder`.
- Tagged keys for nested-ish state, e.g. `sym.<SYMBOL>.mode`, `sym.<SYMBOL>.risk`, `ui.x` (used by StateStore).
- Types: string, integer/long, double (fixed digits), boolean (`true`/`false`).
- String escaping on write: `\\`, `\"`, `\n`, `\r`, `\t`; control chars `< 0x20` dropped.
- String unescaping on read: `\\`, `\"`, `\n`, `\r`, `\t`, `\/`.
- Numbers: signed integers; signed decimals and exponent form readable by `StringToDouble` when present.

## Not Supported / Caveats
- **General nesting/arrays as parsed structures:** reader fetches values by exact key lookup; it does not build a DOM or iterate arbitrary arrays/objects.
- **Unicode escapes (`\uXXXX`):** not decoded; MQL5 strings are UTF-16 — Persian/Unicode characters are preserved when written/read as raw UTF content, but JSON `\u` sequences are not interpreted.
- **Duplicate keys:** `FindKey` returns first match; duplicates undefined.
- **Whitespace/format variations:** tolerant in simple cases but not a full tokenizer.
- **Strings containing unescaped quotes/newlines** in source: invalid JSON; builder escapes them.
- **Large/complex schemas:** intended only for StateStore’s known keys; extend deliberately with tests.

## Required Tests (Phase 1)
- Round-trip on real State fields (version, login, mode, counters, ui flags, per-symbol keys).
- Strings with quotes, backslash, slash, and Persian text.
- Negative and decimal numbers.
- Boolean and default/missing-key behavior.

> If schema grows beyond tagged-flat keys, replace with a tested JSON component and bump state `version` with migration.