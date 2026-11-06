# The game engine: sell a block of policies, then follow every customer year by year.
# Each product simulation returns one row per year with:
#   premiums, expenses, claims  money in and out during the year (face amounts)
#   net_flow                    the same flows, rolled up with interest to the end of the year
#   reserve                     reserves held at the end of the year for the whole block.
#                               A single policy can have a negative reserve (it is expected to
#                               pay in more than it costs), but the block's total is never
#                               allowed below zero: future profits cannot be counted as assets.
#   in_force                    customers still covered at the end of the year
#   events, expected_events     claim events in the year (new disability claims, or deaths)
#                               and how many the model expected: actual vs expected (A/E)
# Each table also carries attr(, "people"): one row per customer, for their life story.
# i_earn can be one rate or one rate per year. A shock (see make_shock) multiplies the
# real-world rates in one year, without changing the prices or reserves.
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

# ---------- Shocks: surprise events in one year ----------
# Multipliers on the real-world rates, by year. All 1 means no surprise.
#   death: death rates (all products)   disable: becoming disabled   lapse: lapse rates
make_shock <- function(horizon, year = NA, death = 1, disable = 1, lapse = 1) {
  s <- data.frame(year = seq_len(horizon), death = 1, disable = 1, lapse = 1)
  if (!is.na(year)) {
    s$death[year] <- death
    s$disable[year] <- disable
    s$lapse[year] <- lapse
  }
  s
}

# ---------- Chapter 1: disability income ----------
# States: 1 healthy, 2 disabled, 3 dead (no recovery), constant intensities.
# Lives are drawn one year at a time. Within a year the intensities are constant, so the
# time to the next move is exponential (and memoryless, so drawing year by year gives
# the same lives as drawing whole lifetimes, while allowing a shock in one year).
# i_val: interest rate for pricing and reserves. i_earn: the rate the company actually earns.
simulate_disability <- function(N, mu, n, B, S, G, expenses, i_val, i_earn,
                                horizon = n, seed = NULL, h = 0.01,
                                shock = make_shock(horizon)) {
  stopifnot(mu[2, 1] == 0)
  if (!is.null(seed)) set.seed(seed)
  e <- expenses
  i_earn <- rep_len(i_earn, horizon)
  last <- min(n, horizon)

  t_h <- rep(Inf, N)        # time the customer stops being healthy
  t_d <- rep(Inf, N)        # time of death
  dis <- rep(FALSE, N)      # TRUE: became disabled
  for (k in seq_len(last)) {
    m01 <- mu[1, 2] * shock$disable[k]
    m02 <- mu[1, 3] * shock$death[k]
    m12 <- mu[2, 3] * shock$death[k]
    # healthy at the start of the year: time to leave healthy
    hh <- which(is.infinite(t_h))
    w <- rexp(length(hh), m01 + m02)
    leave <- hh[w < 1]
    t_h[leave] <- k - 1 + w[w < 1]
    sick <- leave[runif(length(leave)) < m01 / (m01 + m02)]
    dis[sick] <- TRUE
    died_healthy <- setdiff(leave, sick)
    t_d[died_healthy] <- t_h[died_healthy]
    # disabled lives (already disabled, or just became disabled): time to death
    old <- which(dis & is.infinite(t_d) & t_h <= k - 1)
    who <- c(old, sick)
    from <- c(rep(k - 1, length(old)), t_h[sick])
    dd <- rexp(length(who), m12)
    die <- from + dd < k
    t_d[who[die]] <- from[die] + dd[die]
  }
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

  p_sick <- mu[1, 2] / (mu[1, 2] + mu[1, 3]) * (1 - exp(-(mu[1, 2] + mu[1, 3])))
  init_cost <- N * (e$init_fixed + e$init_pct * G)          # paid at time 0
  rows <- matrix(0, nrow = horizon, ncol = 8)
  for (k in seq_len(horizon)) {
    d_e <- log(1 + i_earn[k])
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
      first * (1 + i_earn[k]) - B * sum(td_i) - S * sum(exp(d_e * (k - t_d[died])))
    if (k <= n) {
      events <- sum(dis & t_h > k - 1 & t_h <= k)           # new disability claims
      expected <- sum(t_h > k - 1) * p_sick                 # healthy at start x P(sick in year)
    } else {
      events <- 0
      expected <- 0
    }
    if (k < n) {
      n_h <- sum(t_h > k)
      n_d <- sum(dis & t_h <= k & t_d > k)
      reserve <- max(n_h * V[k + 1, 1] + n_d * V[k + 1, 2], 0)
    } else {
      n_h <- 0
      n_d <- 0
      reserve <- 0
    }
    rows[k, ] <- c(premiums, expenses_k, claims, net, reserve, n_h + n_d, events, expected)
  }
  out <- as_year_table(rows)
  time_sick <- ifelse(dis, pmax(pmin(t_d, last) - pmin(t_h, last), 0), 0)
  attr(out, "people") <- data.frame(
    id = seq_len(N),
    sick_at = ifelse(dis & t_h <= last, t_h, NA),           # NA: never disabled
    died_at = ifelse(t_d <= last, t_d, NA),                 # NA: alive at the end
    premiums = G * pmin(t_h, last),
    benefits = B * time_sick + S * (t_d <= last)
  )
  out
}

# ---------- Chapter 2: term life with lapses ----------
# q: dependent rates (death, lapse) by policy year; b: benefit for each decrement,
# paid at the end of the year. Premiums and expenses are paid at the start of each year.
simulate_term <- function(N, q, b, G, expenses, i_val, i_earn,
                          horizon = nrow(q), seed = NULL, shock = make_shock(horizon)) {
  if (!is.null(seed)) set.seed(seed)
  q <- as.matrix(q)
  n <- nrow(q)
  e <- expenses
  i_earn <- rep_len(i_earn, horizon)
  V <- md_reserves(q, b, premium_cashflows(G, n, e), i_val)
  alive <- rep(TRUE, N)
  exit_year <- rep(NA, N)
  exit_how <- rep("still covered", N)
  paid <- numeric(N)
  rows <- matrix(0, nrow = horizon, ncol = 8)
  for (k in seq_len(horizon)) {
    if (k > n) next                                         # policy has ended
    n_k <- sum(alive)
    q_die <- min(q[k, 1] * shock$death[k], 1)
    q_lapse <- min(q[k, 2] * shock$lapse[k], 1 - q_die)
    u <- runif(N)
    die <- alive & u < q_die
    lapse <- alive & !die & u < q_die + q_lapse
    paid[alive] <- paid[alive] + G
    premiums <- G * n_k
    expenses_k <- if (k == 1) n_k * (e$init_pct * G + e$init_fixed) else
      n_k * (e$renew_pct * G + e$renew_fixed)
    claims <- b[1] * sum(die) + b[2] * sum(lapse)
    net <- (premiums - expenses_k) * (1 + i_earn[k]) - claims
    exit_year[die | lapse] <- k
    exit_how[die] <- "died"
    exit_how[lapse] <- "lapsed"
    alive <- alive & !die & !lapse
    rows[k, ] <- c(premiums, expenses_k, claims, net, sum(alive) * max(V[k + 1], 0),
                   sum(alive), sum(die), n_k * q[k, 1])
  }
  out <- as_year_table(rows)
  attr(out, "people") <- data.frame(
    id = seq_len(N), exit_year = exit_year, exit = exit_how, premiums = paid,
    benefits = ifelse(exit_how == "died", b[1], ifelse(exit_how == "lapsed", b[2], 0))
  )
  out
}

# ---------- Chapter 3: couples annuity ----------
# Single premium G per couple at the start. Pays 'amount' at the start of each year
# while both are alive and share * amount while one is alive.
# Expenses: init_fixed + init_pct G at the start; renew_fixed per year from year 2.
# qx, qy: death rates up to the end of the annuity (the reserves need the full length).
simulate_couples <- function(N, qx, qy, amount, share, G, expenses, i_val, i_earn,
                             horizon = 20, seed = NULL, shock = make_shock(horizon)) {
  if (!is.null(seed)) set.seed(seed)
  e <- expenses
  n <- length(qx)
  i_earn <- rep_len(i_earn, horizon)
  V <- couple_reserves(qx, qy, i_val, amount, share, expense = c(0, rep(e$renew_fixed, n - 1)))
  x_alive <- rep(TRUE, N)
  y_alive <- rep(TRUE, N)
  x_died <- rep(NA, N)
  y_died <- rep(NA, N)
  received <- numeric(N)
  rows <- matrix(0, nrow = horizon, ncol = 8)
  for (k in seq_len(horizon)) {
    if (k > n) next                                         # everyone has died
    both <- x_alive & y_alive
    one <- xor(x_alive, y_alive)
    received <- received + amount * both + share * amount * one
    claims <- amount * sum(both) + share * amount * sum(one)
    premiums <- if (k == 1) G * N else 0
    expenses_k <- if (k == 1) N * (e$init_pct * G + e$init_fixed) else
      e$renew_fixed * sum(both | one)
    net <- (premiums - expenses_k - claims) * (1 + i_earn[k])
    expected <- sum(x_alive) * qx[k] + sum(y_alive) * qy[k]
    x_dies <- x_alive & runif(N) < min(qx[k] * shock$death[k], 1)
    y_dies <- y_alive & runif(N) < min(qy[k] * shock$death[k], 1)
    x_died[x_dies] <- k
    y_died[y_dies] <- k
    x_alive <- x_alive & !x_dies
    y_alive <- y_alive & !y_dies
    r <- V[k + 1, ]
    reserve <- max(sum(x_alive & y_alive) * r["both"] +
                     sum(x_alive & !y_alive) * r["x_only"] +
                     sum(!x_alive & y_alive) * r["y_only"], 0)
    rows[k, ] <- c(premiums, expenses_k, claims, net, reserve, sum(x_alive | y_alive),
                   sum(x_dies) + sum(y_dies), expected)
  }
  out <- as_year_table(rows)
  attr(out, "people") <- data.frame(id = seq_len(N), x_died = x_died, y_died = y_died,
                                    premiums = G, benefits = received)
  out
}

# Turn the matrix of yearly results into a data frame
as_year_table <- function(m) {
  data.frame(year = seq_len(nrow(m)), premiums = m[, 1], expenses = m[, 2],
             claims = m[, 3], net_flow = m[, 4], reserve = m[, 5], in_force = m[, 6],
             events = m[, 7], expected_events = m[, 8])
}

# ---------- The company ----------
# products: a list of year tables (same number of years), from the functions above.
# capital: money the company starts with.
# i_earn: interest earned on its assets, one rate or one rate per year.
# Assets roll forward: A_k = A_{k-1} (1 + i_k) + net flows of year k.
# Surplus = assets - reserves. Status each year:
#   Bankrupt  assets below reserves (and the company stays shut from then on)
#   Warning   surplus below warning_level times reserves
#   Healthy   otherwise
run_company <- function(products, capital, i_earn, warning_level = 0.1) {
  cols <- c("premiums", "expenses", "claims", "net_flow", "reserve")
  tot <- Reduce(`+`, lapply(products, function(p) as.matrix(p[, cols])))
  years <- nrow(tot)
  i_earn <- rep_len(i_earn, years)
  assets <- numeric(years)
  prev <- capital
  for (k in seq_len(years)) {
    assets[k] <- prev * (1 + i_earn[k]) + tot[k, "net_flow"]
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
