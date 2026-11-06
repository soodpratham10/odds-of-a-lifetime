library(shiny)

# Load the tested engine whether the app runs from app/ or the project root
find_file <- function(...) {
  for (p in c(file.path("..", ...), file.path(...))) if (file.exists(p)) return(p)
  NA
}
source(find_file("r", "multistate.R"))
source(find_file("r", "decrement.R"))
source(find_file("r", "multilife.R"))
source(find_file("r", "experience.R"))
source(find_file("r", "reserves.R"))
source(find_file("r", "expenses.R"))
source(find_file("r", "simulate_company.R"))

# Load experience data from SQLite, if the database has been built
est <- NULL            # Chapter 1: estimated intensities
study <- NULL          # Chapter 2: exit study by policy year
couple_study <- NULL   # Chapter 3: couples study by year
db_path <- find_file("sql", "experience.sqlite")
if (!is.na(db_path)) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  tabs <- DBI::dbListTables(con)
  if ("spell" %in% tabs)  est <- estimate_intensities(query_experience(con), 3)
  if ("policy" %in% tabs) study <- estimate_decrement_rates(query_exit_study(con))
  if ("couple" %in% tabs) couple_study <- query_couple_study(con)
  DBI::dbDisconnect(con)
}

money <- function(x) paste0("$", formatC(x, format = "f", big.mark = ",", digits = 2))
pct <- function(x) sprintf("%.1f%%", 100 * x)
note <- p(em("Illustrative assumptions only. Not calibrated to real data and not a pricing basis."))

# ---------- Chapter 1: Detours (multiple state model) ----------
tab_disability <- tabPanel("Chapter 1: Detours",
                           sidebarLayout(
                             sidebarPanel(
                               h4("Transition intensities (per year)"),
                               sliderInput("mu01", "Healthy to disabled", min = 0, max = 0.30,
                                           value = 0.02, step = 0.001),
                               sliderInput("mu02", "Death while healthy", min = 0, max = 0.10,
                                           value = 0.01, step = 0.001),
                               sliderInput("mu12", "Death while disabled", min = 0, max = 0.30,
                                           value = 0.05, step = 0.001),
                               if (!is.null(est)) actionButton("use_est",
                                                               "Use intensities estimated from experience data"),
                               h4("Economics and term"),
                               sliderInput("delta", "Force of interest", min = 0, max = 0.10,
                                           value = 0.05, step = 0.005),
                               sliderInput("n", "Policy term (years)", min = 5, max = 40,
                                           value = 20, step = 1),
                               h4("Benefits"),
                               numericInput("di", "Disability benefit (per year while disabled)",
                                            value = 12000, min = 0, step = 1000),
                               numericInput("db", "Death benefit (paid on death)",
                                            value = 50000, min = 0, step = 5000)
                             ),
                             mainPanel(
                               p(em("A healthy person may become disabled, and a disabled person may die.
            The policy pays an income while disabled and a lump sum on death.")),
                               h3("Results"),
                               tableOutput("results"),
                               h3("Where a healthy policyholder is over time"),
                               plotOutput("probs", height = "350px"),
                               if (!is.null(est)) tagList(
                                 h3("Intensities estimated from experience data (SQLite)"),
                                 tableOutput("est_table")
                               ),
                               p(em("Premiums are paid continuously while healthy and set by the equivalence principle.")),
                               note
                             )
                           )
)

# ---------- Chapter 2: Exits (multiple decrement model) ----------
tab_lapse <- tabPanel("Chapter 2: Exits",
                      sidebarLayout(
                        sidebarPanel(
                          h4("Term insurance"),
                          sliderInput("dl_n", "Policy term (years)", min = 5, max = 30, value = 20, step = 1),
                          numericInput("dl_b", "Death benefit (paid at end of year of death)",
                                       value = 250000, min = 0, step = 10000),
                          sliderInput("dl_i", "Annual interest rate", min = 0, max = 0.10,
                                      value = 0.05, step = 0.005),
                          h4("Mortality (independent rate)"),
                          sliderInput("dl_q0", "Year 1 death rate", min = 0.0005, max = 0.02,
                                      value = 0.002, step = 0.0005),
                          sliderInput("dl_g", "Annual increase in death rate", min = 0, max = 0.12,
                                      value = 0.08, step = 0.005),
                          h4("Lapses (independent rate)"),
                          sliderInput("dl_l1", "Year 1 lapse rate", min = 0, max = 0.30,
                                      value = 0.10, step = 0.01),
                          sliderInput("dl_lu", "Lapse rate after year 1", min = 0, max = 0.15,
                                      value = 0.05, step = 0.005)
                        ),
                        mainPanel(
                          p(em("A term policy ends in one of three ways: the policyholder dies, walks away,
            or reaches the end of the term. How many leave each way changes the price.")),
                          h3("Results"),
                          tableOutput("dl_results"),
                          h3("What happens to 1,000 policies"),
                          plotOutput("dl_plot", height = "350px"),
                          if (!is.null(study)) tagList(
                            h3("Experience study (SQLite): actual vs expected"),
                            p(em("50,000 simulated policies, counted by policy year in SQL, compared with the
              assumptions currently set on the sliders. An A/E ratio near 100% means the
              assumption fits the data.")),
                            tableOutput("dl_ae"),
                            plotOutput("dl_study_plot", height = "300px")
                          ),
                          p(em("Death and lapse rates are entered as independent (single decrement) rates and
            converted to dependent rates assuming a uniform distribution of each decrement
            within the year. Premiums are paid at the start of each year while in force.
            No cash value is paid on lapse.")),
                          note
                        )
                      )
)

# ---------- Chapter 3: Two Lives (multiple life model) ----------
tab_couple <- tabPanel("Chapter 3: Two Lives",
                       sidebarLayout(
                         sidebarPanel(
                           h4("The couple"),
                           sliderInput("tl_x", "Age of first life (x)", min = 50, max = 85, value = 65, step = 1),
                           sliderInput("tl_y", "Age of second life (y)", min = 50, max = 85, value = 62, step = 1),
                           h4("The pension"),
                           numericInput("tl_amt", "Annual income (paid at the start of each year)",
                                        value = 20000, min = 0, step = 1000),
                           sliderInput("tl_share", "Survivor's share after the first death", min = 0, max = 1,
                                       value = 0.6, step = 0.05),
                           sliderInput("tl_i", "Annual interest rate", min = 0, max = 0.10,
                                       value = 0.05, step = 0.005)
                         ),
                         mainPanel(
                           p(em("A couple retires on a promise: an income while both are alive, and part of it
            for whoever survives. Their lifetimes, and which one goes first, set the cost.")),
                           h3("Results"),
                           tableOutput("tl_results"),
                           h3("What happens to the couple over time"),
                           plotOutput("tl_plot", height = "350px"),
                           if (!is.null(couple_study)) tagList(
                             h3("Couples experience study (SQLite): observed vs model"),
                             p(em("20,000 simulated couples aged 65 and 62, followed for 30 years and counted in SQL,
              compared with the model at the ages currently set on the sliders. At 65 and 62
              the model should match the data; other ages show how far a wrong assumption drifts.")),
                             tableOutput("tl_study_table"),
                             plotOutput("tl_study_plot", height = "300px")
                           ),
                           p(em("Both lives follow Makeham mortality with the parameters of the SOA Standard
            Ultimate Life Table, and their future lifetimes are assumed independent.
            Annuities are paid at the start of each year, up to age 120 for the younger life.")),
                           note
                         )
                       )
)



# =====================================================================
# THE GAME: Lifetime Mutual
# =====================================================================

# Money in millions with one decimal, e.g. $902,594 -> $0.9M, -4,100,000 -> -$4.1M
money_m <- function(x) {
  sprintf("%s$%.1fM", ifelse(x < 0, "-", ""), abs(x) / 1e6)
}
# Whole dollars, e.g. 15400.4 -> $15,400
money0 <- function(x) paste0("$", formatC(x, format = "f", digits = 0, big.mark = ","))

# ---------- Game settings ----------
I_PRICE <- 0.05          # interest rate used for pricing and reserves
HORIZON <- 20            # years the game runs
CAPITAL_SHARE <- 0.20    # starting capital: 20% of the fair premiums of the business
ELASTICITY <- 4          # how strongly sales react to price
OUTLOOK <- c("Low (3%)" = 0.03, "Expected (5%)" = 0.05, "High (6.5%)" = 0.065)

# Costs of doing business (facts of the market, not choices)
e_std <- expense_basis(init_pct = 0.5, renew_pct = 0.05, init_fixed = 200, renew_fixed = 50)
e_annuity <- expense_basis(init_pct = 0.02, init_fixed = 500, renew_fixed = 50)

# Product assumptions (the same defaults as the chapter calculators)
mu_game <- matrix(c(0, 0.02, 0.01,
                    0, 0,    0.05,
                    0, 0,    0), nrow = 3, byrow = TRUE)
k_term <- 0:19
q_game <- udd_single_to_multiple(cbind(0.002 * 1.08^k_term, ifelse(k_term == 0, 0.10, 0.05)))
qx_game <- makeham_q(65, 58)
qy_game <- makeham_q(62, 58)

pr_di <- price_disability(mu_game, 20, log(1 + I_PRICE), B = 12000, S = 50000, expenses = e_std)
pr_term <- price_term(q_game, c(250000, 0), I_PRICE, e_std)
pr_couple <- price_couple(qx_game, qy_game, I_PRICE, 20000, 0.6, e_annuity)

products <- list(
  di = list(name = "Disability Income", chapter = "Chapter 1: Detours", icon = "\U0001F3E5",
            blurb = "Pays $12,000 a year while a customer is too sick to work, and $50,000 if they die. 20 years.",
            unit = "a year", base = 5000,
            fair = pr_di$G, epv_prem = pr_di$G * pr_di$a_hh),
  term = list(name = "Term Life", chapter = "Chapter 2: Exits", icon = "\U0001F6E1",
              blurb = "Pays a family $250,000 if the customer dies within 20 years. Customers can walk away at any time.",
              unit = "a year", base = 5000,
              fair = pr_term$G, epv_prem = pr_term$G * pr_term$a),
  couple = list(name = "Couples Annuity", chapter = "Chapter 3: Two Lives", icon = "\U0001F491",
                blurb = "A couple aged 65 and 62 pays once. You pay them $20,000 a year for life, and 60% to whoever lives longer.",
                unit = "once", base = 500,
                fair = pr_couple$G, epv_prem = pr_couple$G)
)

starting_capital <- function(chosen) {
  CAPITAL_SHARE * sum(sapply(products[chosen], function(prod) prod$base * prod$epv_prem))
}

# ---------- Hard mode: one surprise event ----------
SHOCKS <- list(
  pandemic = list(death = 3, disable = 1, lapse = 1, crash = FALSE,
                  headline = "PANDEMIC: death rates triple this year",
                  why = "a pandemic tripled death rates. Bad for Term Life and death benefits, but good for the annuity, which stops paying when people die."),
  sickness = list(death = 1, disable = 3, lapse = 1, crash = FALSE,
                  headline = "SICKNESS WAVE: three times as many people too ill to work",
                  why = "a sickness wave tripled new disability claims, and each one pays out for years."),
  lapses = list(death = 1, disable = 1, lapse = 4, crash = FALSE,
                headline = "CUSTOMERS FLEE: a rival cuts prices and lapses quadruple",
                why = "a rival's price cut made four times as many Term Life customers walk away."),
  crash = list(death = 1, disable = 1, lapse = 1, crash = TRUE,
               headline = "MARKET CRASH: interest rates fall 3 points for good",
               why = "a market crash cut the interest you earn by 3 points for the rest of the game.")
)

# Sell the policies, live through the years, and add everything up.
# The game number is the random seed, so the same number replays the same luck.
run_game <- function(chosen, price_pct, outlook, seed, hard = FALSE) {
  set.seed(seed)
  i_path <- rep(outlook, HORIZON)
  shock_tab <- make_shock(HORIZON)
  shock <- NULL
  if (hard) {
    # only surprises that can affect the products on sale
    available <- c("pandemic", "crash", if ("di" %in% chosen) "sickness",
                   if ("term" %in% chosen) "lapses")
    type <- sample(available, 1)
    yr <- sample(5:14, 1)
    s <- SHOCKS[[type]]
    shock_tab <- make_shock(HORIZON, year = yr, death = s$death, disable = s$disable,
                            lapse = s$lapse)
    if (s$crash) i_path[yr:HORIZON] <- pmax(outlook - 0.03, 0.005)
    shock <- list(type = type, year = yr, headline = s$headline, why = s$why)
  }
  tabs <- list()
  info <- list()
  for (id in chosen) {
    prod <- products[[id]]
    G <- prod$fair * price_pct[[id]] / 100
    N <- sales_volume(G, prod$fair, base = prod$base, elasticity = ELASTICITY)
    tabs[[id]] <- switch(id,
      di = simulate_disability(N, mu_game, 20, 12000, 50000, G, e_std,
                               I_PRICE, i_path, horizon = HORIZON, shock = shock_tab),
      term = simulate_term(N, q_game, c(250000, 0), G, e_std,
                           I_PRICE, i_path, horizon = HORIZON, shock = shock_tab),
      couple = simulate_couples(N, qx_game, qy_game, 20000, 0.6, G, e_annuity,
                                I_PRICE, i_path, horizon = HORIZON, shock = shock_tab))
    info[[id]] <- list(G = G, N = N, pct = price_pct[[id]])
  }
  capital <- starting_capital(chosen)
  res <- list(co = run_company(tabs, capital, i_path), tabs = tabs, info = info,
              capital = capital, i_path = i_path, outlook = outlook, shock = shock,
              hard = hard)
  res$stories <- pick_stories(res)
  res
}

# ---------- Customer stories ----------
yr_of <- function(t) ceiling(t)      # a time of 6.3 years happens in year 7

pick_stories <- function(res) {
  cand <- list()
  add <- function(key, text) cand[[key]] <<- text
  pick <- function(ids) if (length(ids) == 1) ids else sample(ids, 1)
  if (!is.null(res$tabs$di)) {
    pe <- attr(res$tabs$di, "people")
    sick <- which(!is.na(pe$sick_at))
    if (length(sick) > 0) {
      r <- pe[pick(sick), ]
      ending <- if (!is.na(r$died_at)) paste0(" and died in year ", yr_of(r$died_at),
                                              ". Their family received $50,000.")
                else " and was still too ill to work when the policy ended."
      add("di_a", paste0("\U0001F3E5 Customer #", r$id, " (Disability Income) got sick in year ",
                         yr_of(r$sick_at), ending, " They paid you ", money0(r$premiums),
                         " in premiums; you paid them ", money0(r$benefits),
                         ". This is what insurance is for."))
    }
    well <- which(is.na(pe$sick_at) & is.na(pe$died_at))
    if (length(well) > 0) {
      r <- pe[pick(well), ]
      add("di_b", paste0("\U0001F3C3 Customer #", r$id, " (Disability Income) stayed healthy for all ",
                         HORIZON, " years and never claimed. Their ", money0(r$premiums),
                         " in premiums helped pay for the customers who did get sick."))
    }
  }
  if (!is.null(res$tabs$term)) {
    pe <- attr(res$tabs$term, "people")
    died <- which(pe$exit == "died")
    if (length(died) > 0) {
      r <- pe[pick(died), ]
      add("term_a", paste0("\U0001F56F Customer #", r$id, " (Term Life) died in year ", r$exit_year,
                           ". They had paid ", money0(r$premiums), ", and their family received ",
                           money0(r$benefits), "."))
    }
    lapsed <- which(pe$exit == "lapsed")
    if (length(lapsed) > 0) {
      r <- pe[pick(lapsed), ]
      add("term_b", paste0("\U0001F6AA Customer #", r$id, " (Term Life) walked away in year ", r$exit_year,
                           " after paying ", money0(r$premiums),
                           ". No payout. The price already assumed some customers would leave."))
    }
  }
  if (!is.null(res$tabs$couple)) {
    pe <- attr(res$tabs$couple, "people")
    one <- which(xor(is.na(pe$x_died), is.na(pe$y_died)))
    if (length(one) > 0) {
      r <- pe[pick(one), ]
      who <- if (!is.na(r$x_died)) "the older partner (65)" else "the younger partner (62)"
      yr <- if (!is.na(r$x_died)) r$x_died else r$y_died
      add("couple_a", paste0("\U0001F491 Couple #", r$id, " (Couples Annuity): ", who, " died in year ", yr,
                             ". The survivor kept getting 60%, $12,000 a year. You paid them ",
                             money0(r$benefits), " in total against one premium of ", money0(r$premiums), "."))
    }
    both <- which(is.na(pe$x_died) & is.na(pe$y_died))
    if (length(both) > 0) {
      r <- pe[pick(both), ]
      add("couple_b", paste0("\U0001F475 Couple #", r$id, " (Couples Annuity) are both still alive after ",
                             HORIZON, " years. You've paid them ", money0(r$benefits),
                             " so far, and the payments carry on."))
    }
  }
  order <- c("di_a", "term_a", "couple_a", "di_b", "term_b", "couple_b")
  unname(unlist(cand[intersect(order, names(cand))]))[seq_len(min(3, length(cand)))]
}

# ---------- The Daily Actuary: headlines for one year ----------
headlines_for_year <- function(res, k) {
  co <- res$co
  out <- character(0)
  if (!is.null(res$shock) && res$shock$year == k) out <- c(out, paste("\u26A1", res$shock$headline))
  if (co$status[k] == "Bankrupt") out <- c(out, "\U0001F534 LIFETIME MUTUAL COLLAPSES: regulator steps in")
  if (co$status[k] == "Warning" && (k == 1 || co$status[k - 1] == "Healthy"))
    out <- c(out, "\U0001F7E1 Regulator raises concerns over Lifetime Mutual's thin surplus")
  if (k > 1 && co$status[k] == "Healthy" && co$status[k - 1] == "Warning")
    out <- c(out, "\U0001F7E2 Lifetime Mutual back on solid ground")
  if (k == 1) {
    n_all <- sum(sapply(res$info, function(x) x$N))
    out <- c(out, paste0("Lifetime Mutual opens its doors: ", formatC(n_all, format = "d", big.mark = ","),
                         " customers sign up"))
  }
  ae_line <- function(tab, high, low) {
    e <- tab$expected_events[k]
    if (e < 5) return(character(0))
    ae <- tab$events[k] / e
    if (ae >= 1.12) return(sprintf(high, round(100 * (ae - 1))))
    if (ae <= 0.88) return(sprintf(low, round(100 * (1 - ae))))
    character(0)
  }
  if (!is.null(res$tabs$di))
    out <- c(out, ae_line(res$tabs$di, "Bad year for Disability Income: new claims %d%% above expected",
                          "Healthy year: new disability claims %d%% below expected"))
  if (!is.null(res$tabs$term))
    out <- c(out, ae_line(res$tabs$term, "Term Life hit hard: deaths %d%% above expected",
                          "Lucky year for Term Life: deaths %d%% below expected"))
  if (!is.null(res$tabs$couple))
    out <- c(out, ae_line(res$tabs$couple, "Annuity book gains: deaths among couples %d%% above expected",
                          "Couples living longer: deaths %d%% below expected, so annuity costs rise"))
  if (length(out) == 0) {
    out <- if (co$profit[k] >= 0) paste0("Quiet year: Lifetime Mutual makes ", money_m(co$profit[k]))
           else paste0("Quiet year, but Lifetime Mutual loses ", money_m(-co$profit[k]))
  }
  out
}

# ---------- Report card ----------
report_card <- function(res, final_year) {
  co <- res$co
  final <- co[final_year, ]
  bank <- res$capital * prod(1 + res$i_path[seq_len(final_year)])
  pcts <- sapply(res$info, function(x) x$pct)
  if (final$status == "Bankrupt") {
    grade <- "F"
    title <- "\U0001F4A5 The Cautionary Tale"
    gain <- NA
  } else {
    gain <- final$surplus - bank
    ratio <- gain / res$capital
    grade <- if (ratio >= 0.5) "A" else if (ratio >= 0.15) "B" else if (ratio >= -0.05) "C" else "D"
    title <- if (all(abs(pcts - 100) <= 3)) "\U0001F981 The Steady Hand"
             else if (any(pcts < 97)) "\U0001F3B0 The Gambler"
             else if (all(pcts >= 115)) "\U0001F422 Too Careful"
             else "\U0001F4BC The Profit Maker"
  }
  helped <- 0
  if (!is.null(res$tabs$di)) {
    pe <- attr(res$tabs$di, "people")
    helped <- helped + sum((!is.na(pe$sick_at) & pe$sick_at <= final_year) |
                             (!is.na(pe$died_at) & pe$died_at <= final_year))
  }
  if (!is.null(res$tabs$term)) {
    pe <- attr(res$tabs$term, "people")
    helped <- helped + sum(pe$exit == "died" & pe$exit_year <= final_year)
  }
  if (!is.null(res$info$couple)) helped <- helped + res$info$couple$N
  list(grade = grade, title = title, gain = gain, bank = bank, final = final,
       paid = sum(co$claims[seq_len(final_year)]), helped = helped,
       customers = sum(sapply(res$info, function(x) x$N)),
       storm = res$hard && final$status != "Bankrupt")
}

status_colour <- c(Healthy = "#2a9d8f", Warning = "#e9a23b", Bankrupt = "#e63946")
status_icon <- c(Healthy = "\U0001F7E2", Warning = "\U0001F7E1", Bankrupt = "\U0001F534")
grade_colour <- c(A = "#2a9d8f", B = "#52b788", C = "#e9a23b", D = "#f4845f", F = "#e63946")

card <- function(...) div(class = "game-card", ...)

game_head <- tags$head(
  tags$link(rel = "stylesheet",
            href = "https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&family=Nunito:wght@400;700&display=swap"),
  tags$script(src = "https://cdn.jsdelivr.net/npm/canvas-confetti@1.9.3/dist/confetti.browser.min.js"),
  tags$script(HTML("
    Shiny.addCustomMessageHandler('confetti', function(x) {
      if (typeof confetti !== 'function') return;
      confetti({ particleCount: 180, spread: 90, origin: { y: 0.6 } });
      setTimeout(function() { confetti({ particleCount: 120, spread: 120, origin: { y: 0.5 } }); }, 400);
    });
  ")),
  tags$style(HTML("
    body { background: #f7f5ef; }
    h1, h2, h3, h4 { font-family: 'Fredoka', sans-serif; }
    .game-card { border: none; border-radius: 16px; padding: 18px 22px; margin-bottom: 16px;
                 background: #ffffff; box-shadow: 0 2px 10px rgba(0,0,0,0.06); }
    .game-hero { text-align: center; padding: 50px 10px 30px 10px; }
    .game-hero h1 { font-size: 3em; margin-bottom: 0.3em; }
    .game-hero p { font-size: 1.15em; max-width: 640px; margin: 0 auto 1em auto; }
    .locked { opacity: 0.5; }
    .meter { color: white; border-radius: 16px; padding: 14px 22px; font-size: 1.25em;
             margin-bottom: 14px; font-family: 'Fredoka', sans-serif; }
    .progress-track { background: rgba(255,255,255,0.3); border-radius: 8px; height: 10px; margin-top: 10px; }
    .progress-fill { background: white; border-radius: 8px; height: 10px; transition: width 0.4s; }
    .newspaper { background: #fffdf6; border: 2px solid #2b2b2b; border-radius: 6px; padding: 14px 18px;
                 font-family: Georgia, 'Times New Roman', serif; min-height: 330px; }
    .newspaper .masthead { text-align: center; border-bottom: 3px double #2b2b2b; margin-bottom: 10px;
                           font-size: 1.6em; font-weight: bold; letter-spacing: 1px; }
    .newspaper .dateline { text-align: center; font-size: 0.85em; font-style: italic; margin-bottom: 8px; }
    .newspaper .lead { font-size: 1.35em; font-weight: bold; line-height: 1.25; margin-bottom: 8px; }
    .newspaper .sub { font-size: 1em; margin-bottom: 4px; }
    .newspaper .earlier { border-top: 1px solid #999; margin-top: 10px; padding-top: 6px; font-size: 0.85em; color: #555; }
    .report { border-radius: 16px; padding: 20px 24px; margin-top: 10px; background: white;
              box-shadow: 0 2px 10px rgba(0,0,0,0.08); border-left: 10px solid #ccc; }
    .grade { font-family: 'Fredoka', sans-serif; font-size: 4em; line-height: 1; color: white;
             width: 1.6em; height: 1.6em; border-radius: 50%; display: flex; align-items: center;
             justify-content: center; }
    .big-number { font-size: 1.6em; font-weight: bold; }
    .story { background: #f1f7f6; border-radius: 12px; padding: 12px 16px; margin-bottom: 10px; }
    .shelf .checkbox { background: white; border-radius: 16px; padding: 14px 18px; margin-bottom: 12px;
                       box-shadow: 0 2px 10px rgba(0,0,0,0.06); }
    .shelf .checkbox label { width: 100%; }
    .btn { border-radius: 10px; margin: 3px; }
    .navbar .nav-link.active, .navbar .nav-link:focus { color: #ffffff !important; font-weight: 700;
                                                        border-bottom: 3px solid #ffffff; }
    .chart-key { font-size: 0.85em; color: #555; margin-top: 6px; text-align: center; }
    .key-item { white-space: nowrap; display: inline-block; }
    .key-line { display: inline-block; width: 22px; height: 4px; vertical-align: middle;
                margin: 0 6px 0 14px; border-radius: 2px; }
    .key-box { display: inline-block; width: 22px; height: 12px; vertical-align: middle;
               margin: 0 6px 0 14px; background: rgba(42,157,143,0.2); }
    .report-top { display: flex; gap: 24px; align-items: flex-start; }
    .grade { flex: 0 0 auto; }
  "))
)

screen_welcome <- tabPanelBody("welcome",
  div(class = "game-hero",
      h1("\U0001F3E2 Lifetime Mutual"),
      p(strong("You've just been made Chief Actuary.")),
      p("Choose which insurance products to sell and set their prices. Then live through
        the next 20 years with thousands of customers: some get sick, some die, some walk away,
        and interest rates may not be kind."),
      p("Price too low and the company goes bankrupt. Price too high and nobody buys."),
      actionButton("go_shelf", "Start \u25B6", class = "btn-primary btn-lg"),
      br(), br(),
      p(em("An actuary works out what future promises cost today, using probability and interest.
           That's the whole game."))
  )
)

screen_shelf <- tabPanelBody("shelf",
  h2("1. Choose what to sell"),
  p("Each product is one chapter of the project. Pick one or more."),
  div(class = "shelf",
      checkboxGroupInput("chosen", NULL, width = "100%",
        choiceNames = unname(lapply(products, function(prod) tagList(
          strong(paste(prod$icon, prod$name)), tags$small(paste0("  (", prod$chapter, ")")), br(),
          prod$blurb))),
        choiceValues = names(products),
        selected = names(products))
  ),
  div(class = "game-card locked", strong("\U0001F512 Company Pension (Chapter 4)"), br(),
      "Run an employer's pension plan. Coming next."),
  div(class = "game-card locked", strong("\U0001F512 Flexible Life (Chapter 6)"), br(),
      "Customers choose what they pay. Coming later."),
  div(class = "game-card locked", strong("\U0001F512 Guaranteed Product (Chapter 7)"), br(),
      "A promise with a hidden cost. Coming later."),
  actionButton("back_welcome", "\u25C0 Back"),
  actionButton("go_pricing", "Next: set prices \u25B6", class = "btn-primary")
)

screen_pricing <- tabPanelBody("pricing",
  h2("2. Set your prices"),
  uiOutput("capital_note"),
  uiOutput("price_panels"),
  card(
    h4("\U0001F4C8 Interest rates over the next 20 years"),
    p("You priced everything assuming your investments earn 5% a year. What actually happens?"),
    radioButtons("outlook", NULL, choices = names(OUTLOOK), selected = "Expected (5%)", inline = TRUE)
  ),
  card(
    h4("\u26A1 Hard mode"),
    checkboxInput("hard", "Add one surprise event somewhere between years 5 and 14
                  (a pandemic, a sickness wave, customers fleeing or a market crash)", value = FALSE),
    p(em("Real insurers test their prices against shocks like these. That's called a stress test."))
  ),
  card(
    h4("\U0001F3B2 Game number (optional)"),
    p("Leave this blank for brand-new luck. To replay someone's game with exactly the same
      customer lives, enter their game number and use the same products, prices, interest and hard mode."),
    numericInput("game_no", NULL, value = NA, min = 1, max = 99999, step = 1, width = "200px")
  ),
  card(
    h4("\U0001F9FE Your costs"),
    p("Agents take 50% of the first year's premium and 5% after that. Each policy costs $200 to set up
      and $50 a year to run. The annuity costs 2% of its premium plus $500 to set up, then $50 a year.
      The fair price already includes these.")
  ),
  actionButton("back_shelf", "\u25C0 Back"),
  actionButton("run", "Run the 20 years \u25B6", class = "btn-primary btn-lg")
)

screen_years <- tabPanelBody("years",
  h2("3. The next 20 years"),
  uiOutput("meter"),
  fluidRow(
    column(7, card(plotOutput("company_plot", height = "330px"),
                   div(class = "chart-key",
                       span(class = "key-item", span(class = "key-line", style = "background:#2a9d8f;"),
                            "Assets (colour = health)"),
                       span(class = "key-item", span(class = "key-line", style = "background:#264653;"),
                            "Reserves"),
                       span(class = "key-item", span(class = "key-box"), "Gap = surplus")))),
    column(5, uiOutput("newspaper"))
  ),
  uiOutput("verdict"),
  br(),
  actionButton("skip", "Skip to the end \u23E9"),
  actionButton("reroll", "Same prices, different luck \U0001F3B2"),
  actionButton("again", "Change my prices \u21A9"),
  actionButton("play_again", "Play again \U0001F504", class = "btn-primary"),
  h4("The company's accounts"),
  p(em("All amounts for the year. Reserves are the money that must be set aside for future promises;
       surplus is what's left over.")),
  tableOutput("year_table")
)

tab_game <- tabPanel("\U0001F3AE The Game",
  game_head,
  tabsetPanel(id = "screen", type = "hidden",
              screen_welcome, screen_shelf, screen_pricing, screen_years)
)

tab_how <- tabPanel("\U0001F4D6 How it works",
  h3("The maths behind the game"),
  p("Every number in the game comes from the same tested R engine. The fair price is set by the
    equivalence principle: the expected present value of premiums equals the expected present value
    of benefits plus expenses. Each customer's life is then simulated at random, and the company holds
    reserves (Thiele's equation for disability, the recursion for term life and the annuity)."),
  p("Below are the calculators from the project, one per chapter. Change an assumption and see what
    happens to the price."),
  tabsetPanel(tab_disability, tab_lapse, tab_couple),
  p(a("See the code and the maths on GitHub", href = "https://github.com/soodpratham10/odds-of-a-lifetime",
      target = "_blank"))
)

game_server <- function(input, output, session) {
  go <- function(screen) updateTabsetPanel(session, "screen", selected = screen)
  observeEvent(input$go_shelf, go("shelf"))
  observeEvent(input$back_welcome, go("welcome"))
  observeEvent(input$back_shelf, go("shelf"))
  observeEvent(input$go_pricing, {
    if (length(input$chosen) == 0) {
      showNotification("Pick at least one product to sell.", type = "warning")
    } else {
      go("pricing")
    }
  })

  output$capital_note <- renderUI({
    req(input$chosen)
    card(p("The board gives you ", span(class = "big-number", money_m(starting_capital(input$chosen))),
           " of starting capital for these products. Fair prices are worked out for you.
           Move a slider to charge more or less than fair."))
  })

  output$price_panels <- renderUI({
    req(input$chosen)
    lapply(input$chosen, function(id) {
      prod <- products[[id]]
      card(
        h4(paste(prod$icon, prod$name)),
        sliderInput(paste0("price_", id), "Your price, as a % of the fair price",
                    min = 70, max = 150, value = 100, step = 1, post = "%", width = "100%"),
        uiOutput(paste0("price_info_", id))
      )
    })
  })

  for (id in names(products)) local({
    pid <- id
    output[[paste0("price_info_", pid)]] <- renderUI({
      prod <- products[[pid]]
      pct_val <- input[[paste0("price_", pid)]]
      req(pct_val)
      G <- prod$fair * pct_val / 100
      N <- sales_volume(G, prod$fair, base = prod$base, elasticity = ELASTICITY)
      tagList(
        p(strong(paste0("Price: ", money(G), " ", prod$unit)),
          paste0("   (fair price ", money(prod$fair), ")")),
        p(paste0("Expected customers: ", formatC(N, format = "d", big.mark = ","),
                 if (pct_val > 100) " (fewer buy when you charge more)"
                 else if (pct_val < 100) " (more buy when you charge less)" else ""))
      )
    })
  })

  rv <- reactiveValues(res = NULL, year = 0, running = FALSE, prices = NULL, game_no = NULL)

  # The game number is the random seed: same number + same choices = same lives
  start_run <- function(game_no) {
    rv$game_no <- game_no
    rv$res <- run_game(rv$prices$chosen, rv$prices$pct, OUTLOOK[[input$outlook]],
                       seed = game_no, hard = isTRUE(input$hard))
    rv$year <- 0
    rv$running <- TRUE
    go("years")
  }

  observeEvent(input$run, {
    g <- input$game_no
    if (is.null(g) || is.na(g)) {
      g <- sample.int(99999, 1)
    } else if (g < 1 || g > 99999 || g != round(g)) {
      showNotification("A game number is a whole number from 1 to 99,999.", type = "warning")
      return()
    }
    pct_list <- lapply(input$chosen, function(id) {
      v <- input[[paste0("price_", id)]]
      if (is.null(v)) 100 else v
    })
    names(pct_list) <- input$chosen
    rv$prices <- list(chosen = input$chosen, pct = pct_list)
    withProgress(message = "Simulating thousands of lives...", start_run(as.integer(g)))
  })
  observeEvent(input$reroll, {
    req(rv$prices)
    withProgress(message = "Simulating thousands of lives...", start_run(sample.int(99999, 1)))
  })
  observeEvent(input$again, go("pricing"))
  observeEvent(input$play_again, {
    rv$running <- FALSE
    rv$res <- NULL
    rv$year <- 0
    updateNumericInput(session, "game_no", value = NA)
    go("shelf")
  })

  # How far the story can go: the last year, or the year the company went bankrupt
  last_year <- reactive({
    req(rv$res)
    co <- rv$res$co
    bust <- match("Bankrupt", co$status)
    if (is.na(bust)) nrow(co) else bust
  })

  # The end of the game: stop the clock, and celebrate if the company survived
  finish <- function() {
    rv$year <- last_year()
    rv$running <- FALSE
    if (rv$res$co$status[rv$year] != "Bankrupt") session$sendCustomMessage("confetti", list())
  }

  observeEvent(input$skip, {
    req(rv$res, rv$running)
    finish()
  })

  # Reveal one year at a time
  observe({
    req(rv$running)
    invalidateLater(500)
    isolate({
      if (rv$year < last_year()) rv$year <- rv$year + 1
      if (rv$year >= last_year()) finish()
    })
  })

  shown <- reactive({
    req(rv$res, rv$year > 0)
    rv$res$co[seq_len(rv$year), ]
  })

  output$meter <- renderUI({
    req(rv$res)
    if (rv$year == 0) {
      status <- "Start"
      colour <- "#457b9d"
      text <- paste0("Game #", rv$game_no, "  |  Year 0: you start with ", money_m(rv$res$capital))
    } else {
      row <- shown()[rv$year, ]
      status <- row$status
      colour <- status_colour[[status]]
      text <- paste0("Game #", rv$game_no, "  |  ", status_icon[[status]], "  Year ", row$year,
                     " of ", HORIZON, ": ", status, "  |  Surplus ", money_m(row$surplus),
                     "  |  Reserves ", money_m(row$reserve))
    }
    div(class = "meter", style = paste0("background:", colour, ";"),
        text,
        div(class = "progress-track",
            div(class = "progress-fill", style = paste0("width:", round(100 * rv$year / HORIZON), "%;"))))
  })

  output$company_plot <- renderPlot({
    req(rv$res)
    co <- rv$res$co
    top <- max(c(rv$res$capital, co$assets, co$reserve)) * 1.05
    bottom <- min(0, co$assets[seq_len(last_year())])
    par(mar = c(4, 5, 1, 1), bg = "white")
    plot(NA, xlim = c(0, HORIZON), ylim = c(bottom, top) / 1e6,
         xlab = "Year", ylab = "$ millions", las = 1, bty = "n")
    abline(h = 0, col = "grey80")
    if (!is.null(rv$res$shock)) {
      abline(v = rv$res$shock$year - 0.5, col = "grey60", lty = 2)
      text(rv$res$shock$year - 0.5, top / 1e6, "surprise", pos = 4, cex = 0.8, col = "grey40")
    }
    if (rv$year > 0) {
      k <- 0:rv$year
      a <- c(rv$res$capital, co$assets[seq_len(rv$year)]) / 1e6
      r <- c(0, co$reserve[seq_len(rv$year)]) / 1e6
      polygon(c(k, rev(k)), c(a, rev(r)), col = adjustcolor("#2a9d8f", 0.12), border = NA)
      lines(k, r, lwd = 3, col = "#264653")
      # the assets line changes colour with the company's health
      for (j in seq_len(rv$year)) {
        segments(j - 1, a[j], j, a[j + 1], lwd = 4, col = status_colour[[co$status[j]]])
      }
    }
  })

  output$newspaper <- renderUI({
    req(rv$res)
    if (rv$year == 0) {
      lead <- "Lifetime Mutual names a new Chief Actuary"
      subs <- character(0)
      earlier <- character(0)
    } else {
      today <- headlines_for_year(rv$res, rv$year)
      lead <- today[1]
      subs <- today[-1]
      prev <- if (rv$year > 1) rev(seq_len(rv$year - 1)) else integer(0)
      prev <- head(prev, 4)
      earlier <- vapply(prev, function(k) paste0("Year ", k, ": ", headlines_for_year(rv$res, k)[1]),
                        character(1))
    }
    div(class = "newspaper",
        div(class = "masthead", "THE DAILY ACTUARY"),
        div(class = "dateline", paste0("Year ", rv$year, " \u00B7 Game #", rv$game_no)),
        div(class = "lead", lead),
        lapply(subs, function(s) div(class = "sub", paste("\u2022", s))),
        if (length(earlier) > 0) div(class = "earlier", strong("Earlier"),
                                     lapply(earlier, function(s) div(s))))
  })

  output$verdict <- renderUI({
    req(rv$res, !rv$running, rv$year > 0)
    res <- rv$res
    rc <- report_card(res, rv$year)
    reasons <- lapply(names(res$info), function(id) {
      inf <- res$info[[id]]
      nm <- products[[id]]$name
      cust <- formatC(inf$N, format = "d", big.mark = ",")
      if (inf$pct < 97) {
        paste0(nm, ": priced ", 100 - inf$pct, "% below fair, so each policy loses money on average, and the low price brought in ",
               cust, " customers.")
      } else if (inf$pct > 103) {
        paste0(nm, ": priced ", inf$pct - 100, "% above fair, so each policy makes money on average, but only ",
               cust, " customers bought.")
      } else {
        paste0(nm, ": priced at fair, so it breaks even on average (", cust, " customers). Any gain or loss here is luck.")
      }
    })
    if (res$outlook < I_PRICE) {
      reasons[[length(reasons) + 1]] <- paste0("Interest: you earned ", res$outlook * 100,
        "% instead of the 5% you priced with, so investment income fell short every year.")
    } else if (res$outlook > I_PRICE) {
      reasons[[length(reasons) + 1]] <- paste0("Interest: you earned ", res$outlook * 100,
        "% instead of 5%, a tailwind every year.")
    }
    if (!is.null(res$shock) && res$shock$year <= rv$year) {
      reasons[[length(reasons) + 1]] <- paste0("\u26A1 Surprise in year ", res$shock$year, ": ", res$shock$why)
    }
    if (rc$final$status == "Bankrupt") {
      headline <- h3(paste0("\u274C Bankrupt in year ", rc$final$year))
      score <- p("The company could no longer cover its promises to customers.")
    } else {
      headline <- h3(paste0("\u2705 Survived all ", HORIZON, " years"))
      score <- p(HTML(paste0("Final surplus <strong>", money_m(rc$final$surplus),
                             "</strong>. Left in the bank, the starting capital would have grown to ",
                             money_m(rc$bank), ", so the business ",
                             if (rc$gain >= 0) "added " else "cost ",
                             "<span class='big-number'>", money_m(abs(rc$gain)), "</span>.")))
    }
    div(class = "report", style = paste0("border-left-color:", grade_colour[[rc$grade]], ";"),
        div(class = "report-top",
          div(class = "grade", style = paste0("background:", grade_colour[[rc$grade]], ";"),
              rc$grade),
          div(headline, h4(rc$title),
                 if (rc$storm) p(strong("\u26C8 Badge: Storm Survivor."), " You came through a surprise event."),
                 score,
                 p(HTML(paste0("\U0001F91D You sold to <strong>",
                               formatC(rc$customers, format = "d", big.mark = ","),
                               "</strong> customers, paid out <strong>", money_m(rc$paid),
                               "</strong> in benefits, and <strong>",
                               formatC(rc$helped, format = "d", big.mark = ","),
                               "</strong> of them received a payout."))))
        ),
        h4("Why"),
        tags$ul(lapply(reasons, tags$li)),
        if (length(res$stories) > 0) tagList(
          h4("\U0001F464 Three of your customers"),
          lapply(res$stories, function(s) div(class = "story", s))
        ),
        p(em(paste0("This was game #", rv$game_no, ". Share the number with your prices, interest and
                    hard mode choice, and anyone can replay exactly the same luck."))))
  })

  output$year_table <- renderTable({
    co <- shown()
    data.frame(
      Year = co$year,
      Premiums = money_m(co$premiums),
      Claims = money_m(co$claims),
      Expenses = money_m(co$expenses),
      Interest = money_m(co$interest),
      Reserves = money_m(co$reserve),
      Surplus = money_m(co$surplus),
      Profit = money_m(co$profit),
      Status = paste(status_icon[co$status], co$status),
      check.names = FALSE
    )
  }, align = "r")
}

# ---------- The page ----------
ui <- navbarPage(
  title = "The Odds of a Lifetime",
  windowTitle = "The Odds of a Lifetime",
  theme = bslib::bs_theme(bootswatch = "flatly", primary = "#2a9d8f",
                         base_font = "Nunito, sans-serif", heading_font = "Fredoka, sans-serif"),
  tab_game,
  tab_how
)

# The chapter calculators (now inside "How it works")
calculator_server <- function(input, output, session) {
  
  # ----- Chapter 1 -----
  calc <- reactive({
    mu <- matrix(c(0, input$mu01, input$mu02,
                   0, 0,          input$mu12,
                   0, 0,          0), nrow = 3, byrow = TRUE)
    n <- input$n
    delta <- input$delta
    epv_di <- input$di * epv_annuity(mu, 1, 2, n, delta)
    epv_db <- input$db * epv_insurance(mu, 1, 3, n, delta)
    premium <- equivalence_premium(epv_di + epv_db, mu, start = 1,
                                   premium_states = 1, n = n, delta = delta)
    list(mu = mu, epv_di = epv_di, epv_db = epv_db, premium = premium)
  })
  
  output$results <- renderTable({
    r <- calc()
    data.frame(
      Item = c("Annual premium (paid while healthy)",
               "EPV of disability benefit",
               "EPV of death benefit",
               "Total EPV of benefits"),
      Value = c(money(r$premium), money(r$epv_di), money(r$epv_db),
                money(r$epv_di + r$epv_db))
    )
  })
  
  output$probs <- renderPlot({
    h <- 0.05
    path <- kolmogorov_path(calc()$mu, input$n, h)
    t <- (seq_len(dim(path)[1]) - 1) * h
    matplot(t, path[, 1, ], type = "l", lty = 1, lwd = 2,
            col = c("#2a9d8f", "#e9c46a", "#e76f51"), ylim = c(0, 1),
            xlab = "Years since issue", ylab = "Probability")
    legend("right", legend = c("Healthy", "Disabled", "Dead"),
           col = c("#2a9d8f", "#e9c46a", "#e76f51"), lty = 1, lwd = 2)
  })
  
  if (!is.null(est)) {
    output$est_table <- renderTable({
      m <- c(est$mu[1, 2], est$mu[1, 3], est$mu[2, 3])
      s <- c(est$se[1, 2], est$se[1, 3], est$se[2, 3])
      data.frame(
        Transition = c("Healthy to disabled", "Death while healthy",
                       "Death while disabled"),
        Estimate = sprintf("%.4f", m),
        `Std error` = sprintf("%.4f", s),
        `95% interval` = sprintf("%.4f to %.4f", m - 1.96 * s, m + 1.96 * s),
        check.names = FALSE
      )
    })
    
    observeEvent(input$use_est, {
      updateSliderInput(session, "mu01", value = round(est$mu[1, 2], 3))
      updateSliderInput(session, "mu02", value = round(est$mu[1, 3], 3))
      updateSliderInput(session, "mu12", value = round(est$mu[2, 3], 3))
    })
  }
  
  # ----- Chapter 2 -----
  dl <- reactive({
    n <- input$dl_n
    k <- 0:(n - 1)
    qd <- pmin(input$dl_q0 * (1 + input$dl_g)^k, 1)          # independent death rates
    qw <- ifelse(k == 0, input$dl_l1, input$dl_lu)            # independent lapse rates
    q <- udd_single_to_multiple(cbind(qd, qw))                # dependent rates
    q_no_lapse <- cbind(qd, 0)
    b <- c(input$dl_b, 0)
    list(q = q,
         prem = md_premium(q, b, input$dl_i),
         prem_no_lapse = md_premium(q_no_lapse, b, input$dl_i),
         epv = md_epv_benefits(q, b, input$dl_i),
         ann = md_annuity_due(q, input$dl_i))
  })
  
  output$dl_results <- renderTable({
    r <- dl()
    change <- (r$prem - r$prem_no_lapse) / r$prem_no_lapse
    data.frame(
      Item = c("Annual premium allowing for lapses",
               "Annual premium if nobody lapses",
               "Effect of lapses on the premium",
               "EPV of death benefit (with lapses)",
               "Annuity factor (with lapses)"),
      Value = c(money(r$prem), money(r$prem_no_lapse),
                sprintf("%+.1f%%", 100 * change),
                money(r$epv), sprintf("%.4f", r$ann))
    )
  })
  
  output$dl_plot <- renderPlot({
    tab <- decrement_table(dl()$q, radix = 1000)
    yrs <- 0:input$dl_n
    lines <- cbind(tab$l,
                   c(0, cumsum(tab$d[, 1])),
                   c(0, cumsum(tab$d[, 2])))
    matplot(yrs, lines, type = "l", lty = 1, lwd = 2,
            col = c("#2a9d8f", "#e76f51", "#457b9d"), ylim = c(0, 1000),
            xlab = "Policy year", ylab = "Number of policies (out of 1,000)")
    legend("right", legend = c("Still in force", "Cumulative deaths", "Cumulative lapses"),
           col = c("#2a9d8f", "#e76f51", "#457b9d"), lty = 1, lwd = 2)
  })
  
  if (!is.null(study)) {
    # Only compare the policy years covered by both the study and the slider term
    study_in_term <- reactive(study[study$policy_year <= input$dl_n, ])
    
    output$dl_ae <- renderTable({
      ae <- actual_vs_expected(study_in_term(), dl()$q)
      data.frame(
        Decrement = ae$decrement,
        Actual = formatC(ae$actual, format = "d", big.mark = ","),
        Expected = formatC(ae$expected, format = "f", digits = 0, big.mark = ","),
        `A/E` = pct(ae$ae_ratio),
        check.names = FALSE
      )
    })
    
    output$dl_study_plot <- renderPlot({
      s <- study_in_term()
      q <- dl()$q
      k <- s$policy_year
      plot(k, s$q_lapse, pch = 19, col = "#457b9d",
           ylim = c(0, max(c(s$q_lapse + 2 * s$se_lapse, q[k, 2])) * 1.1),
           xlab = "Policy year", ylab = "Lapse rate (dependent)")
      arrows(k, s$q_lapse - 1.96 * s$se_lapse, k, s$q_lapse + 1.96 * s$se_lapse,
             angle = 90, code = 3, length = 0.03, col = "#457b9d")
      lines(k, q[k, 2], lwd = 2, col = "#e76f51")
      legend("topright", legend = c("Observed in SQL data (95% interval)", "Assumption on sliders"),
             col = c("#457b9d", "#e76f51"), pch = c(19, NA), lty = c(NA, 1), lwd = c(NA, 2))
    })
  }
  
  # ----- Chapter 3 -----
  tl <- reactive({
    n <- 120 - min(input$tl_x, input$tl_y)
    qx <- makeham_q(input$tl_x, n)
    qy <- makeham_q(input$tl_y, n)
    i <- input$tl_i
    a_x  <- annuity_due_status(survival_curve(qx), i)
    a_y  <- annuity_due_status(survival_curve(qy), i)
    a_xy <- joint_annuity(qx, qy, i)
    a_ls <- last_survivor_annuity(qx, qy, i)
    list(qx = qx, qy = qy, n = n,
         a_x = a_x, a_y = a_y, a_xy = a_xy, a_ls = a_ls,
         rev = reversionary_annuity(qx, qy, i),
         p_x_first = contingent_first(qx, qy))
  })
  
  output$tl_results <- renderTable({
    r <- tl()
    amt <- input$tl_amt
    s <- input$tl_share
    data.frame(
      Item = c("Cost of a joint and survivor pension",
               "Cost if income continues in full to the survivor",
               "Cost if income stops at the first death",
               "Cost of income to (y) only after (x) dies",
               "Probability that (x) dies first",
               "Annuity factors: x, y, joint, last survivor"),
      Value = c(money(amt * (s * r$a_ls + (1 - s) * r$a_xy)),
                money(amt * r$a_ls),
                money(amt * r$a_xy),
                money(amt * r$rev),
                pct(r$p_x_first),
                sprintf("%.4f, %.4f, %.4f, %.4f", r$a_x, r$a_y, r$a_xy, r$a_ls))
    )
  })
  
  output$tl_plot <- renderPlot({
    r <- tl()
    both <- joint_survival(r$qx, r$qy)
    any  <- last_survivor_survival(r$qx, r$qy)
    yrs <- 0:r$n
    lines <- cbind(both, any - both, 1 - any)
    matplot(yrs, lines, type = "l", lty = 1, lwd = 2,
            col = c("#2a9d8f", "#e9c46a", "#e76f51"), ylim = c(0, 1),
            xlab = "Years from now", ylab = "Probability")
    legend("right", legend = c("Both alive", "One alive", "Both dead"),
           col = c("#2a9d8f", "#e9c46a", "#e76f51"), lty = 1, lwd = 2)
  })
  
  if (!is.null(couple_study)) {
    obs_years <- nrow(couple_study)
    n0 <- couple_study$both_alive[1]
    
    # Model at the slider ages, over the same years as the study
    tl_cmp <- reactive({
      qx <- makeham_q(input$tl_x, obs_years)
      qy <- makeham_q(input$tl_y, obs_years)
      list(cmp = compare_couples(couple_study, qx, qy),
           x_first_model = contingent_first(qx, qy))
    })
    
    output$tl_study_table <- renderTable({
      r <- tl_cmp()
      cmp <- r$cmp
      rows <- c(11, 21, obs_years)
      data.frame(
        Measure = c(sprintf("Both alive after %d years", rows - 1),
                    sprintf("At least one alive after %d years", rows - 1),
                    sprintf("(x) dies first within %d years", obs_years)),
        Observed = c(pct(cmp$both_alive_observed[rows]),
                     pct(cmp$any_alive_observed[rows]),
                     pct(sum(couple_study$x_dies_first) / n0)),
        Model = c(pct(cmp$both_alive_model[rows]),
                  pct(cmp$any_alive_model[rows]),
                  pct(r$x_first_model))
      )
    })
    
    output$tl_study_plot <- renderPlot({
      cmp <- tl_cmp()$cmp
      t <- cmp$year - 1
      plot(t, cmp$both_alive_observed, pch = 19, col = "#2a9d8f", ylim = c(0, 1),
           xlab = "Years from now", ylab = "Proportion of couples")
      points(t, cmp$any_alive_observed, pch = 19, col = "#e9c46a")
      lines(t, cmp$both_alive_model, lwd = 2, col = "#2a9d8f")
      lines(t, cmp$any_alive_model, lwd = 2, col = "#e9c46a")
      legend("bottomleft",
             legend = c("Both alive: observed (dots), model (line)",
                        "At least one alive: observed (dots), model (line)"),
             col = c("#2a9d8f", "#e9c46a"), pch = 19, lwd = 2)
    })
  }
}

server <- function(input, output, session) {
  game_server(input, output, session)
  calculator_server(input, output, session)
}

shinyApp(ui, server)
