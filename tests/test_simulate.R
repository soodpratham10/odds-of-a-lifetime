library(testthat)
source("../r/multistate.R")
source("../r/decrement.R")
source("../r/multilife.R")
source("../r/reserves.R")
source("../r/expenses.R")
source("../r/simulate_company.R")

test_that("sales fall when the price rises above fair", {
  expect_equal(sales_volume(1000, 1000), 5000)
  expect_equal(sales_volume(1200, 1000), round(5000 / 1.2^6))   # 1,674
  expect_true(sales_volume(900, 1000) > 5000)
})

test_that("year_share splits time in a state across policy years", {
  # healthy from 0 to 2.5: one full year, one full year, then half a year
  expect_equal(year_share(0, 2.5, 1, 0), 1)
  expect_equal(year_share(0, 2.5, 3, 0), 0.5)
  expect_equal(year_share(0, 2.5, 4, 0), 0)
  # with interest: integral of exp(d (1 - s)) from 0 to 1 = (exp(d) - 1) / d
  expect_equal(year_share(0, 5, 1, 0.05), (exp(0.05) - 1) / 0.05)
  # many customers at once: healthy for 0.5, 1.5 and 3 years, year 2
  expect_equal(year_share(0, c(0.5, 1.5, 3), 2, 0), c(0, 0.5, 1))
})

test_that("run_company matches the hand calculation", {
  p <- data.frame(year = 1:2, premiums = c(500, 0), expenses = c(100, 0),
                  claims = c(300, 50), net_flow = c(100, -50),
                  reserve = c(300, 0), in_force = c(10, 0))
  co <- run_company(list(p), capital = 1000, i_earn = 0.1)
  # A1 = 1000 * 1.1 + 100 = 1200;  A2 = 1200 * 1.1 - 50 = 1270
  expect_equal(co$assets, c(1200, 1270))
  expect_equal(co$surplus, c(900, 1270))
  expect_equal(co$profit, c(-100, 370))
  # interest: year 1 = 1200 - 1000 - (500 - 100 - 300) = 100; year 2 = 70 + 50 = 120
  expect_equal(co$interest, c(100, 120))
  expect_equal(co$status, c("Healthy", "Healthy"))
})

test_that("a company that falls below its reserves stays bankrupt", {
  p <- data.frame(year = 1:2, premiums = c(500, 0), expenses = c(100, 0),
                  claims = c(300, 50), net_flow = c(100, -50),
                  reserve = c(300, 0), in_force = c(10, 0))
  co <- run_company(list(p), capital = 100, i_earn = 0.1)
  # A1 = 110 + 100 = 210 < 300 reserve; A2 = 181 > 0 but the company is already shut
  expect_equal(co$status, c("Bankrupt", "Bankrupt"))
  # two identical products double everything
  co2 <- run_company(list(p, p), capital = 2000, i_earn = 0.1)
  expect_equal(co2$assets, 2 * c(1200, 1270))
})

test_that("term policies with no deaths or lapses: cash flows by hand", {
  q <- matrix(0, nrow = 3, ncol = 2)
  e <- expense_basis(init_pct = 0.5, renew_pct = 0.05, init_fixed = 10, renew_fixed = 2)
  s <- simulate_term(10, q, c(1000, 0), G = 100, expenses = e, i_val = 0.05, i_earn = 0.05)
  # year 1: 10 * (100 - 50 - 10) * 1.05 = 420; later: 10 * (100 - 5 - 2) * 1.05 = 976.5
  expect_equal(s$net_flow, c(420, 976.5, 976.5))
  expect_equal(s$claims, c(0, 0, 0))
  expect_equal(s$in_force, c(10, 10, 10))
  # with no claims possible, future premiums exceed future costs: reserves floor at 0
  expect_equal(s$reserve, c(0, 0, 0))
})

test_that("term simulation: deaths and lapses match the decrement table", {
  k <- 0:19
  q <- udd_single_to_multiple(cbind(0.003 * 1.07^k, ifelse(k == 0, 0.08, 0.04)))
  e <- expense_basis(init_pct = 0.5, renew_pct = 0.05, init_fixed = 150, renew_fixed = 40)
  G <- price_term(q, c(100000, 0), 0.04, e)$G
  expect_equal(G, 586.3491, tolerance = 1e-6)
  s <- simulate_term(20000, q, c(100000, 0), G, e, 0.04, 0.04, seed = 1)
  tab <- decrement_table(q, radix = 20000)
  exp_deaths <- sum(tab$d[, 1])          # about 1,402
  exp_lapses <- sum(tab$d[, 2])          # about 11,110
  expect_true(abs(sum(s$claims) / 100000 - exp_deaths) < 4 * sqrt(exp_deaths))
  expect_true(abs(20000 - s$in_force[20] - exp_deaths - exp_lapses) <
                4 * sqrt(exp_deaths + exp_lapses))
  expect_true(all(s$reserve >= 0))
})

# Disability income, own numbers
mu <- matrix(c(0, 0.03, 0.01,
               0, 0,    0.04,
               0, 0,    0), nrow = 3, byrow = TRUE)
e_di <- expense_basis(init_pct = 0.5, renew_pct = 0.05, init_fixed = 200, renew_fixed = 50)
pr <- price_disability(mu, 10, log(1.04), B = 10000, S = 20000, expenses = e_di)

test_that("disability: expenses raise the price above the net premium", {
  expect_true(pr$G > pr$net)
  # same net premium as in test_reserves.R, but at i = 4% (delta = log 1.04, not 0.04)
  expect_equal(pr$net, 1608.851, tolerance = 1e-5)
})

test_that("disability simulation at the fair price breaks even on average", {
  s <- simulate_disability(20000, mu, 10, 10000, 20000, pr$G, e_di, 0.04, 0.04, seed = 1)
  pv <- sum(s$net_flow * 1.04^-(1:10)) / 20000
  # within 4% of the EPV of premiums (random noise only)
  expect_true(abs(pv) < 0.04 * pr$G * pr$a_hh)
  expect_true(all(diff(s$in_force) <= 0))
  expect_true(all(s$reserve >= 0))
  expect_equal(s$in_force[10], 0)        # term over: nobody left on the books
})

test_that("the same seed gives the same simulation", {
  a <- simulate_disability(500, mu, 10, 10000, 20000, pr$G, e_di, 0.04, 0.04, seed = 7)
  b <- simulate_disability(500, mu, 10, 10000, 20000, pr$G, e_di, 0.04, 0.04, seed = 7)
  expect_equal(a, b)
})

test_that("couples simulation at the fair price breaks even on average", {
  qx <- makeham_q(68, 56)
  qy <- makeham_q(64, 56)
  e <- expense_basis(init_pct = 0.02, init_fixed = 500, renew_fixed = 50)
  pc <- price_couple(qx, qy, 0.045, 18000, 0.6, e)
  expect_equal(pc$G, 263490.49, tolerance = 1e-6)
  s <- simulate_couples(20000, qx, qy, 18000, 0.6, pc$G, e, 0.045, 0.045,
                        horizon = 56, seed = 1)
  pv <- sum(s$net_flow * 1.045^-(1:56)) / 20000
  expect_true(abs(pv) < 0.01 * pc$G)
  expect_equal(s$premiums[1], 20000 * pc$G)
  expect_true(all(s$reserve >= 0))
})
