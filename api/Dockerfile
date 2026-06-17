# /srv/dairydues/api/Dockerfile

FROM python:3.12-slim AS base

# Keep Python output unbuffered (good for Docker logs)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# --- dependency layer (cached unless requirements.txt changes) ---
FROM base AS deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- final image ---
FROM deps AS final

# Run as non-root for basic container hygiene
RUN addgroup --system api && adduser --system --ingroup api api

COPY --chown=api:api app/ ./app/

# Uploads folder — bind-mounted from the host, so just ensure it exists
RUN mkdir -p /app/uploads && chown api:api /app/uploads

USER api

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]