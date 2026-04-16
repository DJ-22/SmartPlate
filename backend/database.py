import os
import pymysql
import pymysql.cursors
from dotenv import load_dotenv

load_dotenv()

_db_pass = os.getenv("DB_PASS")
if _db_pass is None:
    raise RuntimeError("DB_PASS environment variable must be set (see .env.example)")

DB_CONFIG = {
    "host":     os.getenv("DB_HOST", "localhost"),
    "port":     int(os.getenv("DB_PORT", "3306")),
    "user":     os.getenv("DB_USER", "root"),
    "password": _db_pass,
    "database": os.getenv("DB_NAME", "SmartPlate"),
    "cursorclass": pymysql.cursors.DictCursor,
    # B1: autocommit off so failures in the middle of write paths roll back
    "autocommit": False,
}

def get_conn():
    return pymysql.connect(**DB_CONFIG)

def query(sql: str, params=None) -> list[dict]:
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            return cur.fetchall()

def query_one(sql: str, params=None) -> dict | None:
    rows = query(sql, params)
    return rows[0] if rows else None

def execute(sql: str, params=None) -> int:
    """Returns last insert id. Commits on success, rolls back on error."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            last_id = cur.lastrowid
        conn.commit()
        return last_id
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

def call_proc(name: str, args: tuple = ()):
    """Call a stored procedure. Returns last insert id."""
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.callproc(name, args)
            last_id = cur.lastrowid
        conn.commit()
        return last_id
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
