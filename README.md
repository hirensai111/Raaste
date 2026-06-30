<p align="center">
  <img src="raaste_logo.png" alt="Raaste Logo" width="160">
</p>

<h1 align="center">Raaste</h1>

<p align="center">
  <strong>Explore India like a local.</strong><br>
  A personal, AI-powered travel guide for Indian domestic travel — before you go, while you're there, and after you leave.
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

Raaste is an AI travel guide for Indian domestic travel — like having a well-travelled local friend who's already been everywhere and tells you what's actually worth it, how transport really works, what things should cost, and where the locals eat. **Not a booking app. Not a delivery app. A guide.**

It's built around the Indian traveller specifically: Uber doesn't work everywhere, local cab rates are negotiable, Jain/Halal/Veg requirements are serious, monsoon changes what's accessible, and a ₹500 trip and a ₹5,000 trip need completely different advice.

The app is organized around three travel phases:

1. **Researcher (Before Trip)** — A specific, opinionated pre-trip briefing: how transport works, real costs, what's worth it vs. tourist traps, a day-by-day plan tuned to your interests, what to pack, and local customs.
2. **Companion (During Trip)** — Ask the guide anything about where you are right now. It knows your preferences, so it won't send a Jain traveller to a non-veg place.
3. **Debrief (After Trip)** — A quick review that feeds the knowledge base and improves the guide for the next traveller.

> ⚠️ All prices and timings are a research starting point, not a real-time database — the app always tells you to confirm directly.

---

## 🚀 Features

> Legend: ✅ working · 🟡 partial / wired but thin · 🔲 placeholder / planned

### Mobile App (Flutter)

- ✅ **Authentication** — Email/password and Google sign-in via Supabase Auth.
- ✅ **Onboarding & Profile Setup** — One-time travel style, dietary preference, companions, budget, and interests. These feed directly into AI prompts.
- ✅ **Home Dashboard** — Personalized greeting, destination search, dietary/travel-style filters, trip phase cards, current trip, and popular destinations.
- ✅ **Destination Detail + Chat** — Research-backed destination pages and a conversational chat that answers in the traveller's voice, respecting their profile. This is the app's strongest feature.
- ✅ **AI Itinerary Generation** — Day-by-day plans generated from bundled research, routing data (Google Route Matrix), and the user's interests + dietary rules.
- ✅ **Food & Restaurants** — Restaurant recommendations filtered by dietary tags (Veg / Non-veg / Jain / Halal / Vegan / Eggetarian) with strict, non-negotiable filtering logic.
- ✅ **Checklists** — AI-generated trip checklists synced via Supabase.
- ✅ **My Trips** — Save and manage trips (Supabase-backed).
- 🟡 **Explore** — UI exists, but the `explore` route currently renders the Food screen and most tiles show "Implementing Soon."
- 🔲 **Companion (in-trip Q&A)** — Screen scaffolded; the ask handler is a `TODO`. The real conversational AI today lives in **Destination Chat**.
- 🟡 **Profile** — View/edit basics; several settings rows are "Implementing Soon."

> **Data coverage:** AI features are grounded in hand-curated research JSON. Today that covers **3 destinations — Lonavala, Varanasi, and Hyderabad.** Everything else is a placeholder.

### Backend API (FastAPI) — *parallel track, not yet wired to the app*

A full FastAPI service exists (auth, destinations, trips, checklists, companion, reviews, profile) but **the mobile app does not currently call it.** The app talks to **OpenAI and Supabase directly.** The backend is the intended home for AI calls and shared data, but that migration hasn't happened yet — see [Honest Status](#-honest-status--what-is-actually-built).

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile app | Flutter, Dart |
| State management | BLoC / `flutter_bloc` |
| Navigation | `go_router` |
| Dependency injection | `get_it` |
| Networking | `dio`, Supabase client |
| Local storage | `shared_preferences` |
| Backend API | Python + FastAPI |
| Database | PostgreSQL |
| Auth & realtime | Supabase Auth / Supabase realtime |
| Cache & tasks | Redis + Celery |
| AI / LLM | OpenAI GPT |

---

## 📁 Monorepo Structure

```
Raaste/
├── apps/
│   └── mobile/                    # Flutter app
│       ├── lib/features/          # Feature-first modules
│       │   ├── auth/
│       │   ├── home/
│       │   ├── explore/
│       │   ├── destination/       # Destination detail + destination chat
│       │   ├── food/              # Restaurant recommendations
│       │   ├── trip/              # Trip planning, itinerary, saved trips
│       │   ├── checklist/         # AI-generated trip checklists
│       │   ├── companion/         # AI travel companion
│       │   ├── profile/
│       │   └── onboarding/
│       └── assets/research/       # Destination research JSON assets
├── services/
│   └── api/                       # FastAPI backend
│       ├── app/api/v1/endpoints/  # API routes
│       ├── app/services/          # Business logic
│       ├── app/models/            # SQLAlchemy models
│       ├── app/schemas/           # Pydantic schemas
│       └── app/jobs/              # Background jobs (Celery)
├── supabase/
│   └── migrations/                # Supabase SQL migrations
├── docs/                          # Product & architecture docs
├── docker-compose.yml             # Local infrastructure
└── README.md
```

---

## 🏗 Architecture

- **Mobile:** Feature-first, Clean Architecture-inspired folders (`data`, `domain`, `presentation`). BLoC handles auth state; screens use `StatefulWidget` + repositories. `go_router` manages navigation.
- **Backend:** Layered FastAPI app — endpoints → services → SQLAlchemy models, with Pydantic schemas. Currently developed in parallel and **not yet consumed by the mobile app.**
- **Actual data flow today:** Destination research ships as JSON assets in the app. Trips, checklists, and saved data sync with **Supabase** directly. **AI features call OpenAI directly from the device** using a key in the app's `.env`.

> 🔐 **Security note:** Calling OpenAI directly from the mobile app means the API key is shipped inside the build and can be extracted. Before any real release, AI calls must be proxied through the FastAPI backend (which already exists) so the key stays server-side. This is the single most important pre-launch fix.

Full details are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.7+ (stable)
- Python 3.11+
- Docker & Docker Compose (for Postgres/Redis)
- A Supabase project
- An OpenAI API key

### Mobile

```bash
cd apps/mobile
cp .env.example .env   # Add your SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter run
```

Required `.env` variables:

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
cp .env.example .env       # Add DATABASE_URL, OPENAI_API_KEY, SECRET_KEY, etc.
uvicorn app.main:app --reload
```

### Supabase Migrations

Apply the SQL migrations in `supabase/migrations/` to your Supabase project to create tables for saved trips, checklists, and restaurants.

### Infrastructure (local)

```bash
docker-compose up -d
```

This starts PostgreSQL and Redis for local development.

---

## 📡 Backend API

FastAPI auto-generates interactive docs at:

- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

Key endpoints:

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/otp/send` | Request an OTP |
| POST | `/api/v1/auth/otp/verify` | Verify OTP and receive a JWT |
| GET | `/api/v1/destinations` | Browse/search destinations |
| GET | `/api/v1/destinations/{slug}` | Destination details |
| POST | `/api/v1/trips` | Create a trip |
| GET | `/api/v1/trips/{trip_id}` | Get trip itinerary |
| GET/POST | `/api/v1/checklists/*` | Generate and manage checklists |
| POST | `/api/v1/companion/ask` | Ask the AI travel companion |
| POST | `/api/v1/reviews` | Submit a post-trip review |
| GET/PUT | `/api/v1/profile/me` | User profile |

See [`docs/API_CONTRACTS.md`](docs/API_CONTRACTS.md) for the full contract.

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
flutter analyze
```

---

## 📄 Documentation

- [`docs/PRODUCT_CONTEXT.md`](docs/PRODUCT_CONTEXT.md) — Product vision, target audience, the three phases, and monetisation model
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — System architecture and tech decisions
- [`docs/API_CONTRACTS.md`](docs/API_CONTRACTS.md) — Backend API contracts

---

## 🧭 Honest Status — what is actually built

**Working today (real, end-to-end):**
- [x] Splash, onboarding, profile setup, auth (email + Google via Supabase)
- [x] Home dashboard with search and filters
- [x] Destination detail + **Destination Chat** (the real AI guide, profile-aware)
- [x] AI itinerary generation grounded in research + routing + dietary rules
- [x] Restaurant recommendations with strict dietary filtering (Veg/Jain/Halal/Vegan/etc.)
- [x] AI-generated checklists, synced via Supabase
- [x] Saved trips (My Trips)
- [x] A complete FastAPI backend (exists, runs, has tests — but unused by the app)
- [x] Supabase migrations for trips, checklists, restaurants

**Partial / scaffolded:**
- [ ] **Explore** — UI exists but routes to the Food screen; most tiles are "Implementing Soon"
- [ ] **Companion (in-trip)** — screen exists, ask handler is a `TODO`
- [ ] **Profile settings** — several rows are placeholders

**Not started:**
- [ ] **Backend ↔ mobile integration** (today the app calls OpenAI + Supabase directly)
- [ ] **Securing the OpenAI key** behind the backend ← do this first
- [ ] **Post-trip Debrief / review flow** in the app
- [ ] **Real offline mode** beyond the 3 bundled research files
- [ ] **Monetisation** — trip passes (₹29–49), contextual ads, verified partners
- [ ] **Data coverage** — only 3 destinations have research; the core promise needs a content pipeline
- [ ] **Automated content generation** — research is hand-curated JSON; this won't scale to "all of India" manually

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
