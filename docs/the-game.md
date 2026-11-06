[← Overview](../README.md)

# How the game works

**[▶ Play Lifetime Mutual](https://soodpratham10.shinyapps.io/odds-of-a-lifetime/)**

The game is a small insurance company run on the project's tested engine. A player makes the decisions a pricing actuary makes, and the engine plays out what an insurer then lives through: claims, reserves, interest and solvency.

> **Code:** [`r/simulate_company.R`](../r/simulate_company.R) · [`r/reserves.R`](../r/reserves.R) · [`r/expenses.R`](../r/expenses.R) · [`app/app.R`](../app/app.R)
> **Tests:** [`tests/test_simulate.R`](../tests/test_simulate.R) · [`tests/test_reserves.R`](../tests/test_reserves.R) · [`tests/test_expenses.R`](../tests/test_expenses.R)

## 1. The products

Each product is one chapter, with the same assumptions as that chapter's calculator.

| Product | Chapter | What it pays | Premium | Fair price |
|---|---|---|---|---|
| 🏥 Disability Income | [1. Detours](chapters/01-detours.md) | $12,000 a year while disabled, $50,000 on death, 20 years | Paid continuously while healthy | about $2,797 a year |
| 🛡 Term Life | [2. Exits](chapters/02-exits.md) | $250,000 on death within 20 years; customers can lapse | Annual, in advance | $986.10 a year |
| 💑 Couples Annuity | [3. Two Lives](chapters/03-two-lives.md) | $20,000 a year to a couple aged 65 and 62, 60% to the survivor | One single premium | $293,833.95 |

Interest for pricing and reserves is 5% a year.

## 2. The fair price includes expenses

Real policies cost money to sell and run. Agents take 50% of the first year's premium and 5% after that; each policy costs $200 to set up and $50 a year to run. (The annuity: 2% of the premium and $500 at the start, then $50 a year.)

The fair gross premium $G$ satisfies the equivalence principle with expenses. For annual premiums in advance:

$$G \ddot{a} = \text{EPV(benefits)} + E_0 + e \left( \ddot{a} - 1 \right) + c_0 G + c G \left( \ddot{a} - 1 \right)$$

where $c_0$ and $c$ are the initial and renewal commission rates and $E_0$ and $e$ the fixed costs. For the term policy this lifts the price from the Chapter 2 net premium of $816.86 to $986.10.

## 3. Sales react to price

At the fair price each product sells to a base number of customers (5,000 policies, or 500 couples for the annuity). Charging more sells fewer, charging less sells more:

$$N = N_{\text{base}} \left( \frac{G_{\text{fair}}}{G} \right)^{4}$$

So overcharging isn't a free win: 20% above fair sells only about half as many policies (48% of the base).

## 4. Every customer gets their own life

Each customer is simulated year by year:

- **Disability Income:** within each year the intensities are constant, so the time to the next move (falling ill, or dying) is exponential. Because the exponential distribution is memoryless, drawing one year at a time gives the same lives as drawing whole lifetimes, and it lets a shock hit a single year.
- **Term Life:** each year a policy dies, lapses or stays, with the dependent rates from Chapter 2.
- **Couples Annuity:** each partner dies independently with Makeham mortality (SOA Standard Ultimate Life Table parameters).

## 5. Reserves

At the end of each year the company must hold reserves for its future promises, on the pricing basis and including expenses:

| Product | Method |
|---|---|
| Disability Income | Thiele's differential equations, solved backwards with Euler steps of 0.01 years |
| Term Life | The recursion $\left( {}_tV + P_t \right)(1+i) = q^{(d)} b + p^{(\tau)} {}_{t+1}V$ |
| Couples Annuity | The same kind of recursion for each status: both alive, only one alive |

A single policy can have a negative reserve: it is expected to pay in more than it will cost. The total for each block of policies is never allowed below zero, because future profits can't be counted as assets.

Underpricing shows up straight away: a cheap premium means future premiums don't cover future costs, so the reserve jumps on day one.

## 6. The company's accounts

The board provides starting capital of 20% of the fair premiums of the business chosen. Each year:

$$A_k = A_{k-1} \left( 1 + i_k \right) + \text{premiums} - \text{expenses} - \text{claims}$$

with the year's cash flows rolled up with the interest actually earned, $i_k$. Then:

| Status | Rule |
|---|---|
| 🟢 Healthy | Surplus (assets minus reserves) at least 10% of reserves |
| 🟡 Warning | Surplus positive but below 10% of reserves |
| 🔴 Bankrupt | Assets below reserves. The company is shut down. |

At the end, the score compares the final surplus with what the starting capital would have earned in the bank.

## 7. How the game was tuned

I ran the game many times to set the capital and the price sensitivity so that it feels fair: losses come from bad pricing, bad interest or bad luck, not from the rules.

| Choice | Usual result |
|---|---|
| Fair prices, expected interest | 🟢 Survives; capital grows with interest |
| 10% below fair on everything | 🟡 Survives, just barely |
| 20% below fair on one product | About a coin flip |
| 20% below fair on everything | 🔴 Bankrupt |
| Fair prices, interest only 3% | Survives with much less surplus |
| 10% to 30% above fair | Survives, more profit, fewer customers |

The test suite checks the key property directly: at the fair price, the present value of each product's cash flows over 20,000 customers is close to zero.

## 8. The Daily Actuary

Each year's headlines come from monitoring, as an insurer would do it: **actual vs expected** claim events, the A/E ratio from the [Chapter 2 experience study](chapters/02-exits.md).

- New disability claims against healthy lives × probability of falling ill in a year
- Term Life deaths against policies in force × $q^{(d)}$
- Deaths among annuitants against lives alive × $q$. Fewer deaths than expected is **bad** news for an annuity: it pays for longer.

An A/E above 112% or below 88% makes the news, along with changes in the company's health and any surprise event.

## 9. Hard mode: stress tests

With hard mode on, one surprise hits in a random year between 5 and 14. It changes the real world only. Prices and reserves stay as they were set, just as for a real insurer.

| Surprise | Effect |
|---|---|
| Pandemic | Death rates × 3 for one year. Bad for Term Life, good for the annuity. |
| Sickness wave | Disability rates × 3 for one year |
| Customers flee | Term Life lapse rates × 4 for one year |
| Market crash | Interest earned falls by 3 points for the rest of the game |

## 10. Game numbers

The game number is the random seed. The same number, products, prices, interest and hard-mode setting replay exactly the same lives. Keeping the number fixed and changing only one price separates the effect of the price from the effect of luck.

## What the model leaves out

Taxes, reinsurance, new business after the first year, recoveries from disability, and random interest rates. Reinsurance and random interest scenarios are planned.

---

[← Overview](../README.md) · [Getting started →](getting-started.md)
