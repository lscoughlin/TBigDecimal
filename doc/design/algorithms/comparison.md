### 3.6 Comparison

Comparison checks the signs first. It then checks the adjusted exponents
(`Precision − Scale − 1`). If these differ, the larger exponent wins. Only
when they are equal does it compare limbs. When the scales differ and the adjusted exponents are equal, the operand with
the smaller scale is multiplied by a power of ten into a temporary array, and
the limbs then compare. This case allocates one array. Equal scales, and
operands whose adjusted exponents differ, allocate nothing.
