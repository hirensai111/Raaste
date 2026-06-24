# Raaste — API Contracts

## Authentication

JWT Bearer token required for most endpoints.

## Destinations

### `GET /api/v1/destinations`
List/search destinations.

**Query params:** `q` (optional search string)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "...",
      "slug": "goa",
      "name": "Goa",
      "state": "Goa",
      "tagline": "Beaches, seafood, and laid-back vibes",
      "tags": ["beaches", "nightlife", "food"]
    }
  ]
}
```

### `GET /api/v1/destinations/{slug}`
Get full destination briefing.

## Trips

### `POST /api/v1/trips`
Create a trip and generate itinerary.

**Body:**
```json
{
  "destination_id": "...",
  "days": 4,
  "profile": {
    "dietary_preferences": ["vegetarian"],
    "travel_style": "mid_range_explorer",
    "travel_companion": "friends",
    "interests": ["food", "beaches"],
    "budget_min": "3000",
    "budget_max": "8000"
  }
}
```

### `GET /api/v1/trips/{trip_id}`
Get trip with itinerary and checklist.

## Companion

### `POST /api/v1/companion/ask`
Ask a contextual question during the trip.

**Body:**
```json
{
  "trip_id": "...",
  "query": "Where should I eat Jain food near me?",
  "lat": 15.2993,
  "lon": 74.1240
}
```

## Reviews

### `POST /api/v1/reviews`
Submit post-trip debrief.

**Body:**
```json
{
  "trip_id": "...",
  "destination_id": "...",
  "what_was_great": "...",
  "what_was_disappointing": "...",
  "what_is_outdated": "...",
  "rating": 4
}
```
