#!/usr/bin/env python3
"""Writes oracle test vectors to tests/vectors/*.txt (tab separated).

Run with tools/.venv/bin/python tools/genvectors.py [count].
The oracle is Python decimal for arithmetic and rounding, and mpmath for the
transcendental functions (see the transcendental section below).
"""
import decimal, random, struct, sys, os, math
sys.set_int_max_str_digits(0)
from decimal import Decimal, Context, localcontext

COUNT = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
OUT = os.path.join(os.path.dirname(__file__), '..', 'tests', 'vectors')
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(20261015)

MODES = {
    'rmUp': decimal.ROUND_UP, 'rmDown': decimal.ROUND_DOWN,
    'rmCeiling': decimal.ROUND_CEILING, 'rmFloor': decimal.ROUND_FLOOR,
    'rmHalfUp': decimal.ROUND_HALF_UP, 'rmHalfDown': decimal.ROUND_HALF_DOWN,
    'rmHalfEven': decimal.ROUND_HALF_EVEN,
}
MODE_NAMES = list(MODES)

def exact_ctx():
    return Context(prec=decimal.MAX_PREC, Emax=decimal.MAX_EMAX,
                   Emin=decimal.MIN_EMIN, rounding=decimal.ROUND_HALF_EVEN,
                   traps=[decimal.InvalidOperation, decimal.DivisionByZero])

def digits(n):
    pat = rnd.random()
    if pat < 0.08:
        return '9' * n
    if pat < 0.12:
        return '1' + '0' * (n - 1)
    if pat < 0.16:
        return '5' + '0' * (n - 1)
    s = ''.join(rnd.choice('0123456789') for _ in range(n))
    if s[0] == '0':
        s = str(rnd.randint(1, 9)) + s[1:]
    return s

def gen_dec(maxd=60, allow_zero=True):
    if allow_zero and rnd.random() < 0.03:
        d = '0'
    else:
        r = rnd.random()
        n = rnd.randint(1, 9) if r < 0.3 else rnd.randint(1, maxd)
        d = digits(n)
    sign = '-' if rnd.random() < 0.4 else ''
    r = rnd.random()
    if r < 0.4:
        return sign + d
    if r < 0.8:
        p = rnd.randint(0, len(d))
        return sign + (d[:p] or '0') + '.' + d[p:] if p < len(d) else sign + d
    return sign + d + 'E' + str(rnd.randint(-30, 30))

def nz(x):
    # TBigDecimal has no negative zero
    t = str(x)
    if t.startswith('-'):
        try:
            if Decimal(t) == 0:
                return t[1:]
        except decimal.InvalidOperation:
            pass
    return t

def w(name, rows):
    with open(os.path.join(OUT, name + '.txt'), 'w') as f:
        for r in rows:
            f.write('\t'.join(nz(x) for x in r) + '\n')

def bits(x):
    return struct.unpack('<Q', struct.pack('<d', x))[0]

def main():
    C = exact_ctx()
    add, sub, mul, cmpr, rnd_rows, sets, divc, dive, divi, rem, tod, fromd, strip, sq = ([] for _ in range(14))
    for _ in range(COUNT):
        a, b = Decimal(gen_dec()), Decimal(gen_dec())
        sa, sb = str(a), str(b)
        add.append(('add', sa, sb, str(C.add(a, b))))
        sub.append(('sub', sa, sb, str(C.subtract(a, b))))
        mul.append(('mul', sa, sb, str(C.multiply(a, b))))
        cmpr.append(('cmp', sa, sb, (a > b) - (a < b)))
        sq.append(('sqr', sa, str(C.multiply(a, a))))
        p = rnd.randint(1, 40)
        m = rnd.choice(MODE_NAMES)
        with localcontext(Context(prec=p, rounding=MODES[m], Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN)) as lc:
            rnd_rows.append(('round', sa, p, m, str(+a)))
        ns = rnd.randint(-5, 45)
        q = Decimal(1).scaleb(-ns)
        try:
            r = a.quantize(q, rounding=MODES[m], context=Context(prec=decimal.MAX_PREC, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN))
            sets.append(('setscale', sa, ns, m, str(r)))
        except decimal.InvalidOperation:
            pass
        if b != 0:
            with localcontext(Context(prec=p, rounding=MODES[m], Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN)):
                divc.append(('divctx', sa, sb, p, m, str(a / b)))
            # exact division: build a case that often terminates
            if rnd.random() < 0.5:
                bb = Decimal(rnd.choice([2, 4, 5, 8, 16, 25, 40, 125, 3, 7, 11, 6, 12])) * Decimal(10) ** rnd.randint(-3, 3)
                aa = a
                key = (aa, bb)
            else:
                aa, bb = a, b
            ec = Context(prec=3000, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN,
                         traps=[decimal.Inexact, decimal.DivisionByZero, decimal.InvalidOperation])
            try:
                dive.append(('divexact', str(aa), str(bb), str(ec.divide(aa, bb))))
            except decimal.Inexact:
                dive.append(('divexact', str(aa), str(bb), 'ERR'))
            if abs(a) < Decimal(10) ** 40 and abs(b) > Decimal(10) ** -20:
                divi.append(('divint', sa, sb, str(C.divide_int(a, b)), str(C.remainder(a, b))))
        strip.append(('strip', sa, str(a.normalize(C)) if a != 0 else '0'))
        # doubles
        dstr = gen_dec(maxd=25)
        tod.append(('todouble', dstr, bits(float(Decimal(dstr))) if Decimal(dstr) != 0 else 0))
        x = struct.unpack('<d', struct.pack('<Q', rnd.getrandbits(64)))[0]
        if math.isfinite(x):
            fromd.append(('fromdouble', bits(x), repr(x)))
    for name, rows in [('add', add), ('sub', sub), ('mul', mul), ('cmp', cmpr),
                       ('round', rnd_rows), ('setscale', sets), ('divctx', divc),
                       ('divexact', dive), ('divint', divi), ('strip', strip),
                       ('todouble', tod), ('fromdouble', fromd), ('sqr', sq)]:
        w(name, rows)
    print('vectors written to', OUT)


# ---------------------------------------------------------------------------
# transcendental functions
# Oracle: Python decimal at 300 digits for sqrt, exp, ln, log10, power
# (correctly rounded in half-even mode, so the 300-digit value is close to
# exact), mpmath at 300 digits for the trigonometric functions. The 300-digit
# value is then rounded to p digits with Python decimal in each of the seven
# modes. Exact results (perfect squares, powers of ten) are exact at 300 digits.
# ---------------------------------------------------------------------------
import mpmath

def round_to(v, p, mode):
    with localcontext(Context(prec=p, rounding=MODES[mode], Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN)):
        return +v

def hp():
    return Context(prec=300, Emax=decimal.MAX_EMAX, Emin=decimal.MIN_EMIN, rounding=decimal.ROUND_HALF_EVEN)

def mp_dec(x):
    mpmath.mp.dps = 320
    return Decimal(mpmath.nstr(x, 310, strip_zeros=False, min_fixed=-10**9, max_fixed=10**9))

def rand_pos(maxd=30):
    d = Decimal(gen_dec(maxd, allow_zero=False))
    return abs(d) if d != 0 else Decimal(1)

def transc(count):
    rows = {k: [] for k in ('sqrt', 'exp', 'ln', 'log10', 'log', 'pow', 'root', 'sin', 'cos', 'tan')}
    H = hp()
    for i in range(count):
        p = rnd.choice([1, 2, 3, 5, 9, 16, 20, 34, 50, 80, 150])
        m = rnd.choice(MODE_NAMES)
        x = rand_pos()
        rows['sqrt'].append(('sqrt', str(x), p, m, str(round_to(H.sqrt(x), p, m))))
        # perfect squares and powers of ten are exact
        if i % 7 == 0:
            r0 = rand_pos(12)
            sq = r0 * r0
            rows['sqrt'].append(('sqrt', str(sq), p, m, str(round_to(H.sqrt(sq), p, m))))
        xe = Decimal(rnd.uniform(-300, 300)).quantize(Decimal(10) ** rnd.randint(-12, 3))
        rows['exp'].append(('exp', str(xe), p, m, str(round_to(H.exp(xe), p, m))))
        rows['ln'].append(('ln', str(x), p, m, str(round_to(H.ln(x), p, m))))
        near1 = Decimal(1) + Decimal(rnd.randint(-999, 999)) * Decimal(10) ** -rnd.randint(3, 25)
        rows['ln'].append(('ln', str(near1), p, m, str(round_to(H.ln(near1), p, m))))
        rows['log10'].append(('log10', str(x), p, m, str(round_to(H.log10(x), p, m))))
        pw = Decimal(10) ** rnd.randint(-20, 20)
        rows['log10'].append(('log10', str(pw), p, m, str(round_to(H.log10(pw), p, m))))
        b = rand_pos(6)
        if b == 1:
            b = Decimal(3)
        if x == 1:
            x = Decimal(2)
        lg = H.divide(H.ln(x), H.ln(b))
        rows['log'].append(('log', str(b), str(x), p, m, str(round_to(lg, p, m))))
        y = Decimal(rnd.randint(-40, 40)) / Decimal(rnd.choice([1, 2, 4, 5, 8, 10, 100, 1000]))
        xp = rand_pos(8)
        try:
            pv = H.power(xp, y)
            rows['pow'].append(('pow', str(xp), str(y), p, m, str(round_to(pv, p, m))))
        except Exception:
            pass
        k = rnd.randint(2, 7)
        rv = H.power(x, Decimal(1) / Decimal(k)) if False else mp_dec(mpmath.root(mpmath.mpf(str(x)), k))
        cand = round_to(rv, 40, 'rmHalfEven')
        if cand ** k == x:
            continue  # exact roots follow the preferred-scale rule, tested in the square root cases
        rows['root'].append(('root', str(x), k, p, m, str(round_to(rv, p, m))))
        ax = Decimal(gen_dec(12, allow_zero=False))
        if abs(ax) > 10**12:
            ax = ax / 10**rnd.randint(1, 8)
        mpmath.mp.dps = 320
        for fn, name in ((mpmath.sin, 'sin'), (mpmath.cos, 'cos'), (mpmath.tan, 'tan')):
            v = fn(mpmath.mpf(str(ax)))
            rows[name].append((name, str(ax), p, m, str(round_to(mp_dec(v), p, m))))
    # exact cases
    for sx in ['4', '9', '0.25', '2.25', '100', '1E+4', '1E-4', '0.0001', '6.25', '1.21']:
        for p in (1, 2, 3, 9):
            for m in MODE_NAMES:
                x = Decimal(sx)
                rows['sqrt'].append(('sqrt', sx, p, m, str(round_to(H.sqrt(x), p, m))))
    exact_logs = {('2', '8'): Decimal(3), ('4', '2'): Decimal('0.5'), ('10', '1000'): Decimal(3),
                  ('2', '0.125'): Decimal(-3), ('3', '81'): Decimal(4), ('0.5', '4'): Decimal(-2)}
    for bs, xs in [('2', '8'), ('4', '2'), ('10', '1000'), ('2', '0.125'), ('8', '4'), ('3', '81'), ('0.5', '4')]:
        for p in (1, 3, 9):
            for m in MODE_NAMES:
                if (bs, xs) in exact_logs:
                    lg = exact_logs[(bs, xs)]
                else:
                    lg = H.divide(H.ln(Decimal(xs)), H.ln(Decimal(bs)))
                rows['log'].append(('log', bs, xs, p, m, str(round_to(lg, p, m))))
    for xs, ys in [('4', '0.5'), ('100', '1.5'), ('5.0625', '0.5'), ('8', '0.3333333333333333'), ('0.25', '0.5'), ('16', '0.75'), ('2.25', '-0.5'), ('9', '1.5'), ('1000000', '0.5')]:
        for p in (1, 2, 3, 9):
            for m in MODE_NAMES:
                pv = H.power(Decimal(xs), Decimal(ys))
                rows['pow'].append(('pow', xs, ys, p, m, str(round_to(pv, p, m))))
    return rows

def write_transc(count):
    rows = transc(count)
    for name, r in rows.items():
        w(name, r)


def comb_vectors():
    rows = {k: [] for k in ('fact', 'binom', 'perm', 'dfact', 'catalan', 'primorial', 'rising', 'gamma', 'lngamma')}
    H = hp()
    ns = [0, 1, 2, 19, 20, 21, 22, 100, 1499, 1500, 1501, 1502, 3000, 3001, 5000, 12345, 40000]
    for n in ns:
        rows['fact'].append(('fact', n, math.factorial(n)))
    for _ in range(150):
        n = rnd.randint(0, 3000)
        rows['fact'].append(('fact', n, math.factorial(n)))
    for n, k in [(0, 0), (5, 0), (5, 5), (5, 6), (100, 50), (100, 100), (200, 99), (200, 100), (201, 101), (300, 150),
                 (1000, 500), (1000, 3), (5000, 2500), (20000, 10000), (62, 31), (67, 33), (68, 34), (10**9, 3), (10**6, 4)]:
        rows['binom'].append(('binom', n, k, math.comb(n, k)))
    for _ in range(300):
        n = rnd.randint(0, 2000)
        k = rnd.randint(0, n)
        rows['binom'].append(('binom', n, k, math.comb(n, k)))
    for _ in range(100):
        n = rnd.randint(0, 10**6)
        k = rnd.randint(0, min(n, 12))
        rows['binom'].append(('binom', n, k, math.comb(n, k)))
    for _ in range(100):
        n = rnd.randint(0, 5000)
        k = rnd.randint(0, n)
        rows['perm'].append(('perm', n, k, math.perm(n, k)))
    for n in list(range(0, 30)) + [101, 500, 1001, 3000]:
        d = 1
        for i in range(n, 0, -2):
            d *= i
        rows['dfact'].append(('dfact', n, d))
    for n in list(range(0, 40)) + [100, 500, 1000]:
        rows['catalan'].append(('catalan', n, math.comb(2 * n, n) // (n + 1)))
    for n in [0, 1, 2, 3, 10, 30, 100, 1000, 5000]:
        pr = 1
        for q in range(2, n + 1):
            if all(q % d for d in range(2, int(q ** .5) + 1)):
                pr *= q
        rows['primorial'].append(('primorial', n, pr))
    for xs, k in [('2.5', 5), ('0.1', 7), ('-3.5', 4), ('10', 10), ('1.5', 0), ('0.001', 30)]:
        x = Decimal(xs)
        r = Decimal(1)
        for i in range(k):
            r = decimal.Context(prec=2000).multiply(r, x + i)
        rows['rising'].append(('rising', xs, k, str(r)))
    mpmath.mp.dps = 320
    xs = ['0.5', '1.5', '2.5', '0.1', '0.001', '3.7', '10.25', '33.3333', '100.5', '250.125', '-0.5', '-1.5', '-2.25',
          '-10.5', '-37.125', '-300.75', '-1234.5', '1234.5']
    for _ in range(40):
        xs.append(str(Decimal(rnd.uniform(0.01, 80)).quantize(Decimal(10) ** -rnd.randint(1, 10))))
    for _ in range(25):
        xs.append(str(Decimal(rnd.uniform(-60, -0.01)).quantize(Decimal(10) ** -rnd.randint(1, 10))))
    for xsx in xs:
        x = Decimal(xsx)
        if x == x.to_integral_value():
            continue
        for p, m in ((rnd.choice([5, 9, 20, 34, 60, 120]), rnd.choice(MODE_NAMES)) for _ in range(3)):
            v = mpmath.gamma(mpmath.mpf(xsx))
            rows['gamma'].append(('gamma', xsx, p, m, str(round_to(mp_dec(v), p, m))))
            if x > 0:
                v = mpmath.loggamma(mpmath.mpf(xsx))
                rows['lngamma'].append(('lngamma', xsx, p, m, str(round_to(mp_dec(v), p, m))))
    for n in [1, 2, 3, 4, 5, 10, 20, 50, 100, 170, 500]:
        for p in (5, 34):
            rows['gamma'].append(('gamma', str(n), p, 'rmHalfEven', str(round_to(Decimal(math.factorial(n - 1)), p, 'rmHalfEven'))))
    for n in [3, 4, 10, 100, 1000]:
        for p in (9, 34, 80):
            v = mpmath.loggamma(mpmath.mpf(n))
            rows['lngamma'].append(('lngamma', str(n), p, 'rmHalfEven', str(round_to(mp_dec(v), p, 'rmHalfEven'))))
    return rows

def write_comb():
    for name, r in comb_vectors().items():
        w(name, r)


def fin_vectors():
    rows = {k: [] for k in ('compound', 'pv', 'fv', 'annuity', 'rate', 'pi', 'e', 'ln2', 'ln10')}
    H = hp()
    mpmath.mp.dps = 320
    for _ in range(120):
        p = rnd.choice([5, 9, 16, 34, 60])
        m = rnd.choice(MODE_NAMES)
        r = Decimal(rnd.randint(1, 3000)) / Decimal(10) ** rnd.randint(3, 5)
        n = Decimal(rnd.randint(1, 400)) / Decimal(rnd.choice([1, 1, 2, 4, 10, 12]))
        amt = Decimal(rnd.randint(1, 10**9)) / Decimal(10) ** rnd.randint(0, 4)
        f = H.power(1 + r, n)
        rows['compound'].append(('compound', str(r), str(n), p, m, str(round_to(f, p, m))))
        rows['pv'].append(('pv', str(amt), str(r), str(n), p, m, str(round_to(H.divide(amt, f), p, m))))
        rows['fv'].append(('fv', str(amt), str(r), str(n), p, m, str(round_to(H.multiply(amt, f), p, m))))
        an = H.divide(H.subtract(Decimal(1), H.power(1 + r, -n)), r)
        rows['annuity'].append(('annuity', str(r), str(n), p, m, str(round_to(an, p, m))))
        ratio = Decimal(rnd.randint(11, 9000)) / Decimal(rnd.choice([10, 100, 1000]))
        yrs = Decimal(rnd.randint(1, 60)) / Decimal(rnd.choice([1, 2, 4]))
        rate = H.subtract(H.power(ratio, H.divide(1, yrs)), Decimal(1))
        rows['rate'].append(('rate', str(ratio), str(yrs), p, m, str(round_to(rate, p, m))))
    for p in (1, 2, 5, 9, 16, 34, 60, 100, 250, 300):
        for m in MODE_NAMES:
            rows['pi'].append(('pi', p, m, str(round_to(mp_dec(mpmath.pi), p, m))))
            rows['e'].append(('e', p, m, str(round_to(mp_dec(mpmath.e), p, m))))
            rows['ln2'].append(('ln2', p, m, str(round_to(mp_dec(mpmath.log(2)), p, m))))
            rows['ln10'].append(('ln10', p, m, str(round_to(mp_dec(mpmath.log(10)), p, m))))
    return rows

def write_fin():
    for name, r in fin_vectors().items():
        w(name, r)

if __name__ == '__main__':
    main()
    write_transc(max(200, COUNT // 6))
    write_comb()
    write_fin()
