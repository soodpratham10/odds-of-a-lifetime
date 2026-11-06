# Expenses and gross premiums.
# Real policies cost money to sell and to run. The gross premium is the premium the
# customer actually pays: enough to cover the benefits AND the expenses.

# An expense basis:
#   init_pct    share of the first year's premium (for example commission), at issue
#   renew_pct   share of each premium after the first year
#   init_fixed  fixed cost per policy at issue (underwriting, setting up the policy)
#   renew_fixed fixed cost per policy per year from year 2 (administration)
expense_basis <- function(init_pct = 0, renew_pct = 0, init_fixed = 0, renew_fixed = 0) {
  stopifnot(init_pct >= 0, renew_pct >= 0, init_fixed >= 0, renew_fixed >= 0)
  list(init_pct = init_pct, renew_pct = renew_pct,
       init_fixed = init_fixed, renew_fixed = renew_fixed)
}

# Gross premium by the equivalence principle:
#   G * a = EPV benefits + init_fixed + renew_fixed * a_renew
#           + init_pct * G * a_first + renew_pct * G * (a - a_first)
# so G = (EPV benefits + init_fixed + renew_fixed * a_renew)
#        / (a - init_pct * a_first - renew_pct * (a - a_first))
# prem_annuity (a): EPV of 1 per year paid at the premium dates.
# first_year (a_first): the part of a that falls in the first year
#   (1 for annual premiums in advance; for a single premium use a = 1 and a_first = 1).
# renewal_annuity (a_renew): EPV of 1 per year from year 2 while the policy is in force
#   (for annual premiums in advance this is a - 1, the default).
gross_premium <- function(epv_benefits, prem_annuity, expenses, first_year = 1,
                          renewal_annuity = prem_annuity - first_year) {
  e <- expenses
  denom <- prem_annuity - e$init_pct * first_year - e$renew_pct * (prem_annuity - first_year)
  stopifnot(denom > 0)
  (epv_benefits + e$init_fixed + e$renew_fixed * renewal_annuity) / denom
}

# EPV of the expenses alone, for a premium G (annual premiums in advance by default)
epv_expenses <- function(G, prem_annuity, expenses, first_year = 1,
                         renewal_annuity = prem_annuity - first_year) {
  e <- expenses
  e$init_fixed + e$renew_fixed * renewal_annuity +
    G * (e$init_pct * first_year + e$renew_pct * (prem_annuity - first_year))
}

# Premium net of expenses at the start of each year, for annual premiums in advance:
#   year 1:     G (1 - init_pct)  - init_fixed
#   years 2..n: G (1 - renew_pct) - renew_fixed
# Pass this to md_reserves to get gross premium reserves.
premium_cashflows <- function(G, n, expenses) {
  e <- expenses
  c(G * (1 - e$init_pct) - e$init_fixed,
    rep(G * (1 - e$renew_pct) - e$renew_fixed, n - 1))
}
