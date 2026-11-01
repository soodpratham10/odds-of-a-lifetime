[← Previous: Detours](01-detours.md) · [Overview](../../README.md) · **Chapter 2 of 7** · [Next: Two Lives →](03-two-lives.md)

# Chapter 2: Exits

*A term policy ends in one of three ways: the policyholder dies, walks away (lapses), or reaches the end of the term. How many leave each way, and when, changes the price.*

| | |
|---|---|
| **Actuarial model** | Multiple decrement model: death and lapse |
| **Engine** | [`r/decrement.R`](../../r/decrement.R) |
| **Experience data** | [`r/experience.R`](../../r/experience.R), [`sql/exit_study.sql`](../../sql/exit_study.sql) |
| **Excel cross-check** | [`excel/exits_crosscheck.xlsx`](../../excel/exits_crosscheck.xlsx) |
| **Calculator** | [Chapter 2 tab, live](https://soodpratham10.shinyapps.io/odds-of-a-lifetime/) |

## What the engine does

- **Multiple decrement tables**: lives in force and exits by cause, year by year
- **Associated single decrement rates**: converting between independent and dependent rates under either uniform distribution assumption, for any number of decrements
- **Constant forces of decrement**
- **Benefits that depend on the cause of exit**, annuities and premiums

## The mathematics

Total exit probability, and the probability of staying in force for $k$ years:

$$
q^{(\tau)}_{x} = \sum_j q^{(j)}_{x},
\qquad
{}_kp^{(\tau)}_x = \prod_{r=0}^{k-1}\big(1 - q^{(\tau)}_{x+r}\big)
$$

If each decrement is uniformly distributed over the year in its own single decrement table, the dependent rates follow from the independent ones:

$$
q^{(j)}_x = q^{\prime(j)}_x \int_0^1 \prod_{k \neq j} \big(1 - tq^{\prime(k)}_x\big) dt
$$

which for two decrements is $q^{(1)} = q^{\prime(1)}\big(1 - \tfrac{1}{2}q^{\prime(2)}\big)$. If instead decrements are uniform in the multiple decrement table:

$$
p^{\prime(j)}_x = \big(p^{(\tau)}_x\big)^{q^{(j)}_x / q^{(\tau)}_x}
$$

Benefits $b^{(j)}$ paid at the end of the year of exit, and premiums paid at the start of each year while in force:

$$
\text{EPV} = \sum_{k=0}^{n-1} v^{k+1} {}_kp^{(\tau)}_x \sum_j b^{(j)} q^{(j)}_{x+k},
\qquad
\ddot{a} = \sum_{k=0}^{n-1} v^{k} {}_kp^{(\tau)}_x
$$

## What the calculator shows

A 20-year term policy with a $250,000 death benefit, mortality starting at 0.002 and rising 8% a year, lapses of 10% in year one and 5% after, and 5% interest:

| | Premium |
|---|---|
| Allowing for lapses | $816.86 |
| If nobody lapses | $953.62 |
| Effect of lapses | −14.3% |

Lapses remove people before they reach the expensive later years, so the expected lapses lower the premium. This is **lapse-supported pricing**, and it is a real risk: if fewer people lapse than assumed, the insurer has undercharged.

## Where the exits come from (SQL)

50,000 simulated policies are stored in SQLite, one row per policy with the year it ended and why. `sql/exit_study.sql` counts, for each policy year, the policies in force at the start and the deaths and lapses during the year. The estimated rates and the actual-to-expected ratio are

$$
\hat{q}^{(j)}_k = \frac{d^{(j)}_k}{l_k},
\qquad
\frac{A}{E} = \frac{\sum_k d^{(j)}_k}{\sum_k l_k q^{(j)}_k}
$$

Against the assumptions used to price the policy:

| Decrement | Actual | Expected | A/E |
|---|---|---|---|
| Death | 2,277 | 2,310 | 98.6% |
| Lapse | 31,970 | 32,259 | 99.1% |

The calculator recomputes A/E live as the assumption sliders move, and plots the observed lapse rate in each policy year against the assumption, so a mis-set assumption shows up straight away.

## A second opinion (Excel)

The workbook rebuilds the decrement table and both premiums in spreadsheet formulas, and re-runs the experience study from the SQL results. It matches R to the cent ($816.86, $953.62, $6,935.63, annuity factor 8.4906) and gives the same A/E ratios.

## The two chapters are one model

A multiple decrement model is a multiple state model with one starting state. A test checks this directly: the Chapter 1 Kolmogorov solver, applied to a model with states *in force*, *dead* and *lapsed*, reproduces the Chapter 2 decrement probabilities.

## Key functions

| Function | What it does |
|---|---|
| `decrement_table()` | Lives in force and exits by cause |
| `udd_single_to_multiple()`, `udd_multiple_to_single()` | Conversions between independent and dependent rates |
| `const_force_probs()` | Exit probabilities under constant forces |
| `md_epv_benefits()`, `md_annuity_due()`, `md_premium()` | Benefits, annuities and premiums |
| `simulate_policies()`, `estimate_decrement_rates()`, `actual_vs_expected()` | Experience study and A/E |

---

[← Previous: Detours](01-detours.md) · [Overview](../../README.md) · **Chapter 2 of 7** · [Next: Two Lives →](03-two-lives.md)
