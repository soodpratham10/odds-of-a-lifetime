[← Overview](../README.md)

# Getting started

Everything you need to run The Odds of a Lifetime on your own computer. If you just want to try it, the **[live calculator](https://soodpratham10.shinyapps.io/odds-of-a-lifetime/)** needs no installation.

## 1. Install the packages

```r
install.packages(c("testthat", "DBI", "RSQLite", "shiny"))
```

## 2. Run the tests

From the project folder in R:

```r
testthat::test_file("tests/test_multistate.R")
testthat::test_file("tests/test_experience.R")
testthat::test_file("tests/test_decrement.R")
testthat::test_file("tests/test_multilife.R")
```

Every file should report `FAIL 0`.

## 3. Build the experience database

The database file isn't stored in the repository. This rebuilds it from the simulation scripts:

```r
source("r/multistate.R"); source("r/decrement.R")
source("r/multilife.R"); source("r/experience.R")
db <- "sql/experience.sqlite"

# Chapter 1: lives moving between healthy, disabled and dead
mu_true <- matrix(c(0, 0.10, 0.05,
                    0, 0,    0.20,
                    0, 0,    0), nrow = 3, byrow = TRUE)
spells <- simulate_experience(mu_true, n = 20000, obs_years = 5, seed = 2026)
DBI::dbDisconnect(write_experience_db(spells, db))

# Chapter 2: term policies that die or lapse
k <- 0:19
q_true <- udd_single_to_multiple(cbind(0.002 * 1.08^k, ifelse(k == 0, 0.10, 0.05)))
DBI::dbDisconnect(write_policy_db(simulate_policies(q_true, n = 50000, seed = 2026), db))

# Chapter 3: couples aged 65 and 62
qx <- makeham_q(65, 30); qy <- makeham_q(62, 30)
couples <- simulate_couples(qx, qy, n = 20000, seed = 2026, age_x = 65, age_y = 62)
DBI::dbDisconnect(write_couple_db(couples, db))
```

## 4. Open the calculator

```r
shiny::runApp("app")
```

## How the pieces map to code

| Chapter | Engine | Experience data | Excel |
|---|---|---|---|
| [1. Detours](chapters/01-detours.md) | `r/multistate.R` | `r/experience.R`, `sql/schema.sql`, `sql/exposure.sql`, `sql/transitions.sql` | `excel/disability_death_crosscheck.xlsx` |
| [2. Exits](chapters/02-exits.md) | `r/decrement.R` | `r/experience.R`, `sql/policy_schema.sql`, `sql/exit_study.sql` | `excel/exits_crosscheck.xlsx` |
| [3. Two Lives](chapters/03-two-lives.md) | `r/multilife.R` | `r/experience.R`, `sql/couple_schema.sql`, `sql/couple_study.sql` | `excel/two_lives_crosscheck.xlsx` |

## Repository layout

```
r/          the engine, one file per chapter, plus the experience-data functions
sql/        database schemas and experience-study queries
excel/      one independent cross-check workbook per chapter
tests/      automated tests with hand-checked expected values
app/        the calculator
docs/       chapter pages, this guide and images
deploy.R    publishes the calculator to shinyapps.io
```

---

[← Overview](../README.md)
