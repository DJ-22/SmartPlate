#!/usr/bin/env python
"""
SmartPlate synthetic history generator (Phase 9c).

Seeds N days of Menu_Orders, Menu_Orders_Items, Sales_History,
Weather_Data and supplementary Occasions so the SQL heuristic
forecasting layer has signal to train on.

Orders are shaped by day-of-week, holidays, and weather so the
heuristic produces meaningfully different forecasts across
conditions.

Caveats:
    1. The script DROPs trg_after_order_item (inventory deduction)
       and trg_after_order_item_status (sales-history sync) before
       inserting seed rows, so historical inserts don't touch
       present-day Ingredients.quantity. RE-RUN triggers.sql after
       this script finishes.
    2. Inserted rows use status=2 (delivered) and set the three
       SLA timestamps on Menu_Orders_Items.

Usage:
    python generate_history.py                      # 365 days
    python generate_history.py --days 120 --seed 7
"""

import argparse
import datetime as dt
import math
import os
import random
import sys
from pathlib import Path

import pymysql
import pymysql.cursors
from dotenv import load_dotenv

load_dotenv()

HOLIDAYS = [
    ("New Year",              (1, 1)),
    ("Republic Day",          (1, 26)),
    ("Valentine's Day",       (2, 14)),
    ("Holi",                  (3, 14)),
    ("Independence Day",      (8, 15)),
    ("Gandhi Jayanti",        (10, 2)),
    ("Diwali",                (11, 1)),
    ("Christmas",             (12, 25)),
    ("New Year's Eve",        (12, 31)),
]


def connect():
    pw = os.getenv("DB_PASS")
    if pw is None:
        raise SystemExit("DB_PASS env var must be set (see .env.example)")
    return pymysql.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=pw,
        database=os.getenv("DB_NAME", "SmartPlate"),
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
    )


def drop_seed_conflicting_triggers(cur):
    cur.execute("DROP TRIGGER IF EXISTS trg_after_order_item")
    cur.execute("DROP TRIGGER IF EXISTS trg_after_order_item_status")


def seed_occasions(cur, start, end):
    added = 0
    d = start
    while d <= end:
        for name, (m, day) in HOLIDAYS:
            if d.month == m and d.day == day:
                cur.execute(
                    "INSERT IGNORE INTO Occasions (name, date) VALUES (%s, %s)",
                    (f"{name} {d.year}", d),
                )
                added += cur.rowcount
        d += dt.timedelta(days=1)
    cur.execute(
        "INSERT IGNORE INTO Occasions (name, date) VALUES ('Regular', NULL)"
    )
    return added


def seed_weather(cur, start, end, rng):
    rows = 0
    d = start
    while d <= end:
        doy = d.timetuple().tm_yday
        temp = 22.0 + 10.0 * math.sin(2 * math.pi * (doy - 80) / 365) + rng.gauss(0, 2.5)
        temp = max(-5.0, min(45.0, round(temp, 2)))
        humidity = max(20.0, min(99.0, round(60 + rng.gauss(0, 15), 2)))
        cur.execute(
            "INSERT IGNORE INTO Weather_Data (date, temperature, humidity) "
            "VALUES (%s, %s, %s)",
            (d, temp, humidity),
        )
        rows += cur.rowcount
        d += dt.timedelta(days=1)
    return rows


def fetch_catalog(cur):
    cur.execute("SELECT item_id, price FROM Items WHERE is_active = 1")
    items = cur.fetchall()
    cur.execute("SELECT user_id FROM Customers")
    customers = [r["user_id"] for r in cur.fetchall()]
    cur.execute(
        "SELECT occasion_id, date FROM Occasions WHERE date IS NOT NULL"
    )
    occs = {r["date"]: r["occasion_id"] for r in cur.fetchall()}
    cur.execute("SELECT occasion_id FROM Occasions WHERE name = 'Regular'")
    regular = cur.fetchone()["occasion_id"]
    return items, customers, occs, regular


def daily_order_count(date, weather, is_holiday, rng):
    base = 45.0
    wd = date.weekday()
    if wd >= 4:
        base *= 1.5
    if is_holiday:
        base *= 1.4
    if weather:
        t = float(weather["temperature"])
        h = float(weather["humidity"])
        if t < 12:
            base *= 1.2
        elif t > 32:
            base *= 0.85
        if h > 85:
            base *= 1.15
    return max(1, int(round(base * rng.uniform(0.85, 1.15))))


def generate(days, seed):
    rng = random.Random(seed)
    end = dt.date.today() - dt.timedelta(days=1)
    start = end - dt.timedelta(days=days - 1)

    conn = connect()
    try:
        with conn.cursor() as cur:
            print(f"Seeding {days} days: {start} .. {end}")
            drop_seed_conflicting_triggers(cur)
            conn.commit()

            occs_added = seed_occasions(cur, start, end)
            weather_added = seed_weather(cur, start, end, rng)
            conn.commit()
            print(f"  occasions added: {occs_added}, weather rows: {weather_added}")

            items, customers, occs, regular = fetch_catalog(cur)
            if not items or not customers:
                print("No active items or customers. Run dummy_data.sql first.")
                return 1
            print(f"  catalog: {len(items)} items, {len(customers)} customers")

            cur.execute(
                "SELECT date, temperature, humidity FROM Weather_Data "
                "WHERE date BETWEEN %s AND %s",
                (start, end),
            )
            weather = {r["date"]: r for r in cur.fetchall()}

            orders_inserted = 0
            items_inserted = 0
            d = start
            while d <= end:
                is_hol = d in occs
                n = daily_order_count(d, weather.get(d), is_hol, rng)
                occ_id = occs.get(d, regular)
                for _ in range(n):
                    hour = rng.randint(11, 22)
                    minute = rng.randint(0, 59)
                    order_dt = dt.datetime.combine(d, dt.time(hour, minute))
                    user_id = rng.choice(customers)
                    basket_size = rng.randint(1, min(4, len(items)))
                    basket = rng.sample(items, k=basket_size)
                    lines = [(it, rng.randint(1, 3)) for it in basket]
                    total = sum(float(it["price"]) * qty for it, qty in lines)
                    cur.execute(
                        "INSERT INTO Menu_Orders (order_time, price, user_id) "
                        "VALUES (%s, %s, %s)",
                        (order_dt, round(total, 2), user_id),
                    )
                    oid = cur.lastrowid
                    orders_inserted += 1
                    for it, qty in lines:
                        cur.execute(
                            "INSERT INTO Menu_Orders_Items "
                            "(menu_order_id, item_id, quantity, status, "
                            " prepared_at, dispatched_at, delivered_at) "
                            "VALUES (%s, %s, %s, 2, %s, %s, %s)",
                            (
                                oid, it["item_id"], qty,
                                order_dt + dt.timedelta(minutes=15),
                                order_dt + dt.timedelta(minutes=25),
                                order_dt + dt.timedelta(minutes=45),
                            ),
                        )
                        cur.execute(
                            "INSERT INTO Sales_History "
                            "(quantity, item_id, menu_order_id, occasion_id) "
                            "VALUES (%s, %s, %s, %s)",
                            (qty, it["item_id"], oid, occ_id),
                        )
                        items_inserted += 1
                if d.toordinal() % 30 == 0:
                    conn.commit()
                    print(f"  through {d}: {orders_inserted} orders")
                d += dt.timedelta(days=1)
            conn.commit()

            print(
                f"\nDone. Orders: {orders_inserted}  Items: {items_inserted}\n"
                "IMPORTANT: re-apply triggers to restore runtime behavior:\n"
                "  mysql -u root -p SmartPlate < \"Database Creation/triggers.sql\"\n"
            )
    finally:
        conn.close()
    return 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--days", type=int, default=365)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()
    sys.exit(generate(args.days, args.seed))


if __name__ == "__main__":
    main()
