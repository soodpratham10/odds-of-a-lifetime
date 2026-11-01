[← Overview](../../README.md) · **Chapter 1 of 7** · [Next: Exits →](02-exits.md)

# Chapter 1: Detours

*A healthy person may become disabled, and a disabled person may die. The policy pays an income while they are disabled and a lump sum on death, and premiums stop while they are not healthy.*

| | |
|---|---|
| **Actuarial model** | Multiple state model: healthy, disabled, dead |
| **Engine** | [`r/multistate.R`](../../r/multistate.R) |
| **Experience data** | [`r/experience.R`](../../r/experience.R), [`sql/`](../../sql) |
| **Excel cross-check** | [`excel/disability_death_crosscheck.xlsx`](../../excel/disability_death_crosscheck.xlsx) |
| **Calculator** | [Chapter 1 tab, live](https://soodpratham10.shinyapps.io/odds-of-a-lifetime/) |

## What the engine does

- **Transition probabilities** for discrete-time Markov chains, homogeneous or not, with input validation
- **Kolmogorov's forward equations**, solved by Euler's method for any set of intensities, constant or varying with time
- **Annuities and insurances by state**: payments while in a state, or on entry into a state
- **Premiums** by the equivalence principle

## The mathematics

Notation follows Dickson, Hardy and Waters, *Actuarial Mathematics for Life Contingent Risks*.

The probability of being in state $j$ at age $x+t$, given state $i$ at age $x$, and the transition intensity from $i$ to $j$:

$$
{}_tp_x^{ij} = \Pr\big[\text{in state } j \text{ at age } x+t \mid \text{in state } i \text{ at age } x\big],
\qquad
\mu_x^{ij} = \lim_{h \to 0^+} \frac{{}_hp_x^{ij}}{h}
$$

Kolmogorov's forward equations: the probability of being in state $j$ grows with flow in and shrinks with flow out.

$$
\frac{d}{dt}{}_tp_x^{ij} = \sum_{k \neq j} \Big( {}_tp_x^{ik}\mu_{x+t}^{kj} - {}_tp_x^{ij}\mu_{x+t}^{jk} \Big)
$$

These are solved with Euler's method, using the generator matrix $\mathbf{Q}$ (intensities off the diagonal, minus the row sums on it):

$$
\mathbf{P}(t+h) \approx \mathbf{P}(t) + h\mathbf{P}(t)\mathbf{Q}(t)
$$

Annuity while in state $j$, and insurance on entry into state $j$, over $n$ years at force of interest $\delta$:

$$
\bar{a}_{x:\overline{n}|}^{ij} = \int_0^n e^{-\delta t} {}_tp_x^{ij} dt
$$

$$
\bar{A}_{x:\overline{n}|}^{ij} = \int_0^n e^{-\delta t} \sum_{k \neq j} {}_tp_x^{ik}\mu_{x+t}^{kj} dt
$$

Premium paid while healthy, for $D$ per year while disabled and $B$ on death:

$$
P = \frac{D\bar{a}_{x:\overline{n}|}^{01} + B\bar{A}_{x:\overline{n}|}^{02}}{\bar{a}_{x:\overline{n}|}^{00}}
$$

For constant intensities there are exact answers, which the tests and the Excel workbook compare against:

$$
{}_tp_x^{00} = e^{-(\mu^{01}+\mu^{02})t},
\qquad
{}_tp_x^{01} = \frac{\mu^{01}}{\mu^{12}-\mu^{01}-\mu^{02}}\Big(e^{-(\mu^{01}+\mu^{02})t} - e^{-\mu^{12}t}\Big)
$$

## Where the odds come from (SQL)

Synthetic policyholders are simulated moving between states and stored in SQLite as one row per spell (a stretch of time in one state). With $D^{ij}$ transitions from $i$ to $j$ and $T^{i}$ total years spent in state $i$:

$$
\hat{\mu}^{ij} = \frac{D^{ij}}{T^{i}},
\qquad
\text{Var}\big(\hat{\mu}^{ij}\big) \approx \frac{D^{ij}}{\big(T^{i}\big)^2}
$$

`sql/transitions.sql` counts the transitions and `sql/exposure.sql` sums the exposure. With 20,000 simulated lives observed for 5 years, every true value falls inside its 95% interval:

| Transition | True value | Estimate | 95% interval |
|---|---|---|---|
| Healthy to disabled | 0.10 | 0.1001 | 0.0977 to 0.1024 |
| Death while healthy | 0.05 | 0.0512 | 0.0495 to 0.0528 |
| Death while disabled | 0.20 | 0.2010 | 0.1937 to 0.2084 |

The calculator can load these estimates with one click.

## A second opinion (Excel)

The workbook rebuilds Chapter 1 in spreadsheet formulas only: an Euler sheet, a closed-form sheet, and an experience sheet that re-estimates the intensities from the SQL results. R and Excel agree to the cent, and both are within 0.03% of the exact answer (the gap is the Euler step error):

| | R | Excel (Euler) | Exact |
|---|---|---|---|
| Annual premium | $2,433.23 | $2,433.23 | $2,432.57 |
| EPV of disability benefit | $15,960.66 | $15,960.66 | $15,955.76 |
| EPV of death benefit | $8,313.12 | $8,313.12 | $8,312.26 |

## Key functions

| Function | What it does |
|---|---|
| `kstep_probs()` | k-step transition probabilities |
| `make_generator()` | Generator matrix from the intensities |
| `kolmogorov_path()`, `euler_kolmogorov()` | Forward equations by Euler's method |
| `epv_annuity()` | Annuity while in a state |
| `epv_insurance()` | Insurance on entry into a state |
| `equivalence_premium()` | Level premium by the equivalence principle |
| `simulate_experience()`, `estimate_intensities()` | Simulated experience and occurrence-exposure estimates |

---

[← Overview](../../README.md) · **Chapter 1 of 7** · [Next: Exits →](02-exits.md)
