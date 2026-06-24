# Raaste API

FastAPI backend for Raaste — the personal travel guide for Indian domestic travel.

## Getting Started

```bash
cd services/api
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload
```

## API Docs

- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Structure

- `app/api/v1/endpoints/` — API route handlers
- `app/models/` — SQLAlchemy models
- `app/schemas/` — Pydantic request/response schemas
- `app/services/` — Business logic
- `app/core/` — Security, constants, exceptions
