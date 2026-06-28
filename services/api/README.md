# Raaste API

FastAPI backend for Raaste â€” the personal travel guide for Indian domestic travel.

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

- `app/api/v1/endpoints/` â€” API route handlers
- `app/models/` â€” SQLAlchemy models
- `app/schemas/` â€” Pydantic request/response schemas
- `app/services/` â€” Business logic
- `app/core/` â€” Security, constants, exceptions
## Checklist Cron

Apply the Supabase migration in `supabase/migrations/20260627000200_create_trip_checklists.sql`, then set these backend environment variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OPENAI_API_KEY`
- `OPENAI_MODEL` (optional, defaults to `gpt-4o-mini`)
- `CRON_SECRET`

Render Cron can run daily at 6 AM IST and trigger checklist generation with either option:

```bash
python -m app.jobs.generate_checklists
```

or call the API:

```bash
curl -X POST "$API_URL/api/v1/checklists/cron/run-due" \
  -H "Content-Type: application/json" \
  -H "X-Cron-Secret: $CRON_SECRET" \
  -d "{}"
```

The job generates checklists only when due and uses `(trip_id, checklist_type, checklist_date)` to avoid duplicates. Push notifications are intentionally not sent yet.

