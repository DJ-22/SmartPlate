
## Repository layout

```
SmartPlate/
├── Database Creation/
│   ├── init_schema.sql      Tables, FKs, CHECKs, indexes
│   ├── procedures.sql       Stored procedures (sp_*)
│   ├── triggers.sql         5 triggers covering order, batch, ingredient flows
│   ├── events.sql           Daily event scheduler (batch progression, expiry)
│   ├── ml_schema.sql        Forecast write-back tables
│   ├── ml_forecast.sql      Views + heuristic forecasting procedures
│   └── dummy_data.sql       Seed data (roles, ingredients, items, users)
├── backend/
│   ├── main.py              FastAPI app, ~80 REST endpoints by role
│   ├── auth.py              bcrypt + JWT, require_role() dependency
│   ├── database.py          PyMySQL connection helper, env-driven
│   ├── generate_history.py  Synthetic 12-month order history seeder
│   ├── requirements.txt     Pinned Python deps
│   └── tests/test_smoke.py  Per-role happy-path smoke tests
├── index.html               Common login portal
├── customer-dashboard.html  Browse menu, place/cancel orders, alerts
├── chef-dashboard.html      Active orders, mark prepared / out / delivered
├── employee-dashboard.html  Ingredients + place replenishment batches
├── supplier-dashboard.html  Manage Supplies, advance pending batches
├── manager-dashboard.html   Full CRUD + forecasting controls
├── .env.example             Env template (DB_*, JWT_SECRET)
├── README.md                You are here
└── REPORT.md                Project design report
```

## Code overview

### Database (`Database Creation/`)

Load order matters because triggers reference tables and procedures call other objects:

```
init_schema → procedures → triggers → events → ml_schema → ml_forecast → dummy_data
```

* **`init_schema.sql`** : All tables with surrogate `AUTO_INCREMENT` PKs except composite junctions (`Supplies`, `Recipes`, `Menu_Orders_Items`, `Permissions_Granted`, `Alerted`) and `Weather_Data` (natural PK on `date`). `CHECK` constraints encode status enums (see REPORT §4.1). `ON DELETE CASCADE` for dependent rows; `RESTRICT` for masters.
* **`procedures.sql`** : 11 procedures wrapping every write path so business rules stay in the DB. Multi-statement procs declare `EXIT HANDLER FOR SQLEXCEPTION → ROLLBACK; RESIGNAL` and use `START TRANSACTION / COMMIT`.
* **`triggers.sql`** : 5 triggers:
* `trg_after_order_item`: availability guard, FIFO ingredient deduction across delivered batches, chef alert fan-out.
* `trg_after_batch_delivered`: adds delivered batch to `Ingredients`, writes `in_storage` log.
* `trg_after_ingredient_update` / `trg_after_ingredient_insert`: auto-reorder when stock crosses `min_stock`.
* `trg_after_order_item_status`: guards backwards transitions, writes `dispatched_at` / `delivered_at`, writes `Sales_History` on delivery.
* **`events.sql`** : Two daily events: `evt_update_batch_status` walks batches `ordered → shipped → delivered` based on supplier `delivery_time`; `evt_expire_batches` writes waste records and removes expired inventory.
* **`ml_schema.sql` + `ml_forecast.sql`** : Views (`v_daily_item_sales`, `v_daily_ingredient_usage`, `v_daily_features`) and procedures (`sp_ForecastItemDemand`, `sp_RecomputeMinStocks`, `sp_RecomputePricing`, `sp_ApplyForecasts`, `sp_ApplyPricing`). Forecasts land in dedicated write-back tables with `applied=0`; managers explicitly apply.

### Backend (`backend/`)

* **`main.py`** : FastAPI app. ~80 endpoints grouped by role prefix (`/user/*`, `/chef/*`, `/employee/*`, `/supplier/*`, `/manager/*`) plus `/login`, `/register`, `/health`. Every write endpoint delegates to a stored procedure via `call_proc()`. Errors propagated from `SIGNAL SQLSTATE '45000'` are translated to HTTP 400 with the user-facing message; unexpected DB errors return 500 without leaking detail.
* **`auth.py`** : bcrypt via `passlib`, JWT via `python-jose` (24 h lifetime). `require_role(*roles)` is a FastAPI dependency; manager tokens satisfy any role check by design.
* **`database.py`** : PyMySQL connection helper. Reads `DB_HOST` / `DB_USER` / `DB_PASS` / `DB_NAME` from `.env` via `python-dotenv`; raises on startup if `DB_PASS` or `JWT_SECRET` is missing. `autocommit=True`; multi-statement atomicity is provided by the procedures themselves.
* **`generate_history.py`** : Seeds synthetic `Menu_Orders` + `Menu_Orders_Items` + `Sales_History` over a configurable date range (default 365 days), with day-of-week, occasion, and weather effects so the forecasting layer has signal. Drops `trg_after_order_item` and `trg_after_order_item_status` for the duration of the seed;  **re-run `triggers.sql` afterward** .
* **`tests/test_smoke.py`** : Per-role happy-path: login → role-scoped reads → one write per dashboard.

### Frontend

Static HTML + vanilla JS, no build step. `index.html` is the shared login portal — it dispatches to the correct dashboard based on the role embedded in the JWT. Each dashboard talks to the API at `http://localhost:8000/api/v1` and stores its JWT in `sessionStorage`. Styling and DOM interactions are inline; no framework.

## Setup

### 1. Database

Load the SQL files in order from `Database Creation/` into a running MySQL 8.x server:

```
init_schema.sql
procedures.sql
triggers.sql
events.sql
ml_schema.sql
ml_forecast.sql
dummy_data.sql
```

The event scheduler must be enabled (requires `SUPER` privilege):

```sql
SET GLOBAL event_scheduler = ON;
```

### 2. Backend

```bash
pip install -r backend/requirements.txt
cd backend
uvicorn main:app --reload
```

The API serves on `http://localhost:8000/api/v1`. Both `DB_PASS` and `JWT_SECRET` are required, startup will fail if either is missing.

### 3. Frontend

Serve the project root with any static server (the dashboards expect HTTP, not `file://`):

```bash
python -m http.server 5500
```

Then open `http://localhost:5500/index.html`.

### 4. Forecast training data (optional)

The forecasting tab needs historical orders to produce useful suggestions:

```bash
cd backend
python generate_history.py --days 365
# IMPORTANT: the script drops two triggers before seeding, so re-run
# triggers.sql afterward:
mysql -u root -p SmartPlate < "../Database Creation/triggers.sql"
```

## Demo accounts

All seeded users share the password `password123`. See `Database Creation/dummy_data.sql` for usernames by role.

## Notes

* JWTs live for 24 hours; logout is client-side only (`sessionStorage.clear()`). No refresh / revocation endpoint.
* Manager role passes every `require_role(...)` check by design — managers can hit any dashboard's endpoints.
* Auto-reorder fires when an ingredient crosses below `min_stock` and no pending batch exists. Reorder quantity is `GREATEST(min_stock * 2, 1)` from the fastest active supplier; see REPORT §15 for the full loop.
* CORS is restricted to dev ports (`3000`, `5500`, `8080`); the frontend must be served from one of these.
* Forecast suggestions never apply automatically — the manager reviews and clicks "Apply" to push them into `Ingredients.min_stock` and `Items.price`.
