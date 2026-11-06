library(testthat)
source("../r/decrement.R")
source("../r/multilife.R")
source("../r/reserves.R")
source("../r/expenses.R")

test_that("with no expenses the gross premium is the net premium", {
  expect_equal(gross_premium(1000, 8, expense_basis()), 1000 / 8)
})

test_that("gross premium matches the hand calculation", {
  # EPV benefits 1,000, annuity 8, so 7 renewal years in EPV terms.
  # G = (1000 + 100 + 20 * 7) / (8 - 0.5 - 0.05 * 7) = 1240 / 7.15 = 173.43
  e <- expense_basis(init_pct = 0.5, renew_pct = 0.05, init_fixed = 100, renew_fixed = 20)
  G <- gross_premium(1000, 8, e)
  expect_equal(G, 1240 / 7.15)
  # equivalence: EPV of premiums = EPV of benefits + EPV of expenses
  expect_equal(G * 8, 1000 + epv_expenses(G, 8, e))
})

test_that("single premium: only the initial percentage applies to the premium", {
  # G = (200000 + 500 + 50 * 12) / (1 - 0.02) = 205,204.08
  e <- expense_basis(init_pct = 0.02, init_fixed = 500, renew_fixed = 50)
  G <- gross_premium(200000, 1, e, first_year = 1, renewal_annuity = 12)
  expect_equal(G, 201100 / 0.98)
})

test_that("premium cash flows net of expenses", {
  e <- expense_basis(init_pct = 0.5, renew_pct = 0.05, init_fixed = 150, renew_fixed = 40)
  cf <- premium_cashflows(600, 3, e)
  # year 1: 600 * 0.5 - 150 = 150; later: 600 * 0.95 - 40 = 530
  expect_equal(cf, c(150, 530, 530))
})

# Term life with lapses, 20 years, death benefit 100,000, i = 4%
k <- 0:19
q <- udd_single_to_multiple(cbind(0.003 * 1.07^k, ifelse(k == 0, 0.08, 0.04)))
b <- c(100000, 0)
i <- 0.04
ann <- md_annuity_due(q, i)
e <- expense_basis(init_pct = 0.5, renew_pct = 0.05, init_fixed = 150, renew_fixed = 40)
G <- gross_premium(md_epv_benefits(q, b, i), ann, e)
P <- md_premium(q, b, i)

test_that("expenses raise the premium of the term policy", {
  expect_equal(G, 586.3491, tolerance = 1e-6)     # net premium is 478.45
  expect_true(G > P)
})

test_that("gross premium reserve is zero at issue and below the net premium reserve", {
  V_gross <- md_reserves(q, b, premium_cashflows(G, 20, e), i)
  V_net <- md_reserves(q, b, P, i)
  expect_equal(V_gross[1], 0, tolerance = 1e-6)
  # high first-year costs are paid back by later premiums, so the
  # gross premium reserve sits below the net premium reserve
  expect_true(all(V_gross[2:20] < V_net[2:20]))
  expect_equal(V_gross[21], 0)
})

test_that("couples annuity: single premium covers payments and expenses", {
  qx <- makeham_q(68, 56)
  qy <- makeham_q(64, 56)
  i <- 0.045
  cost <- 18000 * (0.6 * last_survivor_annuity(qx, qy, i) + 0.4 * joint_annuity(qx, qy, i))
  e <- expense_basis(init_pct = 0.02, init_fixed = 500, renew_fixed = 50)
  G <- gross_premium(cost, 1, e, first_year = 1,
                     renewal_annuity = last_survivor_annuity(qx, qy, i) - 1)
  V <- couple_reserves(qx, qy, i, amount = 18000, share = 0.6,
                       expense = c(0, rep(50, 55)))
  # what is left of G after the initial expenses is exactly the reserve needed
  expect_equal(G * (1 - 0.02) - 500, unname(V[1, "both"]))
})
