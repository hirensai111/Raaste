# Raaste — Status & Gap Analysis

_Last updated: 2026-06-28_

This is the honest internal picture of what Raaste actually is today: what works end-to-end, what's scaffolded, what's missing, and what has to happen before a real launch. The marketing-facing summary lives in the README; this doc is the unvarnished version for whoever is building.

---

## TL;DR

Raaste is a **strong prototype / pre-MVP**, roughly **35–45% of the way to a launchable v1**. The core AI experience (profile-aware destination chat + grounded itinerary generation + strict dietary filtering) is genuinely good and real. The remaining work is the hard, unglamorous part — securing the AI key, building the in-trip companion, and solving content scaling — not more screens.

The idea is viable and well-timed. The risk is not the product concept; it's **content scaling** and an **unproven willingness to pay** versus free LLMs.

---

## What is actually built (real, end-to-end)

| Area | Status | Notes |
|------|--------|-------|
| Auth | ✅ | Email/password + Google via Supabase Auth |
| Onboarding & profile setup | ✅ | Travel style, dietary pref, companions, budget, interests — fed into AI prompts |
| Home dashboard | ✅ | Greeting, search, dietary/travel-style filters, trip phase cards |
| Destination detail + chat | ✅ | **The strongest feature.** Profile-aware conversational guide |
| AI itinerary generation | ✅ | Grounded in research JSON + Google Route Matrix + dietary rules |
| Restaurant recommendations | ✅ | Strict dietary filtering (Veg/Non-veg/Jain/Halal/Vegan/Eggetarian) |
| AI checklists | ✅ | Generated + synced via Supabase |
| Saved trips (My Trips) | ✅ | Supabase-backed |
| FastAPI backend | ✅ (exists) | Full service with tests — **but the app never calls it** |
| Supabase migrations | ✅ | trips, checklists, restaurants |

### Why the AI features are good, not gimmicks
- Itineraries and restaurants are **grounded** in curated research JSON, not hallucinated.
- Dietary filtering is **strict and non-negotiable** in the prompt
  (`open_ai_destination_service.dart` lines ~243–252): Jain → only Jain-available
  places, Halal → only halal, Vegan → confirm no ghee/butter/milk, etc.
- Routing uses the Google Route Matrix service so day plans respect real travel time.

This is the part of the product that delivers on the "local friend who knows your preferences" promise. Protect it.

---

## Partial / scaffolded

| Area | Status | Gap |
|------|--------|-----|
| Explore | 🟡 | UI exists, but the `explore` route renders the **Food screen**; most tiles show "Implementing Soon" |
| Companion (in-trip) | 🟡 | Screen exists; the ask handler is a `TODO`. Real chat only lives inside a destination page today |
| Profile settings | 🟡 | View/edit basics works; several settings rows are "Implementing Soon" |

---

## Not started

- **Backend ↔ mobile integration** — two parallel architectures; the app calls OpenAI + Supabase directly and ignores the FastAPI service.
- **Securing the OpenAI key** — see the security issue below. _Do this first._
- **Post-trip Debrief / review flow** in the app (phase 3 of the product — the community loop).
- **Real offline mode** beyond the 3 bundled research files.
- **Monetisation** — trip passes (₹29–49), contextual ads, verified partners.
- **Data coverage** — only 3 destinations have research.
- **Content pipeline** — research is hand-curated JSON; no path to scale.

---

## 🔐 Security issue (launch blocker)

The OpenAI API key is read from the mobile app's `.env` and sent directly from the
device (`open_ai_destination_service.dart` ~line 134; same pattern in the checklist
service). **Any published build ships the key inside it, and it can be extracted** —
allowing anyone to run up the bill.

**Fix:** proxy all AI calls through the existing FastAPI backend so the key stays
server-side. The backend already has an `AIService` and a `/companion/ask` endpoint —
the plumbing largely exists; the app just needs to call it instead of OpenAI. This is
both the security fix and the first step of backend integration, so it's a high-leverage
quick win.

---

## Content coverage (the real moat question)

Research today covers **3 destinations**: Lonavala, Varanasi, Hyderabad. Each is
hand-curated JSON. The product promise is "a local for every destination in India."

- **Manual curation** scales linearly with labour — won't reach "all of India."
- **Naive LLM auto-generation** is no better than what a user can already ask ChatGPT,
  so it provides no defensibility on its own.
- The **defensible** version is curation **+** the community Debrief loop (phase 3),
  where real traveller feedback corrects and freshens the data over time. That loop is
  **not built yet**, which means there is currently **no moat** — just three good files.

Deciding the content strategy (semi-automated research + human review + community
corrections) is the most important product decision, more than any feature.

---

## Viability assessment

**Strengths**
- Real timing: post-COVID domestic-travel boom, digitally-native weekend travellers.
- Real gap: Zomato gives ratings, Maps gives locations, YouTube gives vlogs — none give
  *judgment* personalised to who you are. The India + dietary layer is a genuine wedge.
- The hardest-to-fake part (grounded, preference-aware AI) already works.

**Risks**
- **Content scaling is the whole game** — this is a content business in an app's clothing.
- **Willingness to pay is unproven** — ₹29–49/destination must beat "just ask a free LLM."
  The bet is that curated + opinionated + offline + preference-filtered is _obviously_
  better, not merely arguably better.
- Two unconsolidated architectures add drag until integrated.

**Estimate:** ~35–45% to a launchable v1. Remaining work is the hard part, not more UI.

---

## Recommended priority order

1. **Move OpenAI calls behind the FastAPI backend.** Security blocker; backend exists.
2. **Build the real in-trip Companion.** It's the retention loop and the core pitch
   (used 4–5×/day per the product vision); currently a `TODO` stub.
3. **Solve content scaling.** Decide on semi-automated research + human review + the
   community Debrief loop. This is the moat — or the failure mode.
4. **Then** monetisation and a real Explore.

---

_See also: [`PRODUCT_CONTEXT.md`](PRODUCT_CONTEXT.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`API_CONTRACTS.md`](API_CONTRACTS.md)._
