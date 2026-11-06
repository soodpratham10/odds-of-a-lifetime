# Reserves: the money an insurer must hold today to meet its future promises.
# One reserve method for each product line in the game:
#   Chapter 1 (disability income)  -> Thiele's differential equations
#   Chapter 2 (term life, lapses)  -> year-by-year recursion
#   Chapter 3 (couples annuity)    -> year-by-year recursion by couple status
# Every reserve is prospective: EPV of future benefits minus EPV of future premiums.

# ---------- Chapter 1: Thiele's differential equations ----------
# For a life in state i at time t:
#   dV_i/dt = delta V_i + P_i - B_i - sum over j != i of mu_ij (S_ij + V_j - V_i)
# P_i: premium rate paid while in state i (per year)
# B_i: benefit rate paid while in state i (per year)
# S_ij: lump sum paid on a move from state i to state j
# Solved backwards from V(n) = 0 with Euler steps of size h.
# mu: a square matrix of constant intensities, or a function of t returning one.
# Returns a matrix V[step, state]; row 1 is time 0, row k is time (k - 1) * h.
thiele_reserves <- function(mu, n, delta, premium, benefit, lump = NULL, h = 0.01) {
  mu_fun <- if (is.function(mu)) mu else function(s) mu
  m <- nrow(mu_fun(0))
  if (is.null(lump)) lump <- matrix(0, m, m)
  stopifnot(length(premium) == m, length(benefit) == m, all(dim(lump) == m))
  n_steps <- round(n / h)
  stopifnot(h > 0, abs(n_steps * h - n) < 1e-9)
  V <- matrix(0, nrow = n_steps + 1, ncol = m)
  for (s in n_steps:1) {
    M <- mu_fun(s * h)
    diag(M) <- 0
    v <- V[s + 1, ]
    # entry [i, j] is S_ij + V_j - V_i
    jump <- lump + matrix(v, m, m, byrow = TRUE) - v
    dV <- delta * v + premium - benefit - rowSums(M * jump)
    V[s, ] <- v - h * dV
  }
  V
}

# Keep only whole years: rows for t = 0, 1, ..., n
thiele_yearly <- function(V, h = 0.01) {
  V[seq(1, nrow(V), by = round(1 / h)), , drop = FALSE]
}

# ---------- Chapter 2: term life with lapses ----------
# q: dependent rates, one row per year, one column per decrement (death, lapse).
# b: benefit paid at the end of the year for each decrement (0 for a lapse).
# premium: paid at the start of each year while in force. Either one level amount,
#   or one amount per year. To include expenses, pass the premium net of that
#   year's expenses (see premium_cashflows in expenses.R).
# Recursion: (tV + P_t)(1 + i) = sum_j q^(j) b_j + p^(tau) (t+1)V, with nV = 0.
# Returns tV for t = 0, 1, ..., n.
md_reserves <- function(q, b, premium, i) {
  q <- as.matrix(q)
  n <- nrow(q)
  premium <- rep_len(premium, n)
  v <- 1 / (1 + i)
  V <- numeric(n + 1)
  for (t in n:1) {
    V[t] <- v * (sum(q[t, ] * b) + (1 - sum(q[t, ])) * V[t + 1]) - premium[t]
  }
  V
}

# ---------- Chapter 3: couples annuity ----------
# Pays 'amount' at the start of each year while both are alive,
# and 'share' * amount while only one is alive. Lives are independent.
# qx, qy: one-year death rates from now (same length n).
# expense: paid at the start of each year while at least one is alive.
#   One amount, or one per year (use 0 in year 1 if initial costs are handled separately).
# Returns a matrix with rows t = 0, 1, ..., n and columns for the couple's status.
# Each value is the reserve at time t, just before that year's payment.
couple_reserves <- function(qx, qy, i, amount, share, expense = 0) {
  stopifnot(length(qx) == length(qy))
  n <- length(qx)
  expense <- rep_len(expense, n)
  v <- 1 / (1 + i)
  V <- matrix(0, nrow = n + 1, ncol = 3,
              dimnames = list(NULL, c("both", "x_only", "y_only")))
  for (t in n:1) {
    px <- 1 - qx[t]
    py <- 1 - qy[t]
    nxt <- V[t + 1, ]
    V[t, "x_only"] <- share * amount + expense[t] + v * px * nxt["x_only"]
    V[t, "y_only"] <- share * amount + expense[t] + v * py * nxt["y_only"]
    V[t, "both"] <- amount + expense[t] + v * (px * py * nxt["both"] +
                                  px * (1 - py) * nxt["x_only"] +
                                  (1 - px) * py * nxt["y_only"])
  }
  V
}
