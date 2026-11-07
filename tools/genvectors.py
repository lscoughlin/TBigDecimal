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


# ---------------------------------------------------------------------------
# Excel annuity and rate vectors
# Oracle: Python decimal at 300 digits, certified at 340 digits. A row is kept
# only when both precisions round to the same expected value, so rows near a
# rounding boundary (including true-integer NPER values) never reach the file.
# ---------------------------------------------------------------------------

def xl_ctx(prec):
    return Context(prec=prec, Emax=10**9, Emin=-10**9, rounding=decimal.ROUND_HALF_EVEN)

def xl_growth(ctx, r, n):
    return ctx.power(ctx.add(1, r), n)

# All oracle steps use the given context. Plain operators and unary minus
# would fall back to the 28-digit default context.

def xl_pmt(ctx, r, n, pv, fv, t):
    if r == 0:
        return ctx.minus(ctx.divide(ctx.add(pv, fv), n))
    g = xl_growth(ctx, r, n)
    a = ctx.add(1, ctx.multiply(r, t))
    return ctx.minus(ctx.divide(ctx.multiply(ctx.add(ctx.multiply(pv, g), fv), r),
                               ctx.multiply(a, ctx.subtract(g, 1))))

def xl_nper(ctx, r, pmt, pv, fv, t):
    if r == 0:
        return ctx.minus(ctx.divide(ctx.add(pv, fv), pmt))
    a = ctx.add(1, ctx.multiply(r, t))
    num = ctx.subtract(ctx.multiply(pmt, a), ctx.multiply(fv, r))
    den = ctx.add(ctx.multiply(pmt, a), ctx.multiply(pv, r))
    return ctx.divide(ctx.ln(ctx.divide(num, den)), ctx.ln(ctx.add(1, r)))

def xl_fv(ctx, r, n, pmt, pv, t):
    if r == 0:
        return ctx.minus(ctx.add(pv, ctx.multiply(pmt, n)))
    g = xl_growth(ctx, r, n)
    a = ctx.add(1, ctx.multiply(r, t))
    return ctx.minus(ctx.add(ctx.multiply(pv, g),
                             ctx.divide(ctx.multiply(ctx.multiply(pmt, a), ctx.subtract(g, 1)), r)))

def xl_rate_newton(ctx, n, pmt, pv, fv, t, guess):
    r = ctx.create_decimal(guess)
    tol = Decimal(10) ** -(ctx.prec - 20)
    for _ in range(80):
        if r == 0:
            f = ctx.add(ctx.add(pv, fv), ctx.multiply(pmt, n))
            half = ctx.divide(ctx.subtract(n, 1), 2)
            df = ctx.add(ctx.multiply(pv, n),
                         ctx.multiply(ctx.multiply(pmt, n), ctx.add(half, t)))
        else:
            g = xl_growth(ctx, r, n)
            gm1 = ctx.subtract(g, 1)
            u = ctx.add(1, ctx.multiply(r, t))
            h = ctx.divide(gm1, r)
            gp = ctx.divide(ctx.multiply(g, n), ctx.add(1, r))
            dh = ctx.divide(ctx.subtract(ctx.multiply(r, gp), gm1), ctx.multiply(r, r))
            f = ctx.add(ctx.add(ctx.multiply(pv, g), ctx.multiply(ctx.multiply(pmt, u), h)), fv)
            df = ctx.add(ctx.multiply(pv, gp), ctx.multiply(ctx.multiply(pmt, u), dh))
            if t:
                df = ctx.add(df, ctx.multiply(pmt, h))
        if f == 0:
            return r
        if df == 0:
            return None
        dr = ctx.divide(f, df)
        if abs(dr) < tol:
            return ctx.subtract(r, dr)
        step = dr
        for _ in range(60):
            cand = ctx.subtract(r, step)
            if cand > -1:
                break
            step = ctx.divide(step, 2)
        else:
            return None
        r = cand
    return None

def xl_certified(fn, p, mode):
    # Returns (expected, fine value). Callers also apply xl_guarded: dual
    # agreement alone cannot see a true value that hugs a boundary closer
    # than the library working precision.
    H = xl_ctx(300)
    H2 = xl_ctx(340)
    try:
        v1 = fn(H)
        v2 = fn(H2)
    except Exception:
        return None, None
    if v1 is None or v2 is None:
        return None, None
    if v1.is_nan() or v2.is_nan():
        return None, None
    e1 = round_to(v1, p, mode)
    e2 = round_to(v2, p, mode)
    if e1.is_zero() and e2.is_zero():
        return '0', v2
    if str(e1) != str(e2):
        return None, None
    return str(e1), v2

def xl_certified3(fn, p, mode):
    H = xl_ctx(300)
    H2 = xl_ctx(340)
    H3 = xl_ctx(600)
    try:
        v1 = fn(H)
        v2 = fn(H2)
        v3 = fn(H3)
    except Exception:
        return None, None
    if v1 is None or v2 is None or v3 is None:
        return None, None
    if v1.is_nan() or v2.is_nan() or v3.is_nan():
        return None, None
    e1 = round_to(v1, p, mode)
    e2 = round_to(v2, p, mode)
    e3 = round_to(v3, p, mode)
    if e1.is_zero() and e2.is_zero() and e3.is_zero():
        return '0', v3
    if not (str(e1) == str(e2) == str(e3)):
        return None, None
    return str(e1), v3

def xl_guarded(vfine, p):
    # True when the fine solve sits at least a thousandth of an ulp from
    # every p-digit decision boundary. All arithmetic runs wide.
    with localcontext(xl_ctx(700)):
        lo = round_to(vfine, p, 'rmDown')
        hi = round_to(vfine, p, 'rmUp')
        if vfine == lo or vfine == hi:
            return False
        ulp = abs(hi - lo)
        if ulp == 0:
            return False
        mid = (lo + hi) / 2
        gap = min(abs(vfine - lo), abs(hi - vfine), abs(vfine - mid))
        return gap >= ulp * Decimal('1E-3')

def xl_rate():
    v = rnd.choice(['0.08', '0.05', '0.12', '0.1', '0.06', '0.0525',
                    str(rnd.randint(1, 3000) / 10 ** rnd.randint(3, 6)),
                    str(rnd.randint(1, 999) / 10 ** rnd.randint(7, 12)),
                    '1E-30', '2.5E-9', '0.006666666666666667', '0']) \
        if rnd.random() < 0.5 else str((Decimal(rnd.randint(1, 9000)) / 10000).quantize(Decimal(10) ** -rnd.randint(2, 8)))
    if v != '0' and rnd.random() < 0.2:
        v = '-' + v
    return v

def xl_money():
    if rnd.random() < 0.15:
        return '0'
    v = Decimal(rnd.randint(1, 10**9)) / Decimal(10) ** rnd.randint(0, 4)
    return str(-v if rnd.random() < 0.5 else v)

def xl_prec():
    r = rnd.random()
    if r < 0.1:
        return rnd.choice([100, 150, 200])
    return rnd.choice([5, 9, 16, 34, 60])

def xl_prec_r():
    # ratexl roots hug the planted value, which carries 64 decimals,
    # so precision stays below that depth (see the ratexl comment)
    if rnd.random() < 0.1:
        return 50
    return rnd.choice([5, 9, 16, 34])

def xl_rt_long(short, neg=False):
    # A planted root needs more digits than any row precision, else the
    # true root sits on a rounding boundary and no implementation can
    # side it by string compare. Built by string surgery, so no context
    # rounds the tail.
    tail = str(rnd.randint(1, 10**30 - 1)).zfill(30)
    s = str(short)
    if '.' in s:
        head, frac = s.split('.')
    else:
        head, frac = s, ''
    frac = ((frac + '0' * 34)[:34] + tail)[:64]
    return Decimal(('-' if neg else '') + head + '.' + frac)

def xl_vectors():
    rows = {k: [] for k in ('pmt', 'nper', 'ratexl', 'effect', 'nominal')}
    # --- pmt ---
    made, guard = 0, 0
    while made < 200 and guard < 4000:
        guard += 1
        rs, ns = xl_rate(), rnd.randint(1, 360) if rnd.random() < 0.95 else rnd.randint(361, 5000)
        pvs, fvs, t = xl_money(), (xl_money() if rnd.random() < 0.4 else '0'), rnd.randint(0, 1)
        if Decimal(rs) <= -1:
            continue
        p, m = xl_prec(), rnd.choice(MODE_NAMES)
        exp, vfine = xl_certified(lambda H, rs=rs, ns=ns, pvs=pvs, fvs=fvs, t=t:
                                  xl_pmt(H, H.create_decimal(rs), ns, H.create_decimal(pvs),
                                         H.create_decimal(fvs), t), p, m)
        if exp is None:
            continue
        if exp != '0' and not xl_guarded(vfine, p):
            continue
        rows['pmt'].append(('pmt', rs, ns, pvs, fvs, t, p, m, exp))
        made += 1
    # --- nper ---
    made, guard = 0, 0
    while made < 200 and guard < 8000:
        guard += 1
        r = Decimal(xl_rate())
        if r <= -1:
            continue
        pmt = Decimal(xl_money())
        pv = Decimal(rnd.randint(1, 10**7)) / Decimal(10) ** rnd.randint(0, 2)
        if rnd.random() < 0.3:
            pv = -pv
        fv = Decimal(xl_money()) if rnd.random() < 0.5 else Decimal(0)
        t = rnd.randint(0, 1)
        if r == 0 and pmt == 0:
            continue
        H = xl_ctx(300)
        try:
            if r == 0:
                v = H.minus(H.divide(H.add(H.create_decimal(pv), H.create_decimal(fv)),
                                     H.create_decimal(pmt)))
            else:
                a = H.add(1, H.multiply(H.create_decimal(r), t))
                num = H.subtract(H.multiply(H.create_decimal(pmt), a), H.multiply(H.create_decimal(fv), H.create_decimal(r)))
                den = H.add(H.multiply(H.create_decimal(pmt), a), H.multiply(H.create_decimal(pv), H.create_decimal(r)))
                if num == 0 or (num > 0) != (den > 0):
                    continue
                v = H.divide(H.ln(H.divide(num, den)), H.ln(H.add(1, H.create_decimal(r))))
            # true-integer values are untestable by string compare
            if abs(v - v.to_integral_value(rounding=decimal.ROUND_HALF_EVEN)) < Decimal(10) ** -270:
                continue
        except Exception:
            continue
        p, m = xl_prec(), rnd.choice(MODE_NAMES)
        exp, vfine = xl_certified(lambda H, r=r, pmt=pmt, pv=pv, fv=fv, t=t:
                                  xl_nper(H, H.create_decimal(r), H.create_decimal(pmt),
                                          H.create_decimal(pv), H.create_decimal(fv), t), p, m)
        if exp is None:
            continue
        if exp != '0' and not xl_guarded(vfine, p):
            continue
        rows['nper'].append(('nper', str(r), str(pmt), str(pv), str(fv), t, p, m, exp))
        made += 1
    # --- ratexl: forward-built rows with a known root near the oracle solve ---
    made, guard = 0, 0
    while made < 120 and guard < 6000:
        guard += 1
        n = rnd.randint(1, 360)
        t = rnd.randint(0, 1)
        shape = rnd.random()
        if shape < 0.1:
            pmt, pv = Decimal(0), Decimal(rnd.randint(1, 10**6)) / 100
            if rnd.random() < 0.3:
                rt = xl_rt_long(Decimal(rnd.randint(1, 1000)) / 10000, True)
            else:
                rt = xl_rt_long(Decimal(rnd.randint(1, 2000)) / 10000)
            if rt <= -1 or rt == 0:
                continue
        elif shape < 0.2:
            rt = xl_rt_long(Decimal(rnd.randint(1, 500)) / 100000)
            pmt = -(Decimal(rnd.randint(1, 10**5)) / 100)
            pv = Decimal(rnd.randint(1, 10**7)) / 100
        else:
            rt = xl_rt_long(Decimal(rnd.randint(1, 6000)) / 10000)
            if rnd.random() < 0.25:
                rt = xl_rt_long(Decimal(rnd.randint(1, 4000)) / 10000, True)
            if rt <= -1 or rt == 0 or abs(rt) < Decimal('1E-8'):
                continue
            pmt = Decimal(xl_money())
            pv = Decimal(xl_money())
            if pmt == 0 and pv == 0:
                continue
        H = xl_ctx(300)
        try:
            fv = xl_fv(H, H.create_decimal(rt), n, H.create_decimal(pmt),
                       H.create_decimal(pv), t)
        except Exception:
            continue
        if n == 1 and H.create_decimal(pmt) == 0 and H.create_decimal(pv) == 0:
            continue
        guess = '0.1'
        p, m = xl_prec_r(), rnd.choice(MODE_NAMES)
        exp, vfine = xl_certified3(lambda H, n=n, pmt=pmt, pv=pv, fv=fv, t=t:
                                   xl_rate_newton(H, n, H.create_decimal(pmt), H.create_decimal(pv),
                                                  H.create_decimal(fv), t, guess), p, m)
        if exp is None or exp == '0':
            continue
        # the oracle solve must sit next to the planted root
        if abs(Decimal(exp) - rt) > max(abs(rt), Decimal(1)) * Decimal(2) * (Decimal(10) ** -(p - 1)):
            continue
        # ... and clear of every rounding boundary
        if not xl_guarded(vfine, p):
            continue
        rows['ratexl'].append(('ratexl', n, str(pmt), str(pv), str(fv), t, guess, p, m, exp))
        made += 1
    # --- effect / nominal ---
    made, guard = 0, 0
    while made < 120 and guard < 2000:
        guard += 1
        nom = Decimal(rnd.randint(1, 30000)) / Decimal(10) ** rnd.randint(4, 7)
        if rnd.random() < 0.15:
            nom = Decimal(rnd.randint(1, 999)) * Decimal(10) ** -rnd.randint(8, 35)
        npery = rnd.randint(1, 365) if rnd.random() < 0.9 else rnd.randint(366, 8760)
        p, m = xl_prec(), rnd.choice(MODE_NAMES)
        exp, vfine = xl_certified(lambda H, nom=nom, npery=npery:
                                  H.subtract(H.power(H.add(1, H.divide(H.create_decimal(nom), npery)), npery), 1),
                                  p, m)
        if exp is None:
            continue
        if exp != '0' and not xl_guarded(vfine, p):
            continue
        rows['effect'].append(('effect', str(nom), npery, p, m, exp))
        made += 1
    made, guard = 0, 0
    while made < 120 and guard < 2000:
        guard += 1
        eff = Decimal(rnd.randint(1, 30000)) / Decimal(10) ** rnd.randint(4, 7)
        if rnd.random() < 0.15:
            eff = Decimal(rnd.randint(1, 999)) * Decimal(10) ** -rnd.randint(8, 35)
        npery = rnd.randint(1, 365) if rnd.random() < 0.9 else rnd.randint(366, 8760)
        p, m = xl_prec(), rnd.choice(MODE_NAMES)
        exp, vfine = xl_certified(lambda H, eff=eff, npery=npery:
                                  H.multiply(npery, H.subtract(
                                      H.power(H.add(1, H.create_decimal(eff)),
                                              H.divide(1, npery)), 1)), p, m)
        if exp is None:
            continue
        if exp != '0' and not xl_guarded(vfine, p):
            continue
        rows['nominal'].append(('nominal', str(eff), npery, p, m, exp))
        made += 1
    return rows

def write_xl():
    for name, r in xl_vectors().items():
        w(name, r)

if __name__ == '__main__':
    main()
    write_transc(max(200, COUNT // 6))
    write_comb()
    write_fin()
    write_xl()
