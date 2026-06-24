# Raaste — Architecture

## High-Level Design

```
┌──────────────┐      HTTPS/REST       ┌──────────────┐
│  Flutter App │ ◄──────────────────► │  FastAPI API │
└──────────────┘                       └──────┬───────┘
       │                                      │
       │ Offline cache                        │ PostgreSQL
       │ (Hive / SharedPrefs)                 │ Redis
       ▼                                      ▼
┌──────────────┐                       ┌──────────────┐
│  Local guide │                       │  Supabase    │
│  content     │                       │  Auth / RT   │
└──────────────┘                       └──────────────┘
```

## Mobile Architecture

- **State management**: flutter_bloc
- **Navigation**: go_router
- **Dependency injection**: get_it + injectable
- **Networking**: dio
- **Local storage**: Hive + shared_preferences
- **Offline**: Core destination guides cached locally

### Folder Structure

```
lib/
├── config/          # Routes, theme, app config
├── core/            # Errors, network, storage, DI, constants
├── features/        # One folder per feature (clean architecture)
│   ├── splash
│   ├── onboarding
│   ├── home
│   ├── destination
│   ├── trip
│   ├── companion
│   └── profile
└── shared/          # Reusable widgets and utilities
```

## Backend Architecture

- **Framework**: FastAPI
- **ORM**: SQLAlchemy
- **Migrations**: Alembic
- **Auth**: JWT + Supabase (planned)
- **AI**: OpenAI for companion responses
- **Cache**: Redis
- **Tasks**: Celery for background jobs

### Folder Structure

```
api/
├── app/
│   ├── api/v1/endpoints/   # Route handlers
│   ├── models/             # SQLAlchemy models
│   ├── schemas/            # Pydantic schemas
│   ├── services/           # Business logic
│   ├── core/               # Security, constants, exceptions
│   ├── config.py
│   ├── database.py
│   └── main.py
├── tests/
├── Dockerfile
└── requirements.txt
```

## Data Flow

1. User selects destination → API fetches destination briefing
2. User sets trip length + profile → API generates itinerary
3. During trip → companion queries API (or offline cache) for contextual answers
4. After trip → review data feeds back into knowledge base

## Key Design Decisions

- **Offline-first companion**: Core destination content is cached on device.
- **Price disclaimers**: Every cost has a "confirm directly" note.
- **Dietary filtering**: Hard filters at API and client level.
- **India-first**: Constants, defaults, and copy assume Indian domestic travel.
