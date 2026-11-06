library(testthat)
source("../r/multistate.R")
source("../r/decrement.R")
source("../r/multilife.R")
source("../r/reserves.R")

# ---------- Thiele (Chapter 1) ----------

test_that("Thiele: level premium equal to mu * S gives a zero reserve throughout", {
  # alive (1) -> dead (2) at constant force 0.02, sum insured 100,000.
  # The fair premium rate is 0.02 * 100,000 = 2,000, so dV/dt = 0 and V = 0.
  mu <- matrix(c(0, 0.02,
                 0, 0), nrow = 2, byrow = TRUE)
  lump <- matrix(c(0, 100000,
                   0, 0), nrow = 2, byrow = TRUE)
  V <- thiele_reserves(mu, n = 10, delta = 0.05, premium = c(2000, 0),
                       benefit = c(0, 0), lump = lump)
  expect_equal(nrow(V), 1001)
  expect_true(max(abs(V)) < 1e-6)
})

# Disability income: healthy (1), disabled (2), dead (3), no recovery.
mu_di <- matrix(c(0, 0.03, 0.01,
                  0, 0,    0.04,
                  0, 0,    0), nrow = 3, byrow = TRUE)
B <- 10000   # paid each year while disabled
S <- 20000   # paid on death from either state
n <- 10
delta <- 0.04
lump_di <- matrix(0, 3, 3)
lump_di[1, 3] <- S
lump_di[2, 3] <- S
P_di <- equivalence_premium(B * epv_annuity(mu_di, 1, 2, n, delta) +
                              S * epv_insurance(mu_di, 1, 3, n, delta),
                            mu_di, start = 1, premium_states = 1, n = n, delta = delta)
V_di <- thiele_reserves(mu_di, n, delta, premium = c(P_di, 0, 0),
                        benefit = c(0, B, 0), lump = lump_di)

test_that("Thiele: the healthy reserve at issue is zero at the equivalence premium", {
  a_hh <- epv_annuity(mu_di, 1, 1, n, delta)
  # within 0.1% of the EPV of premiums (two different numerical methods)
  expect_true(abs(V_di[1, 1]) < 0.001 * P_di * a_hh)
})

test_that("Thiele: the disabled reserve matches the closed form", {
  # Disabled lives only die, at force 0.04, so
  # V_2(t) = (B + 0.04 S) * (1 - exp(-(0.04 + delta)(n - t))) / (0.04 + delta)
  closed <- function(t) (B + 0.04 * S) * (1 - exp(-0.08 * (n - t))) / 0.08
  expect_equal(V_di[1, 2], closed(0), tolerance = 1e-3)      # about 74,340.59
  expect_equal(V_di[501, 2], closed(5), tolerance = 1e-3)
  expect_equal(V_di[nrow(V_di), 2], 0)
})

test_that("Thiele: the dead state holds no reserve and yearly rows are picked out", {
  expect_true(all(V_di[, 3] == 0))
  yearly <- thiele_yearly(V_di)
  expect_equal(nrow(yearly), n + 1)
  expect_equal(yearly[6, ], V_di[501, ])
})

# ---------- Recursion with decrements (Chapter 2) ----------

test_that("md_reserves matches the hand calculation", {
  # Two years: column 1 = death, column 2 = lapse. Death benefit 1,000, i = 5%.
  q <- rbind(c(0.01, 0.10),
             c(0.02, 0.05))
  b <- c(1000, 0)
  P <- md_premium(q, b, 0.05)
  # P = (10/1.05 + 0.89 * 20/1.05^2) / (1 + 0.89/1.05) = 13.89298
  expect_equal(P, 13.89298, tolerance = 1e-6)
  V <- md_reserves(q, b, P, 0.05)
  # 1V = 20/1.05 - P = 5.15464; 0V = 0 at the equivalence premium; 2V = 0
  expect_equal(V[2], 20 / 1.05 - P)
  expect_equal(V[1], 0, tolerance = 1e-9)
  expect_equal(V[3], 0)
})

test_that("md_reserves satisfies the recursion every year", {
  k <- 0:19
  q <- udd_single_to_multiple(cbind(0.003 * 1.07^k, ifelse(k == 0, 0.08, 0.04)))
  b <- c(100000, 0)
  i <- 0.04
  P <- md_premium(q, b, i)
  V <- md_reserves(q, b, P, i)
  lhs <- (V[1:20] + P) * (1 + i)
  rhs <- q[, 1] * b[1] + (1 - rowSums(q)) * V[2:21]
  expect_equal(lhs, rhs)
  expect_equal(V[1], 0, tolerance = 1e-6)
})

# ---------- Couples annuity (Chapter 3) ----------

test_that("couple_reserves matches the hand calculation", {
  # i = 0, income 1 while both alive, 0.5 to the survivor.
  qx <- c(0.1, 0.2)
  qy <- c(0.05, 0.1)
  V <- couple_reserves(qx, qy, i = 0, amount = 1, share = 0.5)
  # 0V = 1 + 0.9*0.95*1 + 0.9*0.05*0.5 + 0.1*0.95*0.5 = 1.925
  expect_equal(unname(V[1, "both"]), 1.925)
  expect_equal(unname(V[2, ]), c(1, 0.5, 0.5))
  expect_equal(unname(V[3, ]), c(0, 0, 0))
})

test_that("couple reserve at issue equals the cost of the joint and survivor pension", {
  qx <- makeham_q(70, 54)
  qy <- makeham_q(66, 54)
  V <- couple_reserves(qx, qy, i = 0.04, amount = 15000, share = 0.5)
  cost <- 15000 * (0.5 * last_survivor_annuity(qx, qy, 0.04) +
                   0.5 * joint_annuity(qx, qy, 0.04))
  expect_equal(unname(V[1, "both"]), cost)
  # a survivor alone needs less than the couple, and the reserve runs off to 0
  expect_true(V[11, "x_only"] < V[11, "both"])
  expect_equal(unname(V[55, "both"]), 0)
})
