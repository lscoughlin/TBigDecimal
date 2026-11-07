### 3.5 Parsing and printing

- Parsing reads nine decimal digits at a time into a limb. It handles
  exponent notation (`1.5E-7`). It runs in O(n).
- `ToPlainString` prints each limb with zero padding. It then inserts the
  decimal point. Output is O(n).
- `ToString` follows the Java scientific rule: use plain notation when
  `scale >= 0` and the adjusted exponent is at least −6. Otherwise it uses
  exponent notation. `ToEngineeringString` uses exponents that are multiples
  of three.
- `Create(Double)` has two forms. `FromDoubleExact` expands the binary value
  exactly (a double has at most 1074 fractional binary digits, so the result
  is finite). `FromDouble` tries 15, then 16, then 17 significant digits and keeps the
  first text that parses back to the same `Double`. This always ends, because
  17 digits always round-trip. The `Create` overload uses `FromDouble`,
  because that is the form callers expect. `ToDouble` does not rely on the FPC
  `Val` routine. It scales the value by a power of ten and a power of two to
  get a 54-bit integer quotient and a remainder with exact big integer
  arithmetic, and rounds half to even. This is the method of Clinger's
  Algorithm R. It is correctly rounded for any input length.
