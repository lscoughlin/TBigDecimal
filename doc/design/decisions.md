## 9. Decisions

1. With no thread-local default context, `*` and `/` round to 34
   significant digits, half-even. This differs from Java, where the
   operators are exact. The fallback keeps naive code safe: a product
   cannot grow without bound and a quotient cannot raise. The global
   `NoContextFallback128` restores exact operators when set to `False`.
   The thread-local default context ([section 4.1](context.md)) lets a program choose
   another rounding without changing the operator syntax.
2. `+`, `-` and `*` round under a default context, as in Python `decimal`.
   Java has no such feature, so no Java behavior conflicts.
3. Constants are cached in one shared cache that a lock guards ([section 5.6](functions/constants.md)).
