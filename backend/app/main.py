import logging
import uuid

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .config import Settings, load_settings
from .db import Base, add_missing_columns, make_engine, make_session_factory
from .migrate import require_up_to_date
from .ratelimit import SlidingWindowLimiter
from . import companion as companion_mod
from . import push as push_mod
from .routers import auth, care, companion, devices, patients
from .sms import SmsProvider, get_provider

log = logging.getLogger("smriti")


def create_app(settings: Settings | None = None, sms: SmsProvider | None = None,
               companion_provider=None, push_provider=None) -> FastAPI:
    s = settings or load_settings()
    app = FastAPI(title="Smriti Sathi API", version="1.0",
                  docs_url=None if s.is_prod else "/docs",
                  redoc_url=None, openapi_url=None if s.is_prod else "/openapi.json")
    engine = make_engine(s.database_url)
    if s.is_prod:
        require_up_to_date(engine)  # tables are only ever changed by `alembic upgrade head`
    else:
        Base.metadata.create_all(engine)
        add_missing_columns(engine, Base.metadata)
    app.state.settings = s
    app.state.engine = engine
    app.state.sessionmaker = make_session_factory(engine, {"audit_key": s.secret_key})
    app.state.sms = sms or get_provider(s)
    app.state.push = push_provider or push_mod.get_provider(s.push_provider)
    app.state.companion = companion_provider or companion_mod.get_provider(
        s.companion_provider, s.companion_model)
    app.state.limiter = SlidingWindowLimiter(s.requests_per_minute_ip, 60)

    @app.middleware("http")
    async def guard(request: Request, call_next):
        rid = uuid.uuid4().hex[:12]
        # Body size cap (checked from the declared length).
        try:
            declared = int(request.headers.get("content-length", "0"))
        except ValueError:
            declared = 0
        if declared > s.max_body_bytes:
            return JSONResponse({"detail": "payload_too_large"}, status_code=413)
        # Per-IP request limit.
        fwd = request.headers.get("x-forwarded-for", "").split(",")[0].strip()
        ip = fwd if (s.trust_proxy and fwd) else (request.client.host if request.client else "?")
        if not app.state.limiter.allow(ip):
            return JSONResponse({"detail": "too_many_requests"}, status_code=429,
                                headers={"Retry-After": "60"})
        try:
            response = await call_next(request)
        except Exception:
            # Never leak internals; log without request data (no phone numbers).
            log.exception("unhandled error rid=%s path=%s", rid, request.url.path)
            response = JSONResponse({"detail": "server_error", "request_id": rid},
                                    status_code=500)
        response.headers["X-Request-ID"] = rid
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
        return response

    @app.get("/healthz")
    def healthz():
        return {"status": "ok"}

    app.include_router(auth.router)
    app.include_router(patients.router)
    app.include_router(care.router)
    app.include_router(companion.router)
    app.include_router(devices.router)
    return app
