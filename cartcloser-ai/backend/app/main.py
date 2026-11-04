"""CartCloser AI demo backend (FastAPI)."""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import router
from app.config import get_settings
from app.db.session import Base, SessionLocal, engine
from app.integrations.webhooks import router as webhook_router
from app.models import entities  # noqa: F401  (register tables)
from app.models.entities import Tenant
from app.services import commerce
from app.services.seed import reset_and_seed
from app.services.support import DomainError

log = logging.getLogger("cartcloser")


async def scheduler_loop(stop: asyncio.Event) -> None:
    interval = get_settings().scheduler_interval_seconds
    while not stop.is_set():
        try:
            await asyncio.to_thread(_tick)
        except Exception:  # never let the scheduler die during a live demo
            log.exception("scheduler tick failed")
        try:
            await asyncio.wait_for(stop.wait(), timeout=interval)
        except asyncio.TimeoutError:
            pass


def _tick() -> None:
    db = SessionLocal()
    try:
        commerce.run_due(db)
    finally:
        db.close()


def init_db(auto_seed: bool = True) -> None:
    """Local demo convenience: create tables (Alembic is used for Postgres) and seed if empty."""
    Base.metadata.create_all(engine)
    if auto_seed:
        db = SessionLocal()
        try:
            if db.get(Tenant, "urbanthread-pk") is None:
                reset_and_seed(db)
        finally:
            db.close()


def create_app(run_scheduler: bool = True) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        init_db()
        stop = asyncio.Event()
        task = asyncio.create_task(scheduler_loop(stop)) if run_scheduler else None
        yield
        stop.set()
        if task:
            await task

    s = get_settings()
    app = FastAPI(title="CartCloser AI API", version="0.1.0", lifespan=lifespan,
                  description="Consent-based abandoned-checkout recovery. DEMO tenant UrbanThread PK is fictional. "
                              "Messaging is simulated; Shopify/WooCommerce/WhatsApp are not connected.")
    app.add_middleware(CORSMiddleware, allow_origins=[o.strip() for o in s.cors_origins.split(",")], allow_methods=["*"],
                       allow_headers=["*"])

    @app.exception_handler(DomainError)
    async def domain_error(_: Request, exc: DomainError):
        return JSONResponse(status_code=exc.status, content={"error": exc.code, "message": exc.message})

    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, exc: RequestValidationError):
        first = exc.errors()[0] if exc.errors() else {}
        loc = ".".join(str(x) for x in first.get("loc", []))
        return JSONResponse(status_code=422, content={"error": "validation_error", "message": f"{loc}: {first.get('msg', 'invalid')}",
                                                      "details": [{"loc": e.get("loc"), "msg": e.get("msg")} for e in exc.errors()]})

    app.include_router(router)
    app.include_router(webhook_router)
    return app


app = create_app()
