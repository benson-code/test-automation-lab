"""HTTP 路由。啟動：

    DB_PATH=wallet.db .venv/bin/uvicorn app.main:app --port 8400
"""
from __future__ import annotations

import os
from collections.abc import Iterator
from pathlib import Path

from fastapi import Depends, FastAPI, Header, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field

from app import bugs, service
from app.db import connect, init_db
from app.errors import ApiError
from app.responses import (Health, Payment, PaymentDetail, Refund, TopUp, Transactions, Transfer, Wallet,
                           errors, ok)

DB_PATH = os.environ.get("DB_PATH", "wallet.db")
init_db(DB_PATH)

app = FastAPI(title="test-automation-lab")


# ---- 錯誤：全部轉成統一格式 ---------------------------------------------------

@app.exception_handler(ApiError)
def handle_api_error(_: Request, e: ApiError) -> JSONResponse:
    return JSONResponse(status_code=e.status, content={"error_code": e.error_code, "message": e.message})


@app.exception_handler(RequestValidationError)
def handle_validation_error(_: Request, e: RequestValidationError) -> JSONResponse:
    # FastAPI 預設回 422 和一大串細節；改成跟其他錯誤一樣的格式
    first = e.errors()[0]
    field = ".".join(str(p) for p in first["loc"] if p != "body")
    return JSONResponse(status_code=400, content={"error_code": "INVALID_REQUEST",
                                                  "message": f"{field}: {first['msg']}"})


def get_conn() -> Iterator:
    conn = connect(DB_PATH)
    try:
        yield conn
    finally:
        conn.close()


# ---- 請求格式 ------------------------------------------------------------------
# amount 宣告成 object 而不是 str：讓「傳數字」這種錯誤進到 parse_amount，
# 回傳跟其他金額錯誤一樣的 INVALID_AMOUNT，而不是 pydantic 的通用訊息。
# API 文件上照合約寫成必填的字串（json_schema_extra 只影響文件，不影響收到什麼）。

AMOUNT = Field(default=None, json_schema_extra={"type": "string", "examples": ["100.50"]})
WALLET_ID = Field(default=None, json_schema_extra={"type": "string", "examples": ["w_2b440cba3a8c4d27"]})


def required(*fields: str) -> ConfigDict:
    return ConfigDict(json_schema_extra={"required": list(fields)})


class CreateWallet(BaseModel):
    owner: str


class AmountBody(BaseModel):
    model_config = required("amount")
    amount: object = AMOUNT


class PaymentBody(BaseModel):
    model_config = required("wallet_id", "amount")
    wallet_id: object = WALLET_ID
    amount: object = AMOUNT


class TransferBody(BaseModel):
    model_config = required("from_wallet_id", "to_wallet_id", "amount")
    from_wallet_id: object = WALLET_ID
    to_wallet_id: object = WALLET_ID
    amount: object = AMOUNT


# ---- 路由 ----------------------------------------------------------------------
# responses：寫進 API 文件的回應格式和錯誤（app/responses.py）。response_model=None：
# FastAPI 不拿任何模型去驗證或改寫實際回應，回應照 service.py 組出來的原樣送出。

KEY_ERRORS = "IDEMPOTENCY_KEY_REQUIRED, INVALID_REQUEST, INVALID_AMOUNT"


@app.get("/health", response_model=None, responses=ok(Health))
def health() -> dict:
    # 回報目前開了哪些 bug：CI 的「證明測試會紅」那一輪，要先確認開關真的有打開
    return {"status": "ok", "bugs": sorted(bugs.ACTIVE)}


@app.post("/wallets", status_code=201, response_model=None,
          responses={**ok(Wallet, 201), **errors({400: "INVALID_OWNER, INVALID_REQUEST"})})
def create_wallet(body: CreateWallet, conn=Depends(get_conn)) -> dict:
    return service.create_wallet(conn, body.owner)


@app.get("/wallets/{wallet_id}", response_model=None,
         responses={**ok(Wallet), **errors({404: "WALLET_NOT_FOUND"})})
def get_wallet(wallet_id: str, conn=Depends(get_conn)) -> dict:
    return service.wallet_view(service.get_wallet_row(conn, wallet_id))


@app.post("/wallets/{wallet_id}/topups", status_code=201, response_model=None,
          responses={**ok(TopUp, 201),
                     **errors({400: "INVALID_AMOUNT, INVALID_REQUEST", 404: "WALLET_NOT_FOUND"})})
def top_up(wallet_id: str, body: AmountBody, conn=Depends(get_conn)) -> dict:
    return service.top_up(conn, wallet_id, body.amount)


@app.post("/payments", status_code=201, response_model=None,
          responses={**ok(Payment, 201, replay=True),
                     **errors({400: KEY_ERRORS, 404: "WALLET_NOT_FOUND", 409: "INSUFFICIENT_BALANCE",
                               422: "IDEMPOTENCY_KEY_REUSED, LIMIT_EXCEEDED"})})
def pay(body: PaymentBody, idempotency_key: str | None = Header(default=None),
        conn=Depends(get_conn)) -> JSONResponse:
    # Header(...) 會把參數名 idempotency_key 對應到 HTTP header「Idempotency-Key」
    status, response, replayed = service.pay(conn, idempotency_key, body.model_dump())
    return JSONResponse(status_code=status, content=response,
                        headers={"Idempotent-Replayed": "true" if replayed else "false"})


@app.get("/payments/{payment_id}", response_model=None,
         responses={**ok(PaymentDetail), **errors({404: "PAYMENT_NOT_FOUND"})})
def get_payment(payment_id: str, conn=Depends(get_conn)) -> dict:
    return service.get_payment(conn, payment_id)


@app.post("/payments/{payment_id}/refunds", status_code=201, response_model=None,
          responses={**ok(Refund, 201, replay=True),
                     **errors({400: KEY_ERRORS, 404: "PAYMENT_NOT_FOUND", 409: "REFUND_EXCEEDS_PAYMENT",
                               422: "IDEMPOTENCY_KEY_REUSED"})})
def refund(payment_id: str, body: AmountBody, idempotency_key: str | None = Header(default=None),
           conn=Depends(get_conn)) -> JSONResponse:
    status, response, replayed = service.refund(conn, idempotency_key, payment_id, body.model_dump())
    return JSONResponse(status_code=status, content=response,
                        headers={"Idempotent-Replayed": "true" if replayed else "false"})


@app.get("/wallets/{wallet_id}/transactions", response_model=None,
         responses={**ok(Transactions), **errors({404: "WALLET_NOT_FOUND"})})
def transactions(wallet_id: str, conn=Depends(get_conn)) -> dict:
    return service.transactions(conn, wallet_id)


@app.post("/transfers", status_code=201, response_model=None,
          responses={**ok(Transfer, 201, replay=True),
                     **errors({400: KEY_ERRORS, 404: "WALLET_NOT_FOUND", 409: "INSUFFICIENT_BALANCE",
                               422: "IDEMPOTENCY_KEY_REUSED, SAME_WALLET, LIMIT_EXCEEDED"})})
def transfer(body: TransferBody, idempotency_key: str | None = Header(default=None),
             conn=Depends(get_conn)) -> JSONResponse:
    status, response, replayed = service.transfer(conn, idempotency_key, body.model_dump())
    return JSONResponse(status_code=status, content=response,
                        headers={"Idempotent-Replayed": "true" if replayed else "false"})


# ---- API 文件 ------------------------------------------------------------------

_generate_openapi = app.openapi
FASTAPI_422 = {"$ref": "#/components/schemas/HTTPValidationError"}
IDEMPOTENCY_KEY = {"name": "idempotency-key", "in": "header", "required": True,
                   "description": "a new key for each new request; a retry resends the same key",
                   "schema": {"type": "string", "minLength": 1, "maxLength": 64}}


def _json_schema(response: dict) -> dict | None:
    return response.get("content", {}).get("application/json", {}).get("schema")


def openapi() -> dict:
    """API 文件（/openapi.json，/docs 畫的就是它），改掉 FastAPI 自動產生、卻和實際不符的兩處：

    - 每個有參數的路由都有「422 Validation Error」，格式是 {"detail": [...]}。這個 API 的驗證錯誤是 400
      INVALID_REQUEST（handle_validation_error），從來不回這種 422。拿掉（CTR-004 檢查）。
    - Idempotency-Key 寫成選填：參數有預設值 None，是為了讓「沒帶」回 IDEMPOTENCY_KEY_REQUIRED，
      而不是 FastAPI 的通用驗證錯誤。文件上照實寫成必填。
    """
    doc = _generate_openapi()           # FastAPI 產生一次之後就快取起來
    for operations in doc["paths"].values():
        for op in operations.values():
            if _json_schema(op["responses"].get("422", {})) == FASTAPI_422:
                del op["responses"]["422"]
            for i, param in enumerate(op.get("parameters", [])):
                if param["name"] == "idempotency-key":
                    op["parameters"][i] = IDEMPOTENCY_KEY
    for name in ("HTTPValidationError", "ValidationError"):
        doc.get("components", {}).get("schemas", {}).pop(name, None)
    return doc


app.openapi = openapi


# ---- 手機版網頁 ----------------------------------------------------------------
# web/ 編譯後（cd web && npm run build）在 web/dist，掛在 /app：跟 API 同一個網址，網頁呼叫 API
# 不會跨網站。沒編譯過就不掛，API 照常運作（API 測試與 CI 不需要 Node）。
# WEB_DIST 環境變數可以換成別的編譯結果：tools/web_mutation_check.py 用它掛故意改壞的前端。
WEB_DIST = Path(os.environ.get("WEB_DIST") or Path(__file__).resolve().parent.parent / "web" / "dist")
if WEB_DIST.is_dir():
    app.mount("/app", StaticFiles(directory=WEB_DIST, html=True), name="web")
