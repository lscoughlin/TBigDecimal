# TBigDecimal Design

This document describes the design of `TBigDecimal`. It states the
representation, the algorithms, and the reason for each choice.

The map below links each section to its file. Section numbers stay in the
file headings, so existing references to a section number stay valid.

| Section | File |
|---|---|
| 1. Representation | [representation.md](design/representation.md) |
| 2. Memory and compiler strategy (FPC) | [compiler.md](design/compiler.md) |
| 3. Algorithms | [algorithms/](design/algorithms/) |
| 3.1 Addition and subtraction | [addition.md](design/algorithms/addition.md) |
| 3.2 Multiplication | [multiplication.md](design/algorithms/multiplication.md) |
| 3.3 Division | [division.md](design/algorithms/division.md) |
| 3.4 Rounding | [rounding.md](design/algorithms/rounding.md) |
| 3.5 Parsing and printing | [parsing.md](design/algorithms/parsing.md) |
| 3.6 Comparison | [comparison.md](design/algorithms/comparison.md) |
| 4. Context and precision model | [context.md](design/context.md) |
| 5. Mathematical functions | [functions/](design/functions/) |
| 5.1 Working precision and correct rounding | [precision.md](design/functions/precision.md) |
| 5.2 Sqrt and Root | [sqrt.md](design/functions/sqrt.md) |
| 5.3 Exp | [exp.md](design/functions/exp.md) |
| 5.4 Ln | [ln.md](design/functions/ln.md) |
| 5.5 Log10, Log, Pow, Root | [log-pow.md](design/functions/log-pow.md) |
| 5.6 Constants | [constants.md](design/functions/constants.md) |
| 5.7 Financial helpers | [financial.md](design/functions/financial.md) |
| 5.8 Factorials, combinatorics and gamma | [combinatorics.md](design/functions/combinatorics.md) |
| 5.9 Trigonometric functions | [trigonometry.md](design/functions/trigonometry.md) |
| 6. API conventions | [api.md](design/api.md) |
| 7. Unit layout | [units.md](design/units.md) |
| 8. Testing and verification | [testing.md](design/testing.md) |
| 8.1 External reference material | [reference-material.md](design/reference-material.md) |
| 9. Decisions | [decisions.md](design/decisions.md) |
| 10. Future directions | [future.md](design/future.md) |
| 11. Measurements and limits | [measurements.md](design/measurements.md) |
