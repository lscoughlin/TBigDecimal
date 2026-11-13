### 5.3 Exp

1. The first reduction splits `x = k · ln(10) + r`, with `k` an integer and
   `|r| ≤ ln(10)/2`. Then `exp(x) = 10^k · exp(r)`. The factor `10^k` is a
   change of scale, which costs nothing in a decimal library. This is better
   than a power of the constant `e`. The step needs `Ln10` at a precision of
   `p` plus the digit count of `k`, because the error in `Ln10` is multiplied
   by `k`.
2. The second reduction sets `r' = r / 2^s`, with `s = min(40, floor(sqrt(w)))`
   for a working precision of `w` digits. The limit of 40 keeps the error
   bound after the squarings below 10^15 units. The Taylor series then
   converges quickly.
3. The Taylor series of `exp(r')` uses the term recurrence
   `t_{k+1} = t_k · r' / (k+1)`. With step 2, the cost is
   O(M(p)·sqrt(p)) (see
   [Brent, "Fast algorithms for high-precision computation of elementary functions"](https://maths-people.anu.edu.au/~brent/pd/RNC7-Brent.pdf)).
4. `s` squarings restore the result. Each squaring loses about one bit, so
   the guard digit count grows by about `s · log10(2)`.
5. For high precision (at and above `ExpBitBurstDigits`, 8000 digits),
   `ExpFxCore` switches to **bit-burst**: split `r` into chunks of 1, 2, 4, 8, ...
   leading bits and use binary splitting on each chunk
   ([Johansson, elementary functions](https://www.fredrikj.net/math/aric2023elementary.pdf)).
   This gives O(M(p)·log²p).
