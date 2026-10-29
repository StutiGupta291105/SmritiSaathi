FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY alembic.ini ./
COPY migrations ./migrations

# Run as an unprivileged user.
RUN useradd --system --no-create-home smriti
USER smriti

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"

# TLS is terminated by the load balancer in front; set SMRITI_TRUST_PROXY=true
# only when that proxy is yours (it is what supplies the real client address).
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-server-header"]
