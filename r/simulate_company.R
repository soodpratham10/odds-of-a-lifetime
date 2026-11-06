# The game engine: sell a block of policies, then follow every customer year by year.
# Each product simulation returns one row per year with:
#   premiums, expenses, claims  money in and out during the year (face amounts)
#   net_flow                    the same flows, rolled up with interest to the end of the year
#   reserve                     reserves held at the end of the year (never below zero)
#   in_force                    customers still covered at the end of the year
# run_company() then adds the products together with the company's capital.
# Needs multistate.R, decrement.R, multilife.R, reserves.R and expenses.R.

# ---------- Pricing: the fair gross premium for each product ----------

# Disability income (Chapter 1): premiums paid continuously while healthy.
# Expenses: init_pct of one year's premium and init_fixed at issue;
# renew_pct of every premium; renew_fixed per year while alive (healthy or disabled).
#   G a_HH = EPV benefits + init_fixed + init_pct G + renew_pct G a_HH + renew_fixed a_alive
price_disability <- function(mu, n, delta, B, S, expenses, h = 0.01) {
  e <- expenses
  a_hh <- epv_annuity(mu, 1, 1, n, delta, h)
  a_hd <- epv_annuity(mu, 1, 2, n, delta, h)
  epv_b <- B * a_hd + S * epv_insurance(mu, 1, 3, n, delta, h)
  denom <- a_hh * (1 - e$renew_pct) - e$init_pct
  stopifnot(denom > 0)
  G <- (epv_b + e$init_fixed + e$renew_fixed * (a_hh + a_hd)) / denom
  list(G = G, net = epv_b / a_hh, a_hh = a_hh, epv_benefits = epv_b)
}

# Term life with lapses (Chapter 2): annual premiums in advance
price_term <- function(q, b, i, expenses) {
  epv_b <- md_epv_benefits(q, b, i)
  a <- md_annuity_due(q, i)
  list(G = gross_premium(epv_b, a, expenses), net = epv_b / a,
       a = a, epv_benefits = epv_b)
}

# Couples annuity (Chapter 3): one single premium at the start
price_couple <- function(qx, qy, i, amount, share, expenses) {
  a_ls <- last_survivor_annuity(qx, qy, i)
  cost <- amount * (share * a_ls + (1 - share) * joint_annuity(qx, qy, i))
  list(G = gross_premium(cost, 1, expenses, first_year = 1, renewal_annuity = a_ls - 1),
       net = cost, epv_benefits = cost)
}

# How many customers buy: base number at the fair price, fewer if dearer, more if cheaper.
sales_volume <- function(G, fair, base = 5000, elasticity = 6) {
  round(base * (fair / G)^elasticity)
}

# ---------- Helper: time spent in a state during policy year k ----------
# For time in state from lo to hi, the part inside year k (from k - 1 to k),
# each unit of time rolled up with interest to the end of year k:
#   integral of exp(delta (k - s)) ds over that part. With delta = 0 it is just the time.
year_share <- function(lo, hi, k, delta) {
  len <- max(length(lo), length(hi))
  a <- rep_len(pmax(lo, k - 1), len)
  b <- rep_len(pmin(hi, k), len)
  out <- numeric(len)
  ok <- b > a
  if (delta == 0) {
    out[ok] <- b[ok] - a[ok]
  } else {
    out[ok] <- (exp(delta * (k - a[ok])) - exp(delta * (k - b[ok]))) / delta
  }
  out
}

# ---------- Chapter 1: disability income ----------
# States: 1 healthy, 2 disabled, 3 dead (no recovery), constant intensities.
# Each customer's times are drawn exactly: time healthy ~ exponential(mu12 + mu13),
# then disabled with probability mu12 / (mu12 + mu13), then time disabled ~ exponential(mu23).
# i_val: interest rate for pricing and reserves. i_earn: the rate the company actually earns.
simulate_disability <- function(N, mu, n, B, S, G, expenses, i_val, i_earn,
                                horizon = n, seed = NULL, h = 0.01) {
  stopifnot(mu[2, 1] == 0)
  if (!is.null(seed)) set.seed(seed)
  e <- expenses
  out_rate <- mu[1, 2] + mu[1, 3]
  t_h <- rexp(N, out_rate)                                  # leaves healthy
  dis <- runif(N) < mu[1, 2] / out_rate                     # TRUE: became disabled
  t_d <- ifelse(dis, t_h + rexp(N, mu[2, 3]), t_h)          # time of death
  h_end <- pmin(t_h, n)
  d_end <- pmin(t_d, n)

  # Reserves per policy, on the pricing basis, with expenses
  lump <- matrix(0, 3, 3)
  lump[1, 3] <- S
  lump[2, 3] <- S
  V <- thiele_yearly(thiele_reserves(mu, n, log(1 + i_val),
                                     premium = c(G * (1 - e$renew_pct) - e$renew_fixed, 0, 0),
                                     benefit = c(0, B + e$renew_fixed, 0),
                                     lump = lump, h = h), h)

  d_e <- log(1 + i_earn)
  init_cost <- N * (e$init_fixed + e$init_pct * G)          # paid at time 0
  rows <- matrix(0, nrow = horizon, ncol = 6)
  for (k in seq_len(horizon)) {
    th <- year_share(0, h_end, k, 0)                        # time healthy in year k
    td <- ifelse(dis, year_share(h_end, d_end, k, 0), 0)    # time disabled in year k
    th_i <- year_share(0, h_end, k, d_e)                    # the same, with interest
    td_i <- ifelse(dis, year_share(h_end, d_end, k, d_e), 0)
    died <- t_d > k - 1 & t_d <= k & t_d <= n
    first <- if (k == 1) init_cost else 0
    premiums <- G * sum(th)
    expenses_k <- e$renew_pct * premiums + e$renew_fixed * (sum(th) + sum(td)) + first
    claims <- B * sum(td) + S * sum(died)
    net <- G * (1 - e$renew_pct) * sum(th_i) - e$renew_fixed * (sum(th_i) + sum(td_i)) -
      first * (1 + i_earn) - B * sum(td_i) - S * sum(exp(d_e * (k - t_d[died])))
    if (k < n) {
      n_h <- sum(t_h > k)
      n_d <- sum(dis & t_h <= k & t_d > k)
      reserve <- n_h * max(V[k + 1, 1], 0) + n_d * max(V[k + 1, 2], 0)
    } else {
      n_h <- 0
      n_d <- 0
      reserve <- 0
    }
    rows[k, ] <- c(premiums, expenses_k, claims, net, reserve, n_h + n_d)
  }
  as_year_table(rows)
}

# ---------- Chapter 2: term life with lapses ----------
# q: dependent rates (death, lapse) by policy year; b: benefit for each decrement,
# paid at the end of the year. Premiums and expenses are paid at the start of each year.
simulate_term <- function(N, q, b, G, expenses, i_val, i_earn,
                          horizon = nrow(q), seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  q <- as.matrix(q)
  n <- nrow(q)
  e <- expenses
  V <- md_reserves(q, b, premium_cashflows(G, n, e), i_val)
  alive <- rep(TRUE, N)
  rows <- matrix(0, nrow = horizon, ncol = 6)
  for (k in seq_len(horizon)) {
    if (k > n) next                                         # policy has ended
    n_k <- sum(alive)
    u <- runif(N)
    die <- alive & u < q[k, 1]
    lapse <- alive & !die & u < q[k, 1] + q[k, 2]
    premiums <- G * n_k
    expenses_k <- if (k == 1) n_k * (e$init_pct * G + e$init_fixed) else
      n_k * (e$renew_pct * G + e$renew_fixed)
    claims <- b[1] * sum(die) + b[2] * sum(lapse)
    net <- (premiums - expenses_k) * (1 + i_earn) - claims
    alive <- alive & !die & !lapse
    rows[k, ] <- c(premiums, expenses_k, claims, net, sum(alive) * max(V[k + 1], 0), sum(alive))
  }
  as_year_table(rows)
}

# ---------- Chapter 3: couples annuity ----------
# Single premium G per couple at the start. Pays 'amount' at the start of each year
# while both are alive and share * amount while one is alive.
# Expenses: init_fixed + init_pct G at the start; renew_fixed per year from year 2.
# qx, qy: death rates up to the end of the annuity (the reserves need the full length).
simulate_couples <- function(N, qx, qy, amount, share, G, expenses, i_val, i_earn,
                             horizon = 20, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  e <- expenses
  n <- length(qx)
  V <- couple_reserves(qx, qy, i_val, amount, share, expense = c(0, rep(e$renew_fixed, n - 1)))
  x_alive <- rep(TRUE, N)
  y_alive <- rep(TRUE, N)
  rows <- matrix(0, nrow = horizon, ncol = 6)
  for (k in seq_len(horizon)) {
    if (k > n) next                                         # everyone has died
    both <- x_alive & y_alive
    one <- xor(x_alive, y_alive)
    claims <- amount * sum(both) + share * amount * sum(one)
    premiums <- if (k == 1) G * N else 0
    expenses_k <- if (k == 1) N * (e$init_pct * G + e$init_fixed) else
      e$renew_fixed * sum(both | one)
    net <- (premiums - expenses_k - claims) * (1 + i_earn)
    x_alive <- x_alive & runif(N) >= qx[k]
    y_alive <- y_alive & runif(N) >= qy[k]
    r <- V[k + 1, ]
    reserve <- sum(x_alive & y_alive) * max(r["both"], 0) +
      sum(x_alive & !y_alive) * max(r["x_only"], 0) +
      sum(!x_alive & y_alive) * max(r["y_only"], 0)
    rows[k, ] <- c(premiums, expenses_k, claims, net, reserve, sum(x_alive | y_alive))
  }
  as_year_table(rows)
}

# Turn the matrix of yearly results into a data frame
as_year_table <- function(m) {
  data.frame(year = seq_len(nrow(m)), premiums = m[, 1], expenses = m[, 2],
             claims = m[, 3], net_flow = m[, 4], reserve = m[, 5], in_force = m[, 6])
}

# ---------- The company ----------
# products: a list of year tables (same number of years), from the functions above.
# capital: money the company starts with. i_earn: interest earned on its assets.
# Assets roll forward: A_k = A_{k-1} (1 + i_earn) + net flows of year k.
# Surplus = assets - reserves. Status each year:
#   Bankrupt  assets below reserves (and the company stays shut from then on)
#   Warning   surplus below warning_level times reserves
#   Healthy   otherwise
run_company <- function(products, capital, i_earn, warning_level = 0.1) {
  cols <- c("premiums", "expenses", "claims", "net_flow", "reserve")
  tot <- Reduce(`+`, lapply(products, function(p) as.matrix(p[, cols])))
  years <- nrow(tot)
  assets <- numeric(years)
  prev <- capital
  for (k in seq_len(years)) {
    assets[k] <- prev * (1 + i_earn) + tot[k, "net_flow"]
    prev <- assets[k]
  }
  surplus <- assets - tot[, "reserve"]
  status <- ifelse(surplus < 0, "Bankrupt",
                   ifelse(surplus < warning_level * tot[, "reserve"], "Warning", "Healthy"))
  first_bust <- match("Bankrupt", status)
  if (!is.na(first_bust)) status[first_bust:years] <- "Bankrupt"
  cash <- tot[, "premiums"] - tot[, "expenses"] - tot[, "claims"]
  data.frame(year = seq_len(years),
             premiums = tot[, "premiums"], expenses = tot[, "expenses"],
             claims = tot[, "claims"],
             interest = assets - c(capital, assets[-years]) - cash,
             reserve = tot[, "reserve"], assets = assets, surplus = surplus,
             profit = surplus - c(capital, surplus[-years]),
             status = status, row.names = NULL)
}
