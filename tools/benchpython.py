"""Times multiply, divide, sqrt, exp and ln in Python decimal (libmpdec).

The operands match bench/BenchCompare.lpr. Run: python3 tools/benchpython.py
"""
import decimal
import time
from decimal import Decimal, Context, ROUND_HALF_EVEN


def digits(p, seed):
    d = [str((i * 7 + seed * 13 + (i * i) % 11) % 10) for i in range(1, p + 1)]
    d[0] = '1'
    return Decimal(d[0] + '.' + ''.join(d[1:]))


def per_call(fn, reps):
    t0 = time.perf_counter()
    for _ in range(reps):
        fn()
    return (time.perf_counter() - t0) / reps * 1e6


print('digits    multiply      divide        sqrt         exp          ln   (microseconds)')
print('Python', '(see Python version)', 'libmpdec', decimal.__libmpdec_version__)
for p in (34, 100, 300, 1000, 3000, 10000):
    ctx = Context(prec=p, rounding=ROUND_HALF_EVEN, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN)
    x = digits(p, 1)
    y = digits(p, 2)
    r1 = 20000000 // (p * p // 100 + 1) + 3
    r2 = 4000 // (p + 1) + 2
    r3 = 2 if p >= 3000 else 2000 // (p + 1) + 2
    row = [per_call(lambda: ctx.multiply(x, y), r1),
           per_call(lambda: ctx.divide(x, y), r1),
           per_call(lambda: ctx.sqrt(x), r2),
           per_call(lambda: ctx.exp(x), r3),
           per_call(lambda: ctx.ln(x), r3)]
    print('%6d' % p + ''.join('%12.2f' % v for v in row))
