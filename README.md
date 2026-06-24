<p align="center">
  <img src="raaste_logo.png" alt="Raaste Logo" width="160">
</p>

<h1 align="center">Raaste</h1>

<p align="center">
  <strong>Explore India like a local.</strong><br>
  A personal travel guide that helps you research, plan, and experience Indian domestic travel—before, during, and after your trip.
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
  <img alt="FastAPI" src="https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white">
  <img alt="PostgreSQL" src="https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white">
  <img alt="Supabase" src="https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white">
  <img alt="OpenAI" src="https://img.shields.io/badge/OpenAI-412991?logo=openai&logoColor=white">
</p>

---

## 📱 App Preview

| Opening Screen | Welcome Screen | Login |
|:--:|:--:|:--:|
| <img src="raaste_openingscreen.png" width="240"> | <img src="raaste_welcomescreen.png" width="240"> | <img src="raaste_login.png" width="240"> |

| Sign Up | Home | Explore |
|:--:|:--:|:--:|
| <img src="raaste_signup.png" width="240"> | <img src="raaste_homepage.png" width="240"> | <img src="raaste_explore.png" width="240"> |

| Profile |
|:--:|
| <img src="raaste_profile.png" width="240"> |

---

## ✨ What is Raaste?

Raaste is your AI-powered travel companion for exploring India. Whether you are planning a weekend getaway to the Western Ghats, a heritage walk in Rajasthan, or a food trail in South India, Raaste gives you local insights, smart itineraries, and real-time guidance.

The product is built around three phases:

1. **Researcher (Before Trip)** — Discover destinations, read curated guides, and build a personalized itinerary.
2. **Companion (During Trip)** — Ask questions, get local tips, find food and activities, and access offline guidance.
3. **Debrief (After Trip)** — Share reviews and feedback that improve the guide for future travelers.

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile app | Flutter |
| Backend API | Python + FastAPI |
| Database | PostgreSQL |
| Auth & realtime | Supabase |
| Cache & tasks | Redis + Celery |
| AI | OpenAI / LLM providers |

---

## 📁 Monorepo Structure

```
Raaste/
├── apps/
│   └── mobile/              # Flutter app
├── services/
│   └── api/                 # FastAPI backend
├── docs/                    # Product & architecture docs
├── docker-compose.yml       # Local infrastructure
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (stable)
- Python 3.11+
- Docker & Docker Compose (for Postgres/Redis)

### Mobile

```bash
cd apps/mobile
flutter pub get
flutter run
```

The mobile app expects a `.env` file in `apps/mobile/` with your Supabase credentials:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

### Backend

```bash
cd services/api
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload
```

The backend `.env` should include your database URL, OpenAI key, and JWT secret.

### Infrastructure

```bash
docker-compose up -d
```

This starts PostgreSQL and Redis for local development.

---

## 📡 Backend API

FastAPI auto-generates interactive docs at:

- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

Key endpoint groups:

- `POST /api/v1/auth/otp/send` — Request an OTP
- `POST /api/v1/auth/otp/verify` — Verify OTP and receive a JWT
- `GET /api/v1/destinations` — Browse/search destinations
- `GET /api/v1/destinations/{slug}` — Destination details
- `POST /api/v1/trips` — Create a trip
- `GET /api/v1/trips/{trip_id}` — Get trip itinerary
- `POST /api/v1/companion/ask` — Ask the AI travel companion
- `POST /api/v1/reviews` — Submit a post-trip review

See [`docs/API_CONTRACTS.md`](docs/API_CONTRACTS.md) for the full contract.

---

## 🏗 Architecture

- **Mobile:** Clean Architecture-inspired layers with BLoC state management, `go_router` navigation, `get_it` dependency injection, and Dio networking.
- **Backend:** Layered FastAPI app with endpoints, services, SQLAlchemy models, and Pydantic schemas.

Full details are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## 📄 Documentation

- [`docs/PRODUCT_CONTEXT.md`](docs/PRODUCT_CONTEXT.md) — Product vision, target audience, phases, and monetisation model
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — System architecture and tech decisions
- [`docs/API_CONTRACTS.md`](docs/API_CONTRACTS.md) — Backend API contracts

---

## 🧪 Running Tests

### Backend

```bash
cd services/api
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pytest
```

### Mobile

```bash
cd apps/mobile
flutter test
```

---

## 🤝 Contributing

Raaste is an active work in progress. If you want to contribute, start by reading the docs in the `docs/` folder and then pick up an open issue or improvement area.

---

## 📝 License

This project is proprietary and maintained by the Raaste team.

---

<p align="center">
  Made with ❤️ for travelers in India.
</p>
