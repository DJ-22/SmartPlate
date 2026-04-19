import logging
import os
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from dotenv import load_dotenv

from database import query, query_one, execute, call_proc, get_conn
from auth import (
    hash_password, verify_password, create_token,
    get_current_user, require_role
)

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("smartplate")

def _db_error(context: str, e: Exception) -> HTTPException:
    # S7: if MySQL SIGNAL (SQLSTATE 45000, errno 1644) bubbled up, surface
    # the user-facing message as 400. Otherwise log and return a generic 500.
    errno = getattr(e, "args", (None,))
    if errno and errno[0] == 1644:
        return HTTPException(400, errno[1] if len(errno) > 1 else "Invalid request")
    logger.exception("%s: %s", context, e)
    return HTTPException(500, "Internal server error")

load_dotenv()

app = FastAPI(title="SmartPlate API")

# Restrict CORS to explicit dev origins (S1). Override via CORS_ORIGINS=a,b,c
_cors_env = os.getenv("CORS_ORIGINS", "")
_cors_origins = [o.strip() for o in _cors_env.split(",") if o.strip()] or [
    "http://localhost:3000", "http://127.0.0.1:3000",
    "http://localhost:5500", "http://127.0.0.1:5500",
    "http://localhost:8080", "http://127.0.0.1:8080",
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

# ── Pydantic models ────────────────────────────────────────────────────────────

class LoginReq(BaseModel):
    email: str
    password: str

class RegisterReq(BaseModel):
    username: str
    email: str
    password: str
    role_name: str
    user_type: str          # customer | employee | chef | supplier | manager
    name: str = ""
    salary: float = 0
    contact: str = ""
    delivery_time: int = 1

class OrderItemReq(BaseModel):
    item_id: int
    quantity: float

class StatusReq(BaseModel):
    status: int

class BatchUpdateReq(BaseModel):
    expiry_date: Optional[str] = None
    quantity:    Optional[float] = None
    unit:        Optional[str] = None
    cost:        Optional[float] = None
    status:      Optional[int] = None

class SupplierBatchUpdateReq(BaseModel):
    expiry_date: Optional[str] = None
    status:      Optional[int] = None

class IngredientReq(BaseModel):
    name: str
    unit: str
    min_stock: float
    allergen: str = "None"

class IngredientUpdateReq(BaseModel):
    name:      Optional[str]   = None
    unit:      Optional[str]   = None
    min_stock: Optional[float] = None

class MenuItemReq(BaseModel):
    name: str
    description: str = ""
    price: float
    prep_time: int
    category: str

class MenuItemUpdateReq(BaseModel):
    name:         Optional[str]   = None
    description:  Optional[str]   = None
    price:        Optional[float] = None
    prep_time:    Optional[int]   = None
    is_active:    Optional[int]   = None

class RecipeLineReq(BaseModel):
    ingredient_id: int
    quantity: float
    unit: str

class SupplierReq(BaseModel):
    name: str
    contact: str
    delivery_time: int
    user_id: Optional[int] = None

class SupplierUpdateReq(BaseModel):
    name:          Optional[str] = None
    contact:       Optional[str] = None
    delivery_time: Optional[int] = None
    is_active:     Optional[int] = None
    user_id:       Optional[int] = None

class SupplyReq(BaseModel):
    ingredient_id: int
    price_per_unit: float
    unit: str

class SupplyPricingReq(BaseModel):
    price_per_unit: float
    unit: str

class BatchOrderReq(BaseModel):
    ingredient_id: int
    supplier_id: int
    quantity: float

class WasteReq(BaseModel):
    batch_id: int
    quantity: float

class ComplianceReq(BaseModel):
    status: int
    description: str = ""

class WeatherReq(BaseModel):
    date: str
    temperature: float
    humidity: float

class ProfileUpdateReq(BaseModel):
    delivery_time: Optional[int] = None
    contact:       Optional[str] = None
    is_active:     Optional[int] = None

class UserUpdateReq(BaseModel):
    username:     Optional[str]   = None
    email:        Optional[str]   = None
    salary:       Optional[float] = None

class PasswordChangeReq(BaseModel):
    old_password: str
    new_password: str

class OccasionReq(BaseModel):
    name: str
    date: Optional[str] = None

class NutritionReq(BaseModel):
    item_id: int
    calories: Optional[int] = None
    protein:  Optional[int] = None
    carbs:    Optional[int] = None
    fat:      Optional[int] = None
    fiber:    Optional[int] = None

class ManagerBatchReq(BaseModel):
    ingredient_id: int
    supplier_id: int
    quantity: float
    unit: Optional[str] = None
    cost: Optional[float] = None
    expiry_date: Optional[str] = None
    status: int = 0

class ForecastRunReq(BaseModel):
    target_date: str
    safety: Optional[float] = 1.5

class GiftCodeReq(BaseModel):
    code: str
    amount: float
    type: int = 0            # 0=percent, 1=flat
    min_order: float = 0
    valid_from: str          # 'YYYY-MM-DD HH:MM:SS' or ISO date
    valid_to: str

# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok"}

# ── Auth ──────────────────────────────────────────────────────────────────────

@app.post("/api/v1/login")
def login(req: LoginReq):
    row = query_one(
        "SELECT u.user_id, u.password_hash, r.name AS role_name "
        "FROM Users u JOIN Roles r ON u.role_id=r.role_id WHERE u.email=%s",
        (req.email,)
    )
    if not row or not verify_password(req.password, row["password_hash"]):
        raise HTTPException(401, "Invalid credentials")

    execute("UPDATE Users SET last_login=NOW() WHERE user_id=%s", (row["user_id"],))

    supplier_id = 0
    if row["role_name"] == "supplier":
        sup = query_one("SELECT supplier_id FROM Suppliers WHERE user_id=%s", (row["user_id"],))
        if sup:
            supplier_id = sup["supplier_id"]

    token = create_token(row["user_id"], row["role_name"], supplier_id)
    return {"token": token, "role": row["role_name"], "supplier_id": supplier_id}


@app.post("/api/v1/me/password")
def change_my_password(req: PasswordChangeReq, user=Depends(get_current_user)):
    row = query_one("SELECT password_hash FROM Users WHERE user_id=%s", (user["user_id"],))
    if not row or not verify_password(req.old_password, row["password_hash"]):
        raise HTTPException(401, "Current password is incorrect")
    if len(req.new_password) < 6:
        raise HTTPException(400, "New password must be at least 6 characters")
    execute("UPDATE Users SET password_hash=%s WHERE user_id=%s",
            (hash_password(req.new_password), user["user_id"]))
    return {"status": "updated"}


@app.patch("/api/v1/alerts/{alert_id}/read")
def mark_alert_read(alert_id: int, user=Depends(get_current_user)):
    execute(
        "UPDATE Alerted SET read_at=NOW() WHERE alert_id=%s AND user_id=%s AND read_at IS NULL",
        (alert_id, user["user_id"])
    )
    return {"status": "read"}


@app.post("/api/v1/register", status_code=201)
def register(req: RegisterReq):
    hashed = hash_password(req.password)
    try:
        call_proc("sp_RegisterUser", (
            req.username, req.email, hashed,
            req.role_name, req.user_type, req.name,
            req.salary, req.contact, req.delivery_time
        ))
    except Exception as e:
        raise _db_error("register", e)
    return {"status": "registered"}

# ── Customer ──────────────────────────────────────────────────────────────────

@app.get("/api/v1/user/menu")
def list_menu(user=Depends(require_role("customer"))):
    return query(
        "SELECT i.*, c.name AS category_name FROM Items i "
        "JOIN Category c ON i.category_id=c.category_id "
        "WHERE i.is_active=1 "
        "AND EXISTS (SELECT 1 FROM Recipes r WHERE r.item_id=i.item_id) "
        "ORDER BY c.name, i.name"
    )

@app.get("/api/v1/user/orders")
def list_my_orders(user=Depends(require_role("customer"))):
    # Hide orders that have no items (empty shells from abandoned sessions)
    return query(
        "SELECT mo.* FROM Menu_Orders mo "
        "WHERE mo.user_id=%s AND EXISTS ("
        "  SELECT 1 FROM Menu_Orders_Items oi WHERE oi.menu_order_id = mo.menu_order_id"
        ") ORDER BY mo.order_time DESC",
        (user["user_id"],)
    )

@app.post("/api/v1/user/orders", status_code=201)
def place_order(user=Depends(require_role("customer"))):
    # Reuse an existing empty order for this user rather than stacking empties
    existing = query_one(
        "SELECT mo.menu_order_id FROM Menu_Orders mo "
        "WHERE mo.user_id=%s AND NOT EXISTS ("
        "  SELECT 1 FROM Menu_Orders_Items oi WHERE oi.menu_order_id = mo.menu_order_id"
        ") ORDER BY mo.order_time DESC LIMIT 1",
        (user["user_id"],)
    )
    if existing:
        return {"order_id": existing["menu_order_id"]}

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.callproc("sp_PlaceOrder", (user["user_id"],))
            cur.execute("SELECT LAST_INSERT_ID() AS order_id")
            row = cur.fetchone()
            order_id = row["order_id"]
        conn.commit()
    return {"order_id": order_id}

@app.post("/api/v1/user/orders/{order_id}/items", status_code=201)
def add_order_item(order_id: int, req: OrderItemReq, user=Depends(require_role("customer"))):
    # Verify order belongs to user
    row = query_one("SELECT user_id FROM Menu_Orders WHERE menu_order_id=%s", (order_id,))
    if not row or row["user_id"] != user["user_id"]:
        raise HTTPException(403, "Forbidden")
    # U2: once any item has shipped (status>0), the order is "closed" for new items
    shipped = query_one(
        "SELECT 1 FROM Menu_Orders_Items WHERE menu_order_id=%s AND status>0 LIMIT 1",
        (order_id,)
    )
    if shipped:
        raise HTTPException(409, "Order is already in delivery — start a new order")
    try:
        call_proc("sp_AddOrderItem", (order_id, req.item_id, req.quantity))
    except Exception as e:
        raise _db_error("add_order_item", e)
    return {"status": "added"}

@app.get("/api/v1/user/orders/{order_id}")
def get_order(order_id: int, user=Depends(require_role("customer"))):
    order = query_one("SELECT * FROM Menu_Orders WHERE menu_order_id=%s", (order_id,))
    if not order or order["user_id"] != user["user_id"]:
        raise HTTPException(403, "Forbidden")
    items = query(
        "SELECT oi.*, i.name AS item_name FROM Menu_Orders_Items oi "
        "JOIN Items i ON oi.item_id=i.item_id WHERE oi.menu_order_id=%s",
        (order_id,)
    )
    return {"order": order, "items": items}

@app.delete("/api/v1/user/orders/{order_id}/items/{item_id}")
def cancel_order_item(order_id: int, item_id: int, user=Depends(require_role("customer"))):
    order = query_one("SELECT user_id FROM Menu_Orders WHERE menu_order_id=%s", (order_id,))
    if not order or order["user_id"] != user["user_id"]:
        raise HTTPException(403, "Forbidden")
    try:
        call_proc("sp_CancelOrderItem", (order_id, item_id))
    except Exception as e:
        raise _db_error("cancel_order_item", e)
    return {"status": "cancelled"}

@app.get("/api/v1/user/alerts")
def get_my_alerts(user=Depends(require_role("customer"))):
    return query(
        "SELECT a.alert_id, a.message, al.created_at, al.read_at FROM Alerts a "
        "JOIN Alerted al ON a.alert_id=al.alert_id "
        "WHERE al.user_id=%s ORDER BY al.created_at DESC LIMIT 50",
        (user["user_id"],)
    )

# ── Chef ──────────────────────────────────────────────────────────────────────

@app.get("/api/v1/chef/orders/active")
def list_active_orders(user=Depends(require_role("chef"))):
    return query(
        "SELECT oi.menu_order_id AS order_id, oi.item_id, oi.quantity, oi.status, "
        "i.name AS item_name FROM Menu_Orders_Items oi "
        "JOIN Items i ON oi.item_id=i.item_id WHERE oi.status IN (0,1) "
        "ORDER BY oi.menu_order_id ASC"
    )

@app.get("/api/v1/chef/orders")
def list_all_orders(user=Depends(require_role("chef"))):
    return query(
        "SELECT oi.menu_order_id AS order_id, oi.item_id, oi.quantity, oi.status, "
        "i.name AS item_name, mo.order_time FROM Menu_Orders_Items oi "
        "JOIN Items i ON oi.item_id=i.item_id "
        "JOIN Menu_Orders mo ON oi.menu_order_id=mo.menu_order_id "
        "ORDER BY oi.menu_order_id DESC LIMIT 500"
    )

@app.patch("/api/v1/chef/orders/{order_id}/items/{item_id}/status")
def update_order_item_status(order_id: int, item_id: int, req: StatusReq,
                              user=Depends(require_role("chef"))):
    row = query_one(
        "SELECT status FROM Menu_Orders_Items WHERE menu_order_id=%s AND item_id=%s",
        (order_id, item_id)
    )
    if not row:
        raise HTTPException(404, "Order item not found")
    if req.status < row["status"]:
        raise HTTPException(400, "Cannot move status backwards")
    if req.status not in (0, 1, 2):
        raise HTTPException(400, "Invalid status value")
    try:
        execute(
            "UPDATE Menu_Orders_Items SET status=%s WHERE menu_order_id=%s AND item_id=%s",
            (req.status, order_id, item_id)
        )
    except Exception as e:
        raise _db_error("update_order_item_status", e)
    return {"status": "updated"}

@app.get("/api/v1/chef/alerts")
def chef_alerts(user=Depends(require_role("chef"))):
    return query(
        "SELECT a.alert_id, a.message, al.created_at, al.read_at FROM Alerts a "
        "JOIN Alerted al ON a.alert_id=al.alert_id "
        "WHERE al.user_id=%s ORDER BY al.created_at DESC LIMIT 50",
        (user["user_id"],)
    )

# ── Employee ──────────────────────────────────────────────────────────────────

@app.get("/api/v1/employee/ingredients")
def list_ingredients_emp(user=Depends(require_role("employee"))):
    return query(
        "SELECT i.*, a.name AS allergen_name FROM Ingredients i "
        "LEFT JOIN Allergens a ON i.allergen_id=a.allergen_id ORDER BY i.name"
    )

@app.get("/api/v1/employee/ingredients/{ingredient_id}/suppliers")
def list_suppliers_for_ingredient(ingredient_id: int, user=Depends(require_role("employee"))):
    return query(
        "SELECT sp.supplier_id, sp.ingredient_id, sp.price_per_unit, sp.unit, "
        "s.name AS supplier_name, s.delivery_time "
        "FROM Supplies sp JOIN Suppliers s ON sp.supplier_id=s.supplier_id "
        "WHERE sp.ingredient_id=%s AND s.is_active=1 ORDER BY s.delivery_time ASC",
        (ingredient_id,)
    )

@app.post("/api/v1/employee/batches", status_code=201)
def receive_batch(req: BatchOrderReq, user=Depends(require_role("employee"))):
    try:
        call_proc("sp_ReceiveBatch", (req.ingredient_id, req.supplier_id, req.quantity))
    except Exception as e:
        raise _db_error("receive_batch", e)
    return {"status": "batch ordered"}

@app.get("/api/v1/employee/batches")
def list_batches_emp(user=Depends(require_role("employee"))):
    return query(
        "SELECT ib.inventory_batch_id AS batch_id, ib.inventory_batch_id, "
        "ib.purchase_date, ib.expiry_date, ib.quantity, ib.unit, ib.cost, ib.status, "
        "ib.supplier_id, ib.ingredient_id, "
        "i.name AS ingredient_name, s.name AS supplier_name "
        "FROM Inventory_Batches ib "
        "LEFT JOIN Ingredients i ON ib.ingredient_id=i.ingredient_id "
        "LEFT JOIN Suppliers s ON ib.supplier_id=s.supplier_id "
        "ORDER BY ib.status ASC, ib.expiry_date ASC"
    )

# ── Supplier ──────────────────────────────────────────────────────────────────

@app.get("/api/v1/supplier/ingredients")
def list_ingredients_sup(user=Depends(require_role("supplier"))):
    return query(
        "SELECT i.*, a.name AS allergen_name FROM Ingredients i "
        "LEFT JOIN Allergens a ON i.allergen_id=a.allergen_id ORDER BY i.name"
    )

@app.get("/api/v1/supplier/supplies")
def get_my_supplies(user=Depends(require_role("supplier"))):
    return query(
        "SELECT sp.supplier_id, sp.ingredient_id, sp.price_per_unit, sp.unit, "
        "i.name AS ingredient_name "
        "FROM Supplies sp JOIN Ingredients i ON sp.ingredient_id=i.ingredient_id "
        "WHERE sp.supplier_id=%s",
        (user["supplier_id"],)
    )

@app.post("/api/v1/supplier/supplies", status_code=201)
def add_supply(req: SupplyReq, user=Depends(require_role("supplier"))):
    execute(
        "INSERT INTO Supplies (supplier_id,ingredient_id,price_per_unit,unit) "
        "VALUES (%s,%s,%s,%s) ON DUPLICATE KEY UPDATE price_per_unit=%s, unit=%s",
        (user["supplier_id"], req.ingredient_id, req.price_per_unit, req.unit,
         req.price_per_unit, req.unit)
    )
    return {"status": "added"}

@app.delete("/api/v1/supplier/supplies/{ingredient_id}")
def remove_supply(ingredient_id: int, user=Depends(require_role("supplier"))):
    execute("DELETE FROM Supplies WHERE supplier_id=%s AND ingredient_id=%s",
            (user["supplier_id"], ingredient_id))
    return {"status": "removed"}

@app.patch("/api/v1/supplier/supplies/{ingredient_id}/pricing")
def update_supply_pricing(ingredient_id: int, req: SupplyPricingReq,
                           user=Depends(require_role("supplier"))):
    execute(
        "UPDATE Supplies SET price_per_unit=%s, unit=%s WHERE supplier_id=%s AND ingredient_id=%s",
        (req.price_per_unit, req.unit, user["supplier_id"], ingredient_id)
    )
    return {"status": "updated"}

@app.get("/api/v1/supplier/batches")
def get_my_batches(user=Depends(require_role("supplier"))):
    return query(
        "SELECT ib.inventory_batch_id AS batch_id, ib.*, "
        "i.name AS ingredient_name FROM Inventory_Batches ib "
        "LEFT JOIN Ingredients i ON ib.ingredient_id=i.ingredient_id "
        "WHERE ib.supplier_id=%s ORDER BY ib.status ASC, ib.purchase_date DESC",
        (user["supplier_id"],)
    )

@app.patch("/api/v1/supplier/batches/{batch_id}")
def update_batch_supplier(batch_id: int, req: SupplierBatchUpdateReq,
                           user=Depends(require_role("supplier"))):
    row = query_one("SELECT supplier_id FROM Inventory_Batches WHERE inventory_batch_id=%s", (batch_id,))
    if not row or row["supplier_id"] != user["supplier_id"]:
        raise HTTPException(403, "Forbidden")
    if req.expiry_date is not None:
        execute("UPDATE Inventory_Batches SET expiry_date=%s WHERE inventory_batch_id=%s",
                (req.expiry_date, batch_id))
    if req.status is not None:
        try:
            execute("UPDATE Inventory_Batches SET status=%s WHERE inventory_batch_id=%s",
                    (req.status, batch_id))
        except Exception as e:
            raise _db_error("supplier_update_batch_status", e)
    return {"status": "updated"}

@app.patch("/api/v1/supplier/profile")
def update_my_profile(req: ProfileUpdateReq, user=Depends(require_role("supplier"))):
    execute(
        "UPDATE Suppliers SET "
        "delivery_time=COALESCE(%s,delivery_time), "
        "contact=COALESCE(%s,contact), "
        "is_active=COALESCE(%s,is_active) "
        "WHERE user_id=%s",
        (req.delivery_time, req.contact, req.is_active, user["user_id"])
    )
    return {"status": "updated"}

# ── Manager ───────────────────────────────────────────────────────────────────

@app.get("/api/v1/manager/allergens")
def list_allergens(user=Depends(require_role("manager"))):
    return query("SELECT * FROM Allergens ORDER BY name")

@app.get("/api/v1/manager/categories")
def list_categories(user=Depends(require_role("manager"))):
    return query("SELECT category_id AS id, name FROM Category ORDER BY name")

@app.get("/api/v1/manager/ingredients")
def list_ingredients(user=Depends(require_role("manager"))):
    return query(
        "SELECT i.*, a.name AS allergen_name FROM Ingredients i "
        "LEFT JOIN Allergens a ON i.allergen_id=a.allergen_id ORDER BY i.name"
    )

@app.post("/api/v1/manager/ingredients", status_code=201)
def add_ingredient(req: IngredientReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_AddIngredient", (req.name, req.unit, req.min_stock, req.allergen))
    except Exception as e:
        raise _db_error("add_ingredient", e)
    return {"status": "created"}

@app.patch("/api/v1/manager/ingredients/{id}")
def update_ingredient(id: int, req: IngredientUpdateReq, user=Depends(require_role("manager"))):
    execute(
        "UPDATE Ingredients SET "
        "name=COALESCE(%s,name), unit=COALESCE(%s,unit), min_stock=COALESCE(%s,min_stock) "
        "WHERE ingredient_id=%s",
        (req.name, req.unit, req.min_stock, id)
    )
    return {"status": "updated"}

@app.delete("/api/v1/manager/ingredients/{id}")
def delete_ingredient(id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Ingredients WHERE ingredient_id=%s", (id,))
    return {"status": "deleted"}

@app.get("/api/v1/manager/menu")
def list_menu_mgr(user=Depends(require_role("manager"))):
    return query(
        "SELECT i.*, c.name AS category_name FROM Items i "
        "JOIN Category c ON i.category_id=c.category_id ORDER BY c.name, i.name"
    )

@app.post("/api/v1/manager/menu", status_code=201)
def add_menu_item(req: MenuItemReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_AddMenuItem", (req.name, req.description, req.price, req.prep_time, req.category))
    except Exception as e:
        raise _db_error("add_menu_item", e)
    return {"status": "created"}

@app.patch("/api/v1/manager/menu/{item_id}")
def update_menu_item(item_id: int, req: MenuItemUpdateReq, user=Depends(require_role("manager"))):
    execute(
        "UPDATE Items SET "
        "name=COALESCE(%s,name), description=COALESCE(%s,description), "
        "price=COALESCE(%s,price), prep_time=COALESCE(%s,prep_time), "
        "is_active=COALESCE(%s,is_active) "
        "WHERE item_id=%s",
        (req.name, req.description, req.price, req.prep_time, req.is_active, item_id)
    )
    return {"status": "updated"}

@app.delete("/api/v1/manager/menu/{item_id}")
def delete_menu_item(item_id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Items WHERE item_id=%s", (item_id,))
    return {"status": "deleted"}

@app.get("/api/v1/manager/menu/{item_id}/recipe")
def get_recipe(item_id: int, user=Depends(require_role("manager"))):
    return query(
        "SELECT r.*, i.name AS ingredient_name FROM Recipes r "
        "JOIN Ingredients i ON r.ingredient_id=i.ingredient_id WHERE r.item_id=%s",
        (item_id,)
    )

@app.post("/api/v1/manager/menu/{item_id}/recipe", status_code=201)
def add_recipe_line(item_id: int, req: RecipeLineReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_AddRecipeLine", (item_id, req.ingredient_id, req.quantity, req.unit))
    except Exception as e:
        raise _db_error("add_recipe_line", e)
    return {"status": "added"}

@app.delete("/api/v1/manager/menu/{item_id}/recipe/{ingredient_id}")
def delete_recipe_line(item_id: int, ingredient_id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Recipes WHERE item_id=%s AND ingredient_id=%s", (item_id, ingredient_id))
    return {"status": "deleted"}

@app.get("/api/v1/manager/suppliers")
def list_suppliers(user=Depends(require_role("manager"))):
    return query("SELECT * FROM Suppliers ORDER BY name")

# S8: supplier creation happens through /manager/users with role=supplier,
# which ensures a linked User record and credentials. Standalone endpoint removed.

@app.patch("/api/v1/manager/suppliers/{id}")
def update_supplier(id: int, req: SupplierUpdateReq, user=Depends(require_role("manager"))):
    execute(
        "UPDATE Suppliers SET "
        "name=COALESCE(%s,name), contact=COALESCE(%s,contact), "
        "delivery_time=COALESCE(%s,delivery_time), is_active=COALESCE(%s,is_active), "
        "user_id=COALESCE(%s,user_id) "
        "WHERE supplier_id=%s",
        (req.name, req.contact, req.delivery_time, req.is_active, req.user_id, id)
    )
    return {"status": "updated"}

@app.delete("/api/v1/manager/suppliers/{id}")
def delete_supplier(id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Suppliers WHERE supplier_id=%s", (id,))
    return {"status": "deleted"}

@app.get("/api/v1/manager/batches")
def list_batches_mgr(user=Depends(require_role("manager"))):
    return query(
        "SELECT ib.inventory_batch_id AS batch_id, ib.inventory_batch_id, "
        "ib.purchase_date, ib.expiry_date, ib.quantity, ib.unit, ib.cost, ib.status, "
        "ib.supplier_id, ib.ingredient_id, "
        "i.name AS ingredient_name, s.name AS supplier_name "
        "FROM Inventory_Batches ib "
        "LEFT JOIN Ingredients i ON ib.ingredient_id=i.ingredient_id "
        "LEFT JOIN Suppliers s ON ib.supplier_id=s.supplier_id "
        "ORDER BY ib.status ASC, ib.expiry_date ASC"
    )

@app.patch("/api/v1/manager/batches/{batch_id}")
def update_batch_mgr(batch_id: int, req: BatchUpdateReq, user=Depends(require_role("manager"))):
    try:
        execute(
            "UPDATE Inventory_Batches SET "
            "expiry_date=COALESCE(%s,expiry_date), quantity=COALESCE(%s,quantity), "
            "unit=COALESCE(%s,unit), cost=COALESCE(%s,cost), status=COALESCE(%s,status) "
            "WHERE inventory_batch_id=%s",
            (req.expiry_date, req.quantity, req.unit, req.cost, req.status, batch_id)
        )
    except Exception as e:
        raise _db_error("manager_update_batch", e)
    return {"status": "updated"}

@app.delete("/api/v1/manager/batches/{batch_id}")
def delete_batch(batch_id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Inventory_Batches WHERE inventory_batch_id=%s", (batch_id,))
    return {"status": "deleted"}

def _clamp_page(limit: Optional[int], offset: Optional[int], default_limit: int = 200, max_limit: int = 1000):
    lim = default_limit if limit is None else max(1, min(int(limit), max_limit))
    off = 0 if offset is None else max(0, int(offset))
    return lim, off


@app.get("/api/v1/manager/orders")
def list_all_orders(
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    user=Depends(require_role("manager"))
):
    lim, off = _clamp_page(limit, offset)
    where, params = [], []
    if from_date:
        where.append("order_time >= %s"); params.append(from_date)
    if to_date:
        where.append("order_time < DATE_ADD(%s, INTERVAL 1 DAY)"); params.append(to_date)
    sql = ("SELECT menu_order_id AS order_id, menu_order_id, order_time, price, user_id "
           "FROM Menu_Orders")
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY order_time DESC LIMIT %s OFFSET %s"
    params.extend([lim, off])
    return query(sql, tuple(params))

@app.get("/api/v1/manager/orders/{order_id}")
def get_order_mgr(order_id: int, user=Depends(require_role("manager"))):
    order = query_one("SELECT * FROM Menu_Orders WHERE menu_order_id=%s", (order_id,))
    items = query(
        "SELECT oi.*, i.name AS item_name FROM Menu_Orders_Items oi "
        "JOIN Items i ON oi.item_id=i.item_id WHERE oi.menu_order_id=%s", (order_id,)
    )
    return {"order": order, "items": items}

@app.get("/api/v1/manager/users")
def list_users(
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    user=Depends(require_role("manager"))
):
    # B11/S7: never return password_hash
    lim, off = _clamp_page(limit, offset, default_limit=500)
    return query(
        "SELECT u.user_id, u.username, u.email, u.last_login, u.role_id, "
        "r.name AS role_name FROM Users u "
        "JOIN Roles r ON u.role_id=r.role_id ORDER BY u.user_id LIMIT %s OFFSET %s",
        (lim, off)
    )

@app.post("/api/v1/manager/users", status_code=201)
def create_user(req: RegisterReq, user=Depends(require_role("manager"))):
    hashed = hash_password(req.password)
    try:
        call_proc("sp_RegisterUser", (
            req.username, req.email, hashed,
            req.role_name, req.user_type, req.name,
            req.salary, req.contact, req.delivery_time
        ))
    except Exception as e:
        raise _db_error("create_user", e)
    return {"status": "created"}

@app.patch("/api/v1/manager/users/{id}")
def update_user(id: int, req: UserUpdateReq, user=Depends(require_role("manager"))):
    if req.username is not None or req.email is not None:
        execute(
            "UPDATE Users SET username=COALESCE(%s,username), email=COALESCE(%s,email) "
            "WHERE user_id=%s",
            (req.username, req.email, id)
        )
    if req.salary is not None:
        execute("UPDATE Employees SET salary=%s WHERE user_id=%s", (req.salary, id))
    return {"status": "updated"}

@app.delete("/api/v1/manager/users/{id}")
def delete_user(id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Users WHERE user_id=%s", (id,))
    return {"status": "deleted"}

@app.get("/api/v1/manager/waste")
def list_waste(user=Depends(require_role("manager"))):
    return query("SELECT * FROM Waste_Records ORDER BY timestamp DESC")

@app.post("/api/v1/manager/waste", status_code=201)
def log_waste(req: WasteReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_LogWaste", (req.batch_id, req.quantity))
    except Exception as e:
        raise _db_error("log_waste", e)
    return {"status": "logged"}

@app.get("/api/v1/manager/logs")
def list_logs(
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    user=Depends(require_role("manager"))
):
    lim, off = _clamp_page(limit, offset)
    where, params = [], []
    if from_date:
        where.append("timestamp >= %s"); params.append(from_date)
    if to_date:
        where.append("timestamp < DATE_ADD(%s, INTERVAL 1 DAY)"); params.append(to_date)
    sql = "SELECT * FROM Logs"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY timestamp DESC LIMIT %s OFFSET %s"
    params.extend([lim, off])
    return query(sql, tuple(params))


@app.get("/api/v1/manager/sales")
def list_sales(
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    user=Depends(require_role("manager"))
):
    lim, off = _clamp_page(limit, offset, default_limit=500)
    where, params = [], []
    if from_date:
        where.append("mo.order_time >= %s"); params.append(from_date)
    if to_date:
        where.append("mo.order_time < DATE_ADD(%s, INTERVAL 1 DAY)"); params.append(to_date)
    sql = ("SELECT sh.*, i.name AS item_name, o.name AS occasion_name, mo.order_time "
           "FROM Sales_History sh "
           "JOIN Items i ON sh.item_id=i.item_id "
           "JOIN Occasions o ON sh.occasion_id=o.occasion_id "
           "JOIN Menu_Orders mo ON sh.menu_order_id=mo.menu_order_id")
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY mo.order_time DESC LIMIT %s OFFSET %s"
    params.extend([lim, off])
    return query(sql, tuple(params))


@app.get("/api/v1/manager/compliance")
def list_compliance(
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
    limit: Optional[int] = None,
    offset: Optional[int] = None,
    user=Depends(require_role("manager"))
):
    lim, off = _clamp_page(limit, offset)
    where, params = [], []
    if from_date:
        where.append("inspection_date >= %s"); params.append(from_date)
    if to_date:
        where.append("inspection_date < DATE_ADD(%s, INTERVAL 1 DAY)"); params.append(to_date)
    sql = ("SELECT compliance_record_id AS id, compliance_record_id, "
           "inspection_date, status, description FROM Compliance_Records")
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY inspection_date DESC LIMIT %s OFFSET %s"
    params.extend([lim, off])
    return query(sql, tuple(params))

@app.post("/api/v1/manager/compliance", status_code=201)
def log_compliance(req: ComplianceReq, user=Depends(require_role("manager"))):
    call_proc("sp_LogCompliance", (req.status, req.description))
    return {"status": "logged"}

@app.post("/api/v1/manager/weather", status_code=201)
def record_weather(req: WeatherReq, user=Depends(require_role("manager"))):
    call_proc("sp_RecordWeather", (req.date, req.temperature, req.humidity))
    return {"status": "recorded"}

@app.get("/api/v1/manager/alerts")
def list_alerts(user=Depends(require_role("manager"))):
    return query(
        "SELECT a.alert_id, a.message, al.created_at FROM Alerts a "
        "JOIN Alerted al ON a.alert_id=al.alert_id "
        "WHERE al.user_id=%s ORDER BY al.created_at DESC LIMIT 50",
        (user["user_id"],)
    )


@app.post("/api/v1/manager/batches", status_code=201)
def add_batch_mgr(req: ManagerBatchReq, user=Depends(require_role("manager"))):
    try:
        execute(
            "INSERT INTO Inventory_Batches "
            "(purchase_date, expiry_date, quantity, unit, cost, status, supplier_id, ingredient_id) "
            "VALUES (NOW(), %s, %s, %s, %s, %s, %s, %s)",
            (req.expiry_date, req.quantity, req.unit, req.cost, req.status,
             req.supplier_id, req.ingredient_id)
        )
    except Exception as e:
        raise _db_error("add_batch_mgr", e)
    return {"status": "created"}


@app.get("/api/v1/manager/weather")
def list_weather(user=Depends(require_role("manager"))):
    return query("SELECT * FROM Weather_Data ORDER BY date DESC LIMIT 365")


@app.get("/api/v1/manager/occasions")
def list_occasions(user=Depends(require_role("manager"))):
    return query("SELECT * FROM Occasions ORDER BY date DESC, name ASC")


@app.post("/api/v1/manager/occasions", status_code=201)
def add_occasion(req: OccasionReq, user=Depends(require_role("manager"))):
    try:
        execute(
            "INSERT INTO Occasions (name, date) VALUES (%s, %s) "
            "ON DUPLICATE KEY UPDATE date=VALUES(date)",
            (req.name, req.date)
        )
    except Exception as e:
        raise _db_error("add_occasion", e)
    return {"status": "created"}


@app.delete("/api/v1/manager/occasions/{occasion_id}")
def delete_occasion(occasion_id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Occasions WHERE occasion_id=%s", (occasion_id,))
    return {"status": "deleted"}


@app.get("/api/v1/manager/nutrition")
def list_nutrition(user=Depends(require_role("manager"))):
    return query(
        "SELECT n.*, i.name AS item_name FROM Nutritional_Info n "
        "JOIN Items i ON n.item_id=i.item_id ORDER BY i.name"
    )


@app.get("/api/v1/manager/nutrition/{item_id}")
def get_nutrition(item_id: int, user=Depends(require_role("manager"))):
    row = query_one("SELECT * FROM Nutritional_Info WHERE item_id=%s", (item_id,))
    if not row:
        raise HTTPException(404, "No nutritional info for this item")
    return row


@app.post("/api/v1/manager/nutrition", status_code=201)
def upsert_nutrition(req: NutritionReq, user=Depends(require_role("manager"))):
    try:
        execute(
            "INSERT INTO Nutritional_Info (item_id, calories, protein, carbs, fat, fiber) "
            "VALUES (%s,%s,%s,%s,%s,%s) "
            "ON DUPLICATE KEY UPDATE "
            "calories=VALUES(calories), protein=VALUES(protein), carbs=VALUES(carbs), "
            "fat=VALUES(fat), fiber=VALUES(fiber)",
            (req.item_id, req.calories, req.protein, req.carbs, req.fat, req.fiber)
        )
    except Exception as e:
        raise _db_error("upsert_nutrition", e)
    return {"status": "saved"}


@app.delete("/api/v1/manager/nutrition/{item_id}")
def delete_nutrition(item_id: int, user=Depends(require_role("manager"))):
    execute("DELETE FROM Nutritional_Info WHERE item_id=%s", (item_id,))
    return {"status": "deleted"}


# ── Forecasting (Phase 9) ─────────────────────────────────────────────────────

@app.post("/api/v1/manager/forecast/minstocks/run")
def run_minstock_forecast(req: ForecastRunReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_RecomputeMinStocks", (req.target_date, req.safety or 1.5))
    except Exception as e:
        raise _db_error("run_minstock_forecast", e)
    return {"status": "computed", "target_date": req.target_date}


@app.post("/api/v1/manager/forecast/pricing/run")
def run_pricing_forecast(req: ForecastRunReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_RecomputePricing", (req.target_date,))
    except Exception as e:
        raise _db_error("run_pricing_forecast", e)
    return {"status": "computed", "target_date": req.target_date}


@app.post("/api/v1/manager/forecast/minstocks/apply")
def apply_minstock_forecast(req: ForecastRunReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_ApplyForecasts", (req.target_date,))
    except Exception as e:
        raise _db_error("apply_minstock_forecast", e)
    return {"status": "applied", "target_date": req.target_date}


@app.post("/api/v1/manager/forecast/pricing/apply")
def apply_pricing_forecast(req: ForecastRunReq, user=Depends(require_role("manager"))):
    try:
        call_proc("sp_ApplyPricing", (req.target_date,))
    except Exception as e:
        raise _db_error("apply_pricing_forecast", e)
    return {"status": "applied", "target_date": req.target_date}


@app.get("/api/v1/manager/forecast/minstocks")
def list_minstock_forecast(target_date: str, user=Depends(require_role("manager"))):
    return query(
        "SELECT f.forecast_id, f.ingredient_id, ing.name AS ingredient_name, "
        "       ing.unit, ing.min_stock AS current_min_stock, "
        "       f.predicted_min_stock, f.applied, f.generated_at "
        "FROM Ingredient_Reorder_Forecast f "
        "JOIN Ingredients ing ON ing.ingredient_id=f.ingredient_id "
        "WHERE f.forecast_date=%s "
        "ORDER BY ing.name",
        (target_date,)
    )


@app.get("/api/v1/manager/forecast/pricing")
def list_pricing_forecast(target_date: str, user=Depends(require_role("manager"))):
    return query(
        "SELECT o.override_id, o.item_id, i.name AS item_name, "
        "       i.price AS current_price, o.price AS suggested_price, "
        "       o.reason, o.applied, o.generated_at "
        "FROM Item_Price_Override o "
        "JOIN Items i ON i.item_id=o.item_id "
        "WHERE o.effective_date=%s "
        "ORDER BY i.name",
        (target_date,)
    )


# ── Gift codes (B18) ──────────────────────────────────────────────────────────

@app.get("/api/v1/manager/gift-codes")
def list_gift_codes(user=Depends(require_role("manager"))):
    return query(
        "SELECT gift_code_id, code, amount, type, min_order, valid_from, valid_to "
        "FROM Gift_Code ORDER BY valid_to DESC"
    )


@app.post("/api/v1/manager/gift-codes", status_code=201)
def create_gift_code(req: GiftCodeReq, user=Depends(require_role("manager"))):
    if req.type not in (0, 1):
        raise HTTPException(400, "type must be 0 (percent) or 1 (flat)")
    try:
        new_id = execute(
            "INSERT INTO Gift_Code (code, amount, type, min_order, valid_from, valid_to) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (req.code, req.amount, req.type, req.min_order, req.valid_from, req.valid_to)
        )
    except Exception as e:
        raise _db_error("create_gift_code", e)
    return {"status": "created", "gift_code_id": new_id}


@app.delete("/api/v1/manager/gift-codes/{gift_code_id}")
def delete_gift_code(gift_code_id: int, user=Depends(require_role("manager"))):
    try:
        execute("DELETE FROM Gift_Code WHERE gift_code_id=%s", (gift_code_id,))
    except Exception as e:
        raise _db_error("delete_gift_code", e)
    return {"status": "deleted"}
