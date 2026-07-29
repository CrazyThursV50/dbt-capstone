# Jaffle Shop Profitability Analytics (dbt project)

A dbt project that answers a single business question:

> **Which products and stores drive the most profit at Jaffle Shop, and what should the business do about it?**

Built on BigQuery using the official 6-table curated Jaffle Shop dataset (customers, orders, items, products, stores, supplies), loaded from the CSVs in `seeds/` via `dbt seed` — fully reproducible with no external data dependencies. Profitability is computed per line item and then rolled up by product, product type, store, and perishable-cost exposure.

---

## 1. Project Goal

**Primary question**: Which products (and stores) drive the most profit?

**Supporting questions**:
- Which product types have the highest gross margin and margin %?
- Which stores drive the most profit vs the most revenue (when these differ)?
- How much of each product's cost is perishable, and what does that mean for inventory management?

**Why it matters**: Jaffle Shop's leadership team needs to decide product-mix priorities, store-expansion sequencing, and supply-chain investments. Knowing which SKUs generate the most profit (not just the most revenue) directs marketing spend, menu engineering, and procurement focus.

**Success criteria**: A trusted analytics layer that:
1. Surfaces top-profit SKUs with concrete dollar amounts
2. Quantifies profit concentration across stores and product types
3. Flags spoilage exposure (perishable cost share) per product category
4. Supports actionable, dollar-attributable recommendations

---

## 2. Data Sources

The official curated Jaffle Shop dataset ships as 6 CSVs in `seeds/`. Running `dbt seed` loads them into the `<target_schema>_raw_jaffle_shop` dataset in BigQuery:

| Seed file | Loaded as | Rows | Description |
|---|---|---|---|
| `raw_customers.csv` | customers | 128 | One row per customer (id, name) |
| `raw_orders.csv` | orders | 686 | One row per order (id, customer, store_id, ordered_at, subtotal, tax_paid, order_total — all monetary fields in cents) |
| `raw_items.csv` | items | 997 | One row per line item (id, order_id, sku) — treated as 1 unit sold |
| `raw_products.csv` | products | 10 | One row per SKU (sku, name, type, price, description) |
| `raw_stores.csv` | stores | 6 | One row per store location (id, name, opened_at, tax_rate) |
| `raw_supplies.csv` | supplies | 65 | One row per supply per SKU (a single SKU can have multiple supplies, e.g. a jaffle needs knife + fork cutlery) |

**Data conventions**:
- `raw_items` has no quantity column → each row = **1 unit sold**
- Revenue per unit = `products.price` (USD, converted from cents via the `cents_to_dollars` macro)
- Cost per unit = sum of `supplies.cost` joined on SKU (a SKU may have multiple supplies)
- Gross margin per unit = revenue − cost
- Data window: **2016-09-01 → 2016-09-16** (16 days, all Philadelphia)

---

## 3. DAG / Model Flow

```
              seeds/ (6 CSVs) ──dbt seed──▶ raw_jaffle_shop (BigQuery)
                    ┌────┬─────┬────┬─────┬───┬───┐
                    │cust│ord. │itm.│prod.│str│sup│
                    └─┬──┴─┬───┴─┬──┴─┬──┴─┬─┴─┬─┘
                      │    │     │    │    │   │
                      ▼    ▼     ▼    ▼    ▼   ▼
              ┌────────────── staging layer (views) ──────────────────┐
              │ stg_jaffle_shop__customers                            │
              │ stg_jaffle_shop__orders                               │
              │ stg_jaffle_shop__items                                │
              │ stg_jaffle_shop__products                             │
              │ stg_jaffle_shop__stores                               │
              │ stg_jaffle_shop__supplies                             │
              └────────────────────┬──────────────────────────────────┘
                                   │
                                   ▼
              ┌────────────── marts layer (tables) ───────────────────┐
              │ dim_products  (price + supply cost → margin)          │
              │ dim_stores    (with store_age_years)                  │
              │ dim_customers (order_count + lifetime_value)          │
              │ fct_orders    (order grain)                           │
              │ fct_sales_line (per-item grain; CENTRAL for analyses) │
              └────────────────────┬──────────────────────────────────┘
                                   │
                                   ▼
              analyses (analysis/*.sql) compiled & run on demand:
                - top_products_by_profit
                - store_revenue_vs_profit
                - perishable_profit_contribution
                - margin_pct_by_product_type
                - check_lifetime_value (sanity check on dim_customers)
```

To explore the live lineage graph interactively:

```bash
cd dbt-capstone
dbt docs generate          # dbt Core (on dbt Fusion: dbt compile --write-catalog)
dbt docs serve --port 8001
```

Then open http://localhost:8001 in a browser.

---

## 4. Model Descriptions

### Staging layer (1:1 with sources, views)

| Model | Purpose | Grain |
|---|---|---|
| `stg_jaffle_shop__customers` | Rename id→customer_id; pass-through name. | One row per customer |
| `stg_jaffle_shop__orders` | Rename to clear FK names; cast `ordered_at`→date; convert monetary fields cents→USD via `cents_to_dollars`. | One row per order |
| `stg_jaffle_shop__items` | Rename id→order_item_id, sku→product_id. | One row per line item |
| `stg_jaffle_shop__products` | Rename sku→product_id; cents→USD on price; derive `is_food_item`/`is_drink_item` booleans. | One row per SKU |
| `stg_jaffle_shop__stores` | Rename id→store_id; cast opened_at→date. | One row per store |
| `stg_jaffle_shop__supplies` | Surrogate key over (id, sku); cents→USD on cost; rename perishable→is_perishable_supply. | One row per supply per SKU |

### Marts layer (analytical models, tables)

| Model | Purpose | Grain | Key columns |
|---|---|---|---|
| `dim_products` | Product dimension with pre-computed profitability fields. Sums all supply costs per SKU (a jaffle's knife + fork + filling all roll into one unit_cost). | One row per SKU (10 rows) | product_id (PK), product_price, **unit_cost**, **gross_margin**, **margin_pct**, has_perishable_supply |
| `dim_stores` | Store dimension; adds `store_age_years` for tenure analysis. | One row per store (6 rows) | store_id (PK), store_name, tax_rate, opened_date, store_age_years |
| `dim_customers` | Customer dimension with lifetime aggregates from fct_orders. | One row per customer (128 rows) | customer_id (PK), customer_name, first_order_date, most_recent_order_date, number_of_orders, lifetime_value |
| `fct_orders` | Order-grain fact table. Pass-through of stg orders with monetary fields in USD. | One row per order (686 rows) | order_id (PK), customer_id, store_id, ordered_at, subtotal, tax_paid, order_total |
| `fct_sales_line` | **The central analytics table**. Joins items × dim_products × orders, denormalizes product_type / is_food_item / has_perishable_supply for query convenience. Every profitability analysis groups this one table. | One row per line item (997 rows) | order_item_id (PK), order_id, product_id, store_id, customer_id, revenue_per_unit, cost_per_unit, **gross_margin_per_unit** |

---

## 5. Testing Strategy

The project uses **four layers of test coverage** matching dbt best practices:

### 5.1 Primary-key generic tests (`unique` + `not_null`)

Every PK at every layer — sources, staging, marts — has both `unique` and `not_null` data tests. Examples:

```yaml
# in src_jaffle_shop.yml — source layer
- name: customers
  columns:
    - name: id
      data_tests: [unique, not_null]

# in _marts.yml — marts layer
- name: dim_products
  columns:
    - name: product_id
      data_tests: [unique, not_null]
```

This prevents the most common analytics bugs: duplicate fact rows (which inflate metrics) and orphaned null keys (which break joins).

### 5.2 Referential integrity (`relationships` tests)

FK columns are tested to point at valid PKs in their dimension:

```yaml
- name: product_id  # in fct_sales_line
  data_tests:
    - relationships:
        arguments:
          to: ref('dim_products')
          field: product_id
```

`fct_sales_line` carries 3 such tests (order_id / product_id / store_id); customer integrity is tested one level up, on `fct_orders.customer_id` → `dim_customers`. If a future CSV reload introduced an unknown SKU, this test would fail before the analysis ran.

### 5.3 Domain rules (singular tests in `tests/`)

A custom SQL test enforces a business rule dbt can't infer from schemas:

- **`assert_gross_margin_non_negative.sql`** — fails if any product's `gross_margin < 0`. Selling below cost is either a pricing bug or an explicitly-approved loss leader; this test forces such cases to be intentional.

### 5.4 Source freshness

Deliberately **not configured**: the curated dataset is a static snapshot (2016-09-01 → 2016-09-16), so any freshness check would permanently report stale. In a live system, `orders.ordered_at` would be the `loaded_at_field` to monitor.

### Test count

`dbt build` runs **32 tests** across **11 models** — all passing in the current state.

---

## Insights:

All numbers below come from running `analysis/*.sql` against the live BigQuery target (`capstone` schema). Source SQL is in this repo and reproducible.

### Insight 1 — Beverages dominate top profit ranking

The top 5 SKUs by total profit are **all beverages**, collectively generating **$3,619.11 (66.9% of total profit)** despite representing just 5 of the 10 SKUs. The single most profitable SKU is **BEV-004 ("for richer or pourover")** at **$1,038.24 profit (19.2% of total)**, sold 168 times.

| Rank | SKU | Type | Units | Revenue | Profit | % of total profit |
|---|---|---|---|---|---|---|
| 1 | BEV-004 | beverage | 168 | $1,176 | **$1,038.24** | 19.2% |
| 2 | BEV-001 | beverage | 154 | $924 | $797.72 | 14.7% |
| 3 | BEV-003 | beverage | 160 | $960 | $713.60 | 13.2% |
| 4 | BEV-005 | beverage | 165 | $660 | $556.05 | 10.3% |
| 5 | BEV-002 | beverage | 158 | $790 | $513.50 | 9.5% |
| 6 | JAF-004 | jaffle | 39 | $546 | $412.23 | 7.6% |
| 7 | JAF-001 | jaffle | 37 | $407 | $362.23 | 6.7% |

The jaffle (food) SKUs sell ~4× less often but at ~2× the unit margin — they're niche, high-margin items, not volume drivers.

### Insight 2 — 100% revenue concentration in Philadelphia

In the 16-day window analyzed, **all $6,818 of revenue and 997 units sold came from Philadelphia** (opened 2016-09-01). The other five stores in the catalog hadn't opened yet:

| Store | Opened | Units | Revenue | Profit | Status |
|---|---|---|---|---|---|
| **Philadelphia** | 2016-09-01 | **997** | **$6,818** | **$5,412.28** | Active (100% of revenue) |
| Brooklyn | 2017-03-12 | 0 | $0 | $0 | Not yet operational |
| Chicago | 2018-04-29 | 0 | $0 | $0 | Not yet operational |
| San Francisco | 2018-05-09 | 0 | $0 | $0 | Not yet operational |
| New Orleans | 2019-03-10 | 0 | $0 | $0 | Not yet operational |
| Los Angeles | 2019-09-13 | 0 | $0 | $0 | Not yet operational |

This is a **strategic single-point-of-failure**: the entire business depends on one location. The model is ready to track per-store profit as new locations come online — `fct_sales_line.store_id` is already in place and tested via a relationships check against `dim_stores`.

### Insight 3 — Jaffles carry ~19 ppts more perishable cost exposure than beverages

Computing **cost-weighted perishable share** per SKU (perishable supply cost ÷ total supply cost), the two categories have very different spoilage profiles:

| Product type | SKUs | Avg perishable cost % | Range |
|---|---|---|---|
| **Jaffle** | 5 | **87.2%** | 76.0% – 92.1% |
| **Beverage** | 5 | **68.5%** | 52.4% – 82.9% |

Summed across their five SKUs, jaffles carry $11.75 of perishable cost out of $13.20 total per-unit cost (≈ $2.35 of $2.64 per SKU on average); beverages carry $4.06 of $5.56 (≈ $0.81 of $1.11 per SKU). The most perishable jaffle is **JAF-003 at 92.1%** — almost all of its supply cost is in spoilage-exposed inputs.

### Insight 4 — Beverages = volume engine, jaffles = unit-margin engine

| Product type | Units sold | Distinct SKUs | Avg price | Avg cost | Avg margin | Total profit | Avg margin % |
|---|---|---|---|---|---|---|---|
| **Beverage** | 805 | 5 | $5.60 | $1.11 | $4.50 | **$3,619.11** | **80.3%** |
| **Jaffle** | 192 | 5 | $12.02 | $2.68 | $9.34 | $1,793.17 | 77.7% |

Beverages have **4.2× the volume** and the higher margin **percent** (80.3% vs 77.7%) — they're both the cash generator and the more efficient one. Jaffles win on **absolute dollar margin per unit** ($9.34 vs $4.50): each one sold contributes 2× the dollar profit, but the rarity of jaffle orders means total profit lags beverages.

---

## Next steps:

Each next step maps to one of the insights above.

| # | Action | Rationale (insight) | Expected impact |
|---|---|---|---|
| 1 | **Double down on BEV-004 promotion** (top-shelf placement, combo offers, marketing spend) | BEV-004 alone is 19.2% of total profit (Insight 1) | Even a 10% lift translates to ~$104 of marginal profit per 16 days (~$2.4k/year extrapolated) |
| 2 | **Accelerate the Brooklyn launch (2017-03 opening)** and instrument per-store profit reporting from day 1 | 100% Philadelphia concentration is unsustainable (Insight 2) | Diversifies geographic risk; `fct_sales_line.store_id` and `dim_stores` are already wired in — onboarding is a data-load problem, not a modeling problem |
| 3 | **Tighten jaffle ingredient sourcing & shelf life** (renegotiate dairy/produce contracts, FEFO rotation, demand forecasting on jaffle volume) | Jaffles are 87% perishable cost (Insight 3) — wastage directly hits the highest-cost-density supplies | At an average jaffle cost of $2.68/unit, a 5-point cut in perishable share saves ~$0.13 per unit sold; at scale this protects margin in the high-perishable category |
| 4 | **Position jaffles as a high-attach upsell to beverage orders**, not as standalone volume drivers | Beverages drive 80% of volume; jaffles drive 2× per-unit dollar margin (Insight 4) | Increases jaffle attach rate without forcing them to win on volume — leverages existing beverage traffic |

---

### Future data work

- **Time-series view** — current data is only 16 days. Once orders span multiple months, add a `dim_date` and analyze day-of-week / weekly patterns.
- **Customer-cohort overlay** — `dim_customers.lifetime_value` is already computed; cross with product mix to find "repeat customer favorites".
- **Store profitability** — once non-Philadelphia stores have orders, the existing `fct_sales_line.store_id` → `dim_stores` relationships will surface store-level profit ranking immediately.
- **Incremental refresh** — `fct_sales_line` is currently materialized as a table on full refresh; with growing volume it should switch to incremental materialization keyed on `ordered_at`.

---

## How to reproduce

```bash
# 0. Clone and enter the project
git clone https://github.com/CrazyThursV50/dbt-capstone.git
cd dbt-capstone

# 1. Configure ~/.dbt/profiles.yml with a `dbt_capstone` profile pointing at
#    your own BigQuery project (any dataset/schema you can write to):
#
#    dbt_capstone:
#      target: dev
#      outputs:
#        dev:
#          type: bigquery
#          method: service-account   # or oauth
#          keyfile: /path/to/your-service-account.json
#          database: your-gcp-project-id
#          schema: capstone
#          location: US
#          threads: 16
#
#    No access to anyone else's data is needed — all raw data ships in seeds/.

dbt debug          # verify the connection

# 2. Install packages (dbt_utils)
dbt deps

# 3. Load the 6 raw CSVs into <schema>_raw_jaffle_shop
dbt seed

# 4. Build all models + run all tests (11 models, 32 tests)
dbt build

# 5. View lineage / model docs (dbt Core)
dbt docs generate
dbt docs serve --port 8001
# On the dbt Fusion engine, write the catalog instead:
#   dbt compile --write-catalog   # produces target/catalog.json + manifest.json

# 6. Re-run any insight on demand
dbt compile --select top_products_by_profit
bq query --nouse_legacy_sql --format=pretty \
  < target/compiled/dbt_capstone/analysis/top_products_by_profit.sql
```

## Data limitations

- Static snapshot: 16 days (2016-09-01 → 2016-09-16), one active store. Trends, seasonality, and store comparisons cannot be inferred from this window.
- `raw_items` has no quantity column, so each line item is treated as exactly 1 unit.
- Insights describe this sample only; the recommended next steps are framed as tests/experiments, not causal conclusions.
