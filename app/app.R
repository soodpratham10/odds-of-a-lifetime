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

money_m <- function(x) {
  ifelse(abs(x) >= 1e6, sprintf("%s$%.1fM", ifelse(x < 0, "-", ""), abs(x) / 1e6),
         sprintf("%s$%s", ifelse(x < 0, "-", ""), formatC(abs(x), format = "f", digits = 0, big.mark = ",")))
}

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

# Sell the policies, live through the years, and add everything up
run_game <- function(chosen, price_pct, i_earn, seed) {
  set.seed(seed)
  tabs <- list()
  info <- list()
  for (id in chosen) {
    prod <- products[[id]]
    G <- prod$fair * price_pct[[id]] / 100
    N <- sales_volume(G, prod$fair, base = prod$base, elasticity = ELASTICITY)
    tabs[[id]] <- switch(id,
      di = simulate_disability(N, mu_game, 20, 12000, 50000, G, e_std,
                               I_PRICE, i_earn, horizon = HORIZON),
      term = simulate_term(N, q_game, c(250000, 0), G, e_std,
                           I_PRICE, i_earn, horizon = HORIZON),
      couple = simulate_couples(N, qx_game, qy_game, 20000, 0.6, G, e_annuity,
                                I_PRICE, i_earn, horizon = HORIZON))
    info[[id]] <- list(G = G, N = N, pct = price_pct[[id]])
  }
  capital <- starting_capital(chosen)
  list(co = run_company(tabs, capital, i_earn), tabs = tabs, info = info,
       capital = capital, i_earn = i_earn)
}

status_colour <- c(Healthy = "#2a9d8f", Warning = "#e9a23b", Bankrupt = "#e63946")
status_icon <- c(Healthy = "\U0001F7E2", Warning = "\U0001F7E1", Bankrupt = "\U0001F534")

card <- function(...) div(class = "game-card", ...)

game_css <- tags$style(HTML("
  .game-card { border: 1px solid #dee2e6; border-radius: 12px; padding: 18px 20px;
               margin-bottom: 16px; background: #ffffff; }
  .game-hero { text-align: center; padding: 40px 10px 20px 10px; }
  .game-hero h1 { font-size: 2.4em; margin-bottom: 0.4em; }
  .game-hero p { font-size: 1.15em; max-width: 640px; margin: 0 auto 1em auto; }
  .locked { opacity: 0.55; }
  .meter { color: white; border-radius: 12px; padding: 14px 20px; font-size: 1.3em;
           margin-bottom: 14px; }
  .verdict { border-radius: 12px; padding: 18px 22px; margin-top: 10px;
             border: 2px solid #dee2e6; }
  .big-number { font-size: 1.8em; font-weight: bold; }
  .shelf .checkbox { border: 1px solid #dee2e6; border-radius: 12px; padding: 12px 16px;
                     margin-bottom: 10px; }
  .shelf .checkbox label { width: 100%; }
"))

screen_welcome <- tabPanelBody("welcome",
  div(class = "game-hero",
      h1("\U0001F3E2 Lifetime Mutual"),
      p(strong("You've just been made Chief Actuary.")),
      p("Choose which insurance products to sell and set their prices. Then live through
        the next 20 years with thousands of customers: some get sick, some die, some walk away,
        and interest rates may not be kind."),
      p("Price too low and the company goes bankrupt. Price too high and nobody buys."),
      actionButton("go_shelf", "Start ▶", class = "btn-primary btn-lg"),
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
  actionButton("back_welcome", "◀ Back"),
  actionButton("go_pricing", "Next: set prices ▶", class = "btn-primary")
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
    h4("\U0001F9FE Your costs"),
    p("Agents take 50% of the first year's premium and 5% after that. Each policy costs $200 to set up
      and $50 a year to run. The annuity costs 2% of its premium plus $500 to set up, then $50 a year.
      The fair price already includes these.")
  ),
  actionButton("back_shelf", "◀ Back"),
  actionButton("run", "Run the 20 years ▶", class = "btn-primary btn-lg")
)

screen_years <- tabPanelBody("years",
  h2("3. The next 20 years"),
  uiOutput("meter"),
  fluidRow(
    column(7, plotOutput("company_plot", height = "330px")),
    column(5, uiOutput("events"))
  ),
  uiOutput("verdict"),
  br(),
  actionButton("skip", "Skip to the end ⏩"),
  actionButton("reroll", "Same prices, different luck \U0001F3B2"),
  actionButton("again", "Change my prices ↩", class = "btn-primary"),
  h4("The company's accounts"),
  p(em("All amounts for the year. Reserves are the money that must be set aside for future promises;
       surplus is what's left over.")),
  tableOutput("year_table")
)

tab_game <- tabPanel("\U0001F3AE The Game",
  game_css,
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

  rv <- reactiveValues(res = NULL, year = 0, running = FALSE, prices = NULL)

  start_run <- function() {
    rv$res <- run_game(rv$prices$chosen, rv$prices$pct, OUTLOOK[[input$outlook]],
                       seed = sample.int(1e6, 1))
    rv$year <- 0
    rv$running <- TRUE
    go("years")
  }

  observeEvent(input$run, {
    pct_list <- lapply(input$chosen, function(id) {
      v <- input[[paste0("price_", id)]]
      if (is.null(v)) 100 else v
    })
    names(pct_list) <- input$chosen
    rv$prices <- list(chosen = input$chosen, pct = pct_list)
    withProgress(message = "Simulating thousands of lives...", start_run())
  })
  observeEvent(input$reroll, {
    req(rv$prices)
    withProgress(message = "Simulating thousands of lives...", start_run())
  })
  observeEvent(input$again, go("pricing"))

  # How far the story can go: the last year, or the year the company went bankrupt
  last_year <- reactive({
    req(rv$res)
    co <- rv$res$co
    bust <- match("Bankrupt", co$status)
    if (is.na(bust)) nrow(co) else bust
  })

  observeEvent(input$skip, {
    req(rv$res)
    rv$year <- last_year()
    rv$running <- FALSE
  })

  # Reveal one year at a time
  observe({
    req(rv$running)
    invalidateLater(450)
    isolate({
      if (rv$year < last_year()) {
        rv$year <- rv$year + 1
      }
      if (rv$year >= last_year()) rv$running <- FALSE
    })
  })

  shown <- reactive({
    req(rv$res, rv$year > 0)
    rv$res$co[seq_len(rv$year), ]
  })

  output$meter <- renderUI({
    req(rv$res)
    if (rv$year == 0) {
      return(div(class = "meter", style = "background:#457b9d;",
                 paste("Year 0: you start with", money_m(rv$res$capital))))
    }
    row <- shown()[rv$year, ]
    div(class = "meter", style = paste0("background:", status_colour[[row$status]], ";"),
        paste0(status_icon[[row$status]], "  Year ", row$year, " of ", HORIZON, ": ", row$status,
               "  |  Surplus ", money_m(row$surplus), "  |  Reserves ", money_m(row$reserve)))
  })

  output$company_plot <- renderPlot({
    req(rv$res)
    co <- rv$res$co
    yr <- c(0, co$year)
    top <- max(c(rv$res$capital, co$assets, co$reserve)) * 1.05
    bottom <- min(0, co$assets[seq_len(last_year())])
    par(mar = c(4, 5, 1, 1))
    plot(NA, xlim = c(0, HORIZON), ylim = c(bottom, top) / 1e6,
         xlab = "Year", ylab = "$ millions", las = 1)
    abline(h = 0, col = "grey70")
    if (rv$year > 0) {
      k <- 0:rv$year
      a <- c(rv$res$capital, co$assets[seq_len(rv$year)]) / 1e6
      r <- c(0, co$reserve[seq_len(rv$year)]) / 1e6
      polygon(c(k, rev(k)), c(a, rev(r)), col = adjustcolor("#2a9d8f", 0.15), border = NA)
      lines(k, a, lwd = 3, col = "#2a9d8f")
      lines(k, r, lwd = 3, col = "#e76f51")
    }
    legend("topleft", legend = c("Assets (what the company owns)", "Reserves (what it must hold)",
                                 "Shaded gap = surplus"),
           col = c("#2a9d8f", "#e76f51", adjustcolor("#2a9d8f", 0.3)), lwd = c(3, 3, 10), bty = "n")
  })

  output$events <- renderUI({
    req(rv$res)
    if (rv$year == 0) return(card(p("Starting the clock...")))
    co <- shown()
    msgs <- list()
    for (k in seq_len(nrow(co))) {
      if (co$status[k] == "Warning" && (k == 1 || co$status[k - 1] == "Healthy")) {
        msgs[[length(msgs) + 1]] <- paste0("Year ", k, ": \U0001F7E1 the surplus is thin. The regulator is watching.")
      }
      if (co$status[k] == "Healthy" && k > 1 && co$status[k - 1] == "Warning") {
        msgs[[length(msgs) + 1]] <- paste0("Year ", k, ": \U0001F7E2 back to healthy.")
      }
      if (co$status[k] == "Bankrupt") {
        msgs[[length(msgs) + 1]] <- paste0("Year ", k, ": \U0001F534 assets fell below reserves. The regulator shuts the company.")
      }
    }
    worst <- which.min(co$profit)
    if (co$profit[worst] < 0) {
      msgs[[length(msgs) + 1]] <- paste0("Worst year so far: year ", worst, ", a loss of ",
                                         money_m(-co$profit[worst]), ".")
    }
    if (length(msgs) == 0) msgs <- list("So far, so good.")
    card(h4("What happened"), tags$ul(lapply(msgs, tags$li)))
  })

  output$verdict <- renderUI({
    req(rv$res, !rv$running, rv$year > 0)
    res <- rv$res
    co <- res$co
    final <- co[rv$year, ]
    bank <- res$capital * (1 + res$i_earn)^rv$year
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
    if (res$i_earn < I_PRICE) {
      reasons[[length(reasons) + 1]] <- paste0("Interest: you earned ", res$i_earn * 100,
        "% instead of the 5% you priced with, so investment income fell short every year.")
    } else if (res$i_earn > I_PRICE) {
      reasons[[length(reasons) + 1]] <- paste0("Interest: you earned ", res$i_earn * 100,
        "% instead of 5%, a tailwind every year.")
    }
    if (final$status == "Bankrupt") {
      headline <- h3(paste0("❌ Bankrupt in year ", final$year))
      border <- status_colour[["Bankrupt"]]
      score <- p("The company could no longer cover its promises to customers.")
    } else {
      gain <- final$surplus - bank
      headline <- h3(paste0("✅ Survived all ", HORIZON, " years"))
      border <- status_colour[["Healthy"]]
      score <- p("Final surplus ", strong(money_m(final$surplus)), ". Left in the bank, the starting capital would have grown to ",
                 money_m(bank), ", so the business ", if (gain >= 0) "added " else "cost ",
                 span(class = "big-number", money_m(abs(gain))), ".")
    }
    div(class = "verdict", style = paste0("border-color:", border, ";"),
        headline, score, h4("Why"), tags$ul(lapply(reasons, tags$li)))
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
  theme = bslib::bs_theme(bootswatch = "flatly"),
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
