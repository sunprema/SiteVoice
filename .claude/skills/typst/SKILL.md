---
name: typst
description: "Use this skill working with Typst template, pdf generation, imprintor library."
---

## Typst PDF Patterns (Imprintor)

- You have to be very careful when working with Elixir/JSON data in typst template. There are issues with the types like nil, true/false, string to number conversions.
- Boolean fields from Elixir/JSON arrive in Typst as **strings** `"true"`/`"false"`, not booleans
- Always coerce at the top of any function that accepts a boolean named param:
  ```typst
  let approximate = if type(approximate) == str { approximate == "true" } else { approximate }
  ```
- Named params with boolean defaults (e.g. `approximate: false`) will still error if the caller passes a string — coercion must be inside the function body
- **Numeric coercion**: See `feedback_typst_numeric_coercion.md` — floats arrive as strings, nil as `"nil"` string. Always define `to-num` helper AT THE TOP of every template (before all functions). Never call `calc.round`/arithmetic on raw Elixir values without `to-num`. Always nil-guard before division.
- **`nil-string bug **: Never check `if v == none` before passing to `to-num` — Elixir `nil` arrives as the string `"nil"`, not Typst `none`. The `== none` guard misses it, then `calc.round(to-num("nil"))` crashes with "expected integer, float, or decimal, found none". **Rule**: always call `to-num(v)` first, bind the result, then check the result for `none`. Pattern: `let n = to-num(v); if n == none { "—" } else { calc.round(n, ...) }`

## Imprintor data injection — use elixir_data, not sys.inputs

Imprintor injects the Elixir data map as a global Typst variable named elixir_data, defined directly in the Typst library scope via the Rust NIF:
library.global.scope_mut().define("elixir_data", typst_value);

In your .typ template, access data as:
#elixir_data.project
#elixir_data.date
#for item in elixir_data.labor [ ... ]

Not sys.inputs.elixir_data.X (sys.inputs is always empty — Imprintor never writes to it) and not
sys.inputs.X (the keys are not flattened there either).

## Type mapping — Elixir values convert to native Typst types:

- String → str
- Integer → int
- Float → float
- List → array (so .len() and for work directly)
- Map → dict (so .at("key", default: "—") works)
- nil atom → none
