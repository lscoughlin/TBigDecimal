"""Times multiply, divide, sqrt, exp and ln in Python decimal (libmpdec).

The operands match bench/BenchCompare.lpr and bench/BenchBigMul.lpr.
Run: python3 tools/benchpython.py
     python3 tools/benchpython.py --bigmul
"""
import decimal
import sys
import time
from decimal import Decimal, Context, ROUND_HALF_EVEN


def digits(p, seed):
    d = [str((i * 7 + seed * 13 + (i * i) % 11) % 10) for i in range(1, p + 1)]
    d[0] = '1'
    return Decimal(d[0] + '.' + ''.join(d[1:]))


def per_call(fn):
    reps = 1
    while True:
        t0 = time.perf_counter()
        for _ in range(reps):
            fn()
        t = time.perf_counter() - t0
        if t >= 0.05:
            break
        reps *= 2
    best = t / reps * 1e6
    for _ in range(4):
        t0 = time.perf_counter()
        for _ in range(reps):
            fn()
        best = min(best, (time.perf_counter() - t0) / reps * 1e6)
    return best


if '--bigmul' in sys.argv or 'bigmul' in sys.argv:
    print('digits        time (ms)')
    for p in (30000, 100000, 300000, 1000000, 3000000):
        ctx = Context(prec=2*p, rounding=ROUND_HALF_EVEN, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN)
        x = digits(p, 1)
        y = digits(p, 2)
        t = per_call(lambda: ctx.multiply(x, y)) / 1000.0
        print(f'{p:8d} {t:12.2f} ms')
else:
    print('digits    multiply      divide        sqrt         exp          ln   (microseconds)')
    print('Python', '(see Python version)', 'libmpdec', decimal.__libmpdec_version__)
    for p in (34, 100, 300, 1000, 3000, 10000):
        ctx = Context(prec=p, rounding=ROUND_HALF_EVEN, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN)
        x = digits(p, 1)
        y = digits(p, 2)
        row = [per_call(lambda: ctx.multiply(x, y)),
               per_call(lambda: ctx.divide(x, y)),
               per_call(lambda: ctx.sqrt(x)),
               per_call(lambda: ctx.exp(x)),
               per_call(lambda: ctx.ln(x))]
        print('%6d' % p + ''.join('%12.2f' % v for v in row))
