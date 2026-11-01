[← Previous: Exits](02-exits.md) · [Overview](../../README.md) · **Chapter 3 of 7**

# Chapter 3: Two Lives

*A couple retires on a promise: an income while both are alive, and part of it for whoever survives. How long each lives, and which one goes first, sets the cost.*

| | |
|---|---|
| **Actuarial model** | Multiple life model: joint life and last survivor |
| **Engine** | [`r/multilife.R`](../../r/multilife.R) |
| **Experience data** | [`r/experience.R`](../../r/experience.R), [`sql/couple_study.sql`](../../sql/couple_study.sql) |
| **Excel cross-check** | [`excel/two_lives_crosscheck.xlsx`](../../excel/two_lives_crosscheck.xlsx) |
| **Calculator** | [Chapter 3 tab, live](https://soodpratham10.shinyapps.io/odds-of-a-lifetime/) |

## What the engine does

- **Joint-life and last-survivor statuses**: survival, annuities and insurances on the first and second death
- **Reversionary annuities**: income to one life only after the other has died
- **Contingent probabilities**: the chance that one life dies before the other
- **Expected time to first and last death** under constant forces
- **Makeham mortality** with the parameters of the SOA Standard Ultimate Life Table

## The mathematics

For independent lives, the joint-life status survives while both are alive, and the last-survivor status while at least one is:

$$
{}_kp_{xy} = {}_kp_x \cdot {}_kp_y,
\qquad
{}_kp_{\overline{xy}} = {}_kp_x + {}_kp_y - {}_kp_{xy}
$$

Annuities paid at the start of each year while the status survives satisfy

$$
\ddot{a}_{xy} + \ddot{a}_{\overline{xy}} = \ddot{a}_x + \ddot{a}_y
$$

An income to $(y)$ only after $(x)$ has died is a reversionary annuity:

$$
\ddot{a}_{x|y} = \ddot{a}_y - \ddot{a}_{xy}
$$

A joint and survivor pension pays $A$ while both are alive and a share $s$ of it to the survivor:

$$
\text{EPV} = A\big(s \ddot{a}_{\overline{xy}} + (1-s) \ddot{a}_{xy}\big)
$$

The probability that $(x)$ dies before $(y)$ within $n$ years, with deaths uniformly distributed over each year of age:

$$
{}_nq_{\overset{1}{x}y} = \sum_{k=0}^{n-1} {}_kp_{xy} q_{x+k}\Big(1 - \tfrac{1}{2}q_{y+k}\Big)
$$

Mortality follows Makeham's law, $\mu_x = A + Bc^x$, with $A = 0.00022$, $B = 2.7 \times 10^{-6}$ and $c = 1.124$.

## What the calculator shows

A couple aged 65 and 62, an income of $20,000 a year, 60% to the survivor, and 5% interest:

| | Cost today |
|---|---|
| Joint and survivor pension (60%) | $286,717 |
| Income continues in full to the survivor | $316,151 |
| Income stops at the first death | $242,566 |
| Income to the younger life only after the older one dies | $45,155 |

The probability that the 65-year-old dies first is 58.6%. The single-life annuity factor at age 65 is 13.5498, which matches the published SOA Standard Ultimate Life Table value at 5%.

## Who is still here (SQL)

20,000 simulated couples aged 65 and 62 are followed for 30 years and stored in SQLite, one row per couple with the time each partner died. `sql/couple_study.sql` counts, for each year, the couples with both partners alive, the couples with at least one alive, and which partner died first. The data tracks the model closely:

| Measure | Observed | Model |
|---|---|---|
| Both alive after 10 years | 83.6% | 83.6% |
| Both alive after 20 years | 47.3% | 47.5% |
| At least one alive after 20 years | 90.6% | 90.6% |
| At least one alive after 29 years | 55.4% | 55.3% |
| The 65-year-old dies first within 30 years | 53.7% | 54.0% |

## A second opinion (Excel)

The workbook builds the couple's life table from the Makeham formula in spreadsheet cells, then the joint-life, last-survivor and reversionary annuities. It matches R to the cent for every cost and to four decimals for every annuity factor, reproduces the SOA table value of 13.5498 at age 65, and re-runs the couples study from the SQL results.

## Three chapters, one model

Two lives are also a multiple state model, with states *both alive*, *only one alive* and *both dead*. A test checks that the Chapter 1 Kolmogorov solver reproduces the joint-life and last-survivor probabilities.

## Key functions

| Function | What it does |
|---|---|
| `joint_survival()`, `last_survivor_survival()` | Survival of the joint and last-survivor statuses |
| `joint_annuity()`, `last_survivor_annuity()`, `reversionary_annuity()` | Annuities for the couple |
| `first_death_insurance()`, `second_death_insurance()` | Insurances on the first and second death |
| `contingent_first()` | Probability that one life dies before the other |
| `makeham_q()` | One-year death rates from Makeham's law |
| `simulate_couples()`, `compare_couples()` | Couples experience study |

---

[← Previous: Exits](02-exits.md) · [Overview](../../README.md) · **Chapter 3 of 7** · Next: The Long Wait (coming soon)
