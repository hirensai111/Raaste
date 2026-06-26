import json
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from openai import AsyncOpenAI
from supabase import Client, create_client

from app.config import settings
from app.schemas.checklist import ChecklistRunResponse

IST = ZoneInfo("Asia/Kolkata")

PRE_TRIP = "pre_trip"
IN_TRIP_DAILY = "in_trip_daily"
POST_TRIP = "post_trip"


@dataclass(frozen=True)
class TripWindow:
    start_date: date
    end_date: date
    raw_dates: str

    @property
    def total_days(self) -> int:
        return (self.end_date - self.start_date).days + 1

    def day_number(self, value: date) -> int:
        return max(1, min(self.total_days, (value - self.start_date).days + 1))


@dataclass(frozen=True)
class DueChecklist:
    checklist_type: str
    checklist_date: date
    day_number: int | None = None


class ChecklistService:
    def __init__(self, supabase_client: Client | None = None):
        self.supabase = supabase_client or self._create_supabase_client()
        self.openai = AsyncOpenAI(api_key=settings.openai_api_key)

    def list_trip_checklists(
        self,
        trip_id: str | UUID,
        user_id: str | UUID,
    ) -> list[dict[str, Any]]:
        response = (
            self.supabase.table("trip_checklists")
            .select("*")
            .eq("trip_id", str(trip_id))
            .eq("user_id", str(user_id))
            .order("checklist_date", desc=False)
            .execute()
        )
        return list(response.data or [])

    async def run_due_checklists(self, run_date: date | None = None) -> ChecklistRunResponse:
        today = run_date or datetime.now(IST).date()
        trips = self._fetch_saved_trips()
        generated = 0
        skipped = 0
        errors: list[str] = []

        for trip in trips:
            trip_id = str(trip.get("id") or "")
            try:
                window = parse_trip_window(
                    _trip_dates_text(trip),
                    reference_date=today,
                )
                if window is None:
                    skipped += 1
                    continue

                self._sync_trip_status(trip, window, today)
                due_checklists = due_checklists_for_trip(window, today)
                if not due_checklists:
                    skipped += 1
                    continue

                for due in due_checklists:
                    if self._checklist_exists(trip_id, due):
                        skipped += 1
                        continue

                    content = await self._generate_checklist(trip, window, due, today)
                    self._save_checklist(trip, window, due, content)
                    generated += 1
            except Exception as exc:  # pragma: no cover - defensive cron isolation
                skipped += 1
                label = trip.get("destination_name") or trip_id or "unknown trip"
                errors.append(f"{label}: {exc}")

        return ChecklistRunResponse(
            run_date=today,
            scanned_trips=len(trips),
            generated=generated,
            skipped=skipped,
            errors=errors,
        )

    def _fetch_saved_trips(self) -> list[dict[str, Any]]:
        response = (
            self.supabase.table("saved_trips")
            .select("*")
            .order("updated_at", desc=True)
            .execute()
        )
        return list(response.data or [])

    def _checklist_exists(self, trip_id: str, due: DueChecklist) -> bool:
        response = (
            self.supabase.table("trip_checklists")
            .select("id")
            .eq("trip_id", trip_id)
            .eq("checklist_type", due.checklist_type)
            .eq("checklist_date", due.checklist_date.isoformat())
            .limit(1)
            .execute()
        )
        return bool(response.data)

    def _save_checklist(
        self,
        trip: dict[str, Any],
        window: TripWindow,
        due: DueChecklist,
        content: dict[str, Any],
    ) -> None:
        payload = {
            "trip_id": trip["id"],
            "user_id": trip["user_id"],
            "checklist_type": due.checklist_type,
            "checklist_date": due.checklist_date.isoformat(),
            "day_number": due.day_number,
            "destination_name": _destination_name(trip),
            "trip_dates": window.raw_dates,
            "content": content,
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
        (
            self.supabase.table("trip_checklists")
            .upsert(
                payload,
                on_conflict="trip_id,checklist_type,checklist_date",
            )
            .execute()
        )

    def _sync_trip_status(
        self,
        trip: dict[str, Any],
        window: TripWindow,
        today: date,
    ) -> None:
        if today < window.start_date:
            status = "upcoming"
        elif today <= window.end_date:
            status = "active"
        else:
            status = "completed"

        if trip.get("status") == status:
            return

        (
            self.supabase.table("saved_trips")
            .update({"status": status})
            .eq("id", trip["id"])
            .execute()
        )

    async def _generate_checklist(
        self,
        trip: dict[str, Any],
        window: TripWindow,
        due: DueChecklist,
        today: date,
    ) -> dict[str, Any]:
        context = checklist_context(trip, window, due, today)
        prompt = prompt_for_due_checklist(due, context)
        fallback = fallback_checklist(due, context)

        if not settings.openai_api_key:
            return fallback

        try:
            response = await self.openai.chat.completions.create(
                model=settings.openai_model,
                messages=[
                    {
                        "role": "system",
                        "content": "Return only valid JSON. Do not use markdown.",
                    },
                    {"role": "user", "content": prompt},
                ],
                response_format={"type": "json_object"},
                temperature=0.45,
            )
            text = response.choices[0].message.content or ""
            decoded = json.loads(text)
            return decoded if isinstance(decoded, dict) else fallback
        except Exception:
            return fallback

    def _create_supabase_client(self) -> Client:
        if not settings.supabase_url:
            raise RuntimeError("SUPABASE_URL is required for checklist generation")

        key = settings.supabase_service_role_key or settings.supabase_key
        if not key:
            raise RuntimeError(
                "SUPABASE_SERVICE_ROLE_KEY or SUPABASE_KEY is required for checklist generation"
            )

        return create_client(settings.supabase_url, key)


def due_checklists_for_trip(window: TripWindow, today: date) -> list[DueChecklist]:
    due: list[DueChecklist] = []
    pre_trip_date = window.start_date - timedelta(days=14)
    post_trip_date = window.end_date + timedelta(days=1)

    if pre_trip_date <= today < window.start_date:
        due.append(DueChecklist(PRE_TRIP, pre_trip_date))

    if window.start_date <= today <= window.end_date:
        due.append(
            DueChecklist(
                IN_TRIP_DAILY,
                today,
                day_number=window.day_number(today),
            )
        )

    if today >= post_trip_date:
        due.append(DueChecklist(POST_TRIP, post_trip_date))

    return due


def parse_trip_window(raw_dates: str, reference_date: date | None = None) -> TripWindow | None:
    reference_date = reference_date or datetime.now(IST).date()
    text = normalize_date_text(raw_dates)
    if not text:
        return None

    year = _extract_year(text) or reference_date.year

    iso_matches = list(
        re.finditer(r"\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b", text)
    )
    if len(iso_matches) >= 2:
        return _window(
            raw_dates,
            int(iso_matches[0].group(1)),
            int(iso_matches[0].group(2)),
            int(iso_matches[0].group(3)),
            int(iso_matches[1].group(1)),
            int(iso_matches[1].group(2)),
            int(iso_matches[1].group(3)),
        )

    numeric = re.search(
        r"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\s*(?:-|to)\s*(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b",
        text,
    )
    if numeric:
        start_year = _normalize_year(numeric.group(3), year)
        end_year = _normalize_year(numeric.group(6), start_year)
        return _window(
            raw_dates,
            start_year,
            int(numeric.group(2)),
            int(numeric.group(1)),
            end_year,
            int(numeric.group(5)),
            int(numeric.group(4)),
        )

    day_month = re.search(
        rf"\b(\d{{1,2}})(?:st|nd|rd|th)?\s+({_MONTH_PATTERN})\s*(?:-|to)\s*(\d{{1,2}})(?:st|nd|rd|th)?(?:\s+({_MONTH_PATTERN}))?\b",
        text,
    )
    if day_month:
        start_month = _month_number(day_month.group(2))
        end_month = _month_number(day_month.group(4)) or start_month
        return _window(
            raw_dates,
            year,
            start_month,
            int(day_month.group(1)),
            year,
            end_month,
            int(day_month.group(3)),
        )

    day_range_month = re.search(
        rf"\b(\d{{1,2}})(?:st|nd|rd|th)?\s*(?:-|to)\s*(\d{{1,2}})(?:st|nd|rd|th)?\s+({_MONTH_PATTERN})\b",
        text,
    )
    if day_range_month:
        month = _month_number(day_range_month.group(3))
        return _window(
            raw_dates,
            year,
            month,
            int(day_range_month.group(1)),
            year,
            month,
            int(day_range_month.group(2)),
        )

    month_day = re.search(
        rf"\b({_MONTH_PATTERN})\s+(\d{{1,2}})(?:st|nd|rd|th)?\s*(?:-|to)\s*(?:({_MONTH_PATTERN})\s+)?(\d{{1,2}})(?:st|nd|rd|th)?\b",
        text,
    )
    if month_day:
        start_month = _month_number(month_day.group(1))
        end_month = _month_number(month_day.group(3)) or start_month
        return _window(
            raw_dates,
            year,
            start_month,
            int(month_day.group(2)),
            year,
            end_month,
            int(month_day.group(4)),
        )

    single_day = re.search(
        rf"\b(\d{{1,2}})(?:st|nd|rd|th)?\s+({_MONTH_PATTERN})\b", text
    )
    if single_day:
        month = _month_number(single_day.group(2))
        day = int(single_day.group(1))
        return _window(raw_dates, year, month, day, year, month, day)

    return None


def normalize_date_text(raw_dates: str) -> str:
    text = (
        (raw_dates or "")
        .strip()
        .lower()
        .replace(",", " ")
        .replace(".", " ")
        .replace("until", "to")
        .replace("till", "to")
        .replace("through", "to")
        .replace("â€“", "-")
        .replace("â€”", "-")
        .replace("Ã¢â‚¬â€œ", "-")
        .replace("Ã¢â‚¬â€", "-")
    )
    text = re.sub(r"(\d)(st|nd|rd|th)([a-z])", r"\1\2 \3", text)
    text = re.sub(r"(\d)(?!(?:st|nd|rd|th)\b)([a-z])", r"\1 \2", text)
    return re.sub(r"\s+", " ", text).strip()


def checklist_context(
    trip: dict[str, Any],
    window: TripWindow,
    due: DueChecklist,
    today: date,
) -> dict[str, Any]:
    guide = _guide(trip)
    intake = _intake(guide)
    overview = guide.get("overview") or {}
    destination = _destination_name(trip)
    itinerary_days = guide.get("itineraryDays") or []
    day_number = due.day_number or 1
    todays_day = next(
        (
            day
            for day in itinerary_days
            if int(day.get("dayNumber") or 0) == day_number
        ),
        itinerary_days[day_number - 1] if len(itinerary_days) >= day_number else {},
    )

    return {
        "destination_name": destination,
        "state": _state_from_address(trip),
        "start_date": window.start_date.isoformat(),
        "end_date": window.end_date.isoformat(),
        "num_days": window.total_days,
        "season": _season_for_month(window.start_date.month),
        "companions": f"{trip.get('people_count') or intake.get('peopleCount') or 1} traveller(s)",
        "travel_style": intake.get("pacePreference") or "Balanced",
        "dietary_preference": intake.get("dietaryPreference") or "No specific preference",
        "interests": ", ".join(intake.get("interests") or []) or "General sightseeing",
        "transport_notes": overview.get("howToGetThere") or "Verify local transport before travel.",
        "connectivity_notes": "Download essentials offline before heading out.",
        "cash_vs_upi": "UPI is common, but carry small cash for local transport and stalls.",
        "seasonal_weather": _weather_note_for_month(window.start_date.month, destination),
        "local_tips": _local_tips(guide),
        "tourist_traps": "Verify prices, timings, entry fees, and availability before travel.",
        "packing_tips": _packing_tips(window.start_date.month, destination),
        "itinerary_summary": _itinerary_summary(itinerary_days),
        "todays_itinerary": _day_summary(todays_day),
        "day_number": day_number,
        "total_days": window.total_days,
        "today_date": today.isoformat(),
        "weather_note": _weather_note_for_month(today.month, destination),
    }


def prompt_for_due_checklist(due: DueChecklist, context: dict[str, Any]) -> str:
    if due.checklist_type == PRE_TRIP:
        return PRE_TRIP_PROMPT.format(**context)
    if due.checklist_type == IN_TRIP_DAILY:
        return IN_TRIP_DAILY_PROMPT.format(**context)
    return POST_TRIP_PROMPT.format(**context)


def fallback_checklist(due: DueChecklist, context: dict[str, Any]) -> dict[str, Any]:
    destination = context["destination_name"]
    if due.checklist_type == PRE_TRIP:
        return {
            "categories": [
                {
                    "name": "Book & Reserve",
                    "emoji": "ticket",
                    "items": [
                        {
                            "text": f"Confirm {destination} stay booking",
                            "priority": "high",
                            "days_before": 14,
                        },
                        {
                            "text": "Arrange local transport benchmark rates",
                            "priority": "medium",
                            "days_before": 7,
                        },
                    ],
                },
                {
                    "name": "Pack",
                    "emoji": "bag",
                    "items": [
                        {
                            "text": f"Pack layers for {context['season']}",
                            "priority": "medium",
                            "days_before": 3,
                        }
                    ],
                },
                {
                    "name": "Download & Save",
                    "emoji": "phone",
                    "items": [
                        {
                            "text": f"Save offline {destination} map",
                            "priority": "high",
                            "days_before": 7,
                        }
                    ],
                },
                {
                    "name": "Know Before You Go",
                    "emoji": "info",
                    "items": [
                        {
                            "text": "Verify timings before leaving home",
                            "priority": "medium",
                            "days_before": None,
                        }
                    ],
                },
                {
                    "name": "Food & Dietary",
                    "emoji": "food",
                    "items": [
                        {
                            "text": "Shortlist meals matching diet preference",
                            "priority": "medium",
                            "days_before": 7,
                        }
                    ],
                },
                {
                    "name": "Money & Documents",
                    "emoji": "card",
                    "items": [
                        {
                            "text": "Carry ID and small cash",
                            "priority": "high",
                            "days_before": 2,
                        }
                    ],
                },
            ],
            "generated_for": destination,
            "season_note": context["seasonal_weather"],
        }

    if due.checklist_type == IN_TRIP_DAILY:
        return {
            "day_number": due.day_number,
            "date": context["today_date"],
            "morning_greeting": f"Good morning, Day {due.day_number} in {destination} is ready.",
            "weather_heads_up": context["weather_note"],
            "sections": [
                {
                    "name": "Before You Leave",
                    "emoji": "sunrise",
                    "time_context": "Do before stepping out",
                    "items": [
                        {"text": "Charge phone and power bank", "type": "prep", "attraction_id": None}
                    ],
                },
                {
                    "name": "Today's Plan",
                    "emoji": "pin",
                    "time_context": "Your day at a glance",
                    "items": [
                        {
                            "text": "Follow today's saved itinerary",
                            "type": "activity",
                            "time": "Morning",
                            "attraction_id": None,
                            "tip": "Keep timings flexible and verify locally.",
                        }
                    ],
                },
                {
                    "name": "Eat & Drink",
                    "emoji": "food",
                    "time_context": "Don't miss these",
                    "items": [
                        {"text": "Pick meals matching your diet", "type": "meal", "time": "Lunch", "attraction_id": None}
                    ],
                },
                {
                    "name": "Good to Know Today",
                    "emoji": "idea",
                    "time_context": "Practical tips for today",
                    "items": [
                        {"text": "Carry cash for small vendors", "type": "tip", "attraction_id": None}
                    ],
                },
            ],
            "end_of_day_note": "Save notes and check tomorrow's timing before sleeping.",
        }

    return {
        "wrap_up_message": f"Hope {destination} was amazing; here is your wrap-up.",
        "sections": [
            {
                "name": "Do Today",
                "emoji": "bolt",
                "items": [{"text": "Back up trip photos", "priority": "high"}],
            },
            {
                "name": "This Week",
                "emoji": "calendar",
                "items": [{"text": "Review expenses and refunds", "priority": "medium"}],
            },
            {
                "name": "Share & Remember",
                "emoji": "camera",
                "items": [{"text": f"Save favorite {destination} memories", "priority": "low"}],
            },
            {
                "name": "Help Future Travellers",
                "emoji": "help",
                "items": [{"text": "Flag outdated Raaste tips", "priority": "low"}],
            },
        ],
    }


def _trip_dates_text(trip: dict[str, Any]) -> str:
    guide = _guide(trip)
    intake = _intake(guide)
    return str(trip.get("dates") or intake.get("dates") or "")


def _guide(trip: dict[str, Any]) -> dict[str, Any]:
    guide = trip.get("guide_json") or {}
    if isinstance(guide, str):
        try:
            decoded = json.loads(guide)
            return decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError:
            return {}
    return guide if isinstance(guide, dict) else {}


def _intake(guide: dict[str, Any]) -> dict[str, Any]:
    intake = guide.get("intake") or {}
    return intake if isinstance(intake, dict) else {}


def _destination_name(trip: dict[str, Any]) -> str:
    guide = _guide(trip)
    return str(
        trip.get("destination_name")
        or guide.get("destinationName")
        or _intake(guide).get("destination")
        or "your trip"
    )


def _state_from_address(trip: dict[str, Any]) -> str:
    address = str(trip.get("destination_address") or "")
    parts = [part.strip() for part in address.split(",") if part.strip()]
    if len(parts) >= 2:
        return parts[-2]
    return "India"


def _local_tips(guide: dict[str, Any]) -> str:
    disclaimers = guide.get("disclaimers") or []
    if isinstance(disclaimers, list) and disclaimers:
        return "; ".join(str(item) for item in disclaimers[:3])
    return "Keep plans flexible and verify timings locally."


def _itinerary_summary(days: list[Any]) -> str:
    lines: list[str] = []
    for day in days[:14]:
        if not isinstance(day, dict):
            continue
        title = day.get("title") or f"Day {day.get('dayNumber') or ''}"
        stops = day.get("stops") or []
        stop_names = [
            str(stop.get("title"))
            for stop in stops
            if isinstance(stop, dict) and stop.get("title")
        ]
        lines.append(f"{title}: {', '.join(stop_names[:5])}")
    return "\n".join(lines) or "Itinerary details were not provided."


def _day_summary(day: dict[str, Any]) -> str:
    if not day:
        return "Today follows the saved itinerary."
    stops = day.get("stops") or []
    lines = [str(day.get("title") or "Today's plan")]
    for stop in stops:
        if not isinstance(stop, dict):
            continue
        time = stop.get("time") or ""
        title = stop.get("title") or ""
        description = stop.get("description") or ""
        lines.append(f"- {time}: {title} - {description}")
    return "\n".join(lines)


def _season_for_month(month: int) -> str:
    if month in {3, 4, 5}:
        return "summer"
    if month in {6, 7, 8, 9}:
        return "monsoon"
    if month in {10, 11}:
        return "post-monsoon"
    return "winter"


def _weather_note_for_month(month: int, destination: str) -> str:
    season = _season_for_month(month)
    if season == "monsoon":
        return f"{destination} may have rain and slippery roads; carry rain protection."
    if season == "summer":
        return f"{destination} can be hot; plan shade, water, and lighter midday pacing."
    if season == "winter":
        return f"{destination} may have cooler mornings and evenings; pack a light layer."
    return f"{destination} usually has clearer weather, but verify local forecasts."


def _packing_tips(month: int, destination: str) -> str:
    season = _season_for_month(month)
    if season == "monsoon":
        return f"Rain jacket, waterproof footwear, quick-dry clothes for {destination}."
    if season == "summer":
        return f"Sunscreen, cap, refillable water bottle, breathable clothes for {destination}."
    if season == "winter":
        return f"Light jacket, comfortable shoes, and evening layers for {destination}."
    return f"Comfortable shoes, day bag, offline documents, and weather-aware layers for {destination}."


def _window(
    raw_dates: str,
    start_year: int,
    start_month: int,
    start_day: int,
    end_year: int,
    end_month: int,
    end_day: int,
) -> TripWindow | None:
    try:
        start = date(start_year, start_month, start_day)
        end = date(end_year, end_month, end_day)
    except ValueError:
        return None
    if end < start:
        end = date(end.year + 1, end.month, end.day)
    return TripWindow(start_date=start, end_date=end, raw_dates=raw_dates)


def _extract_year(text: str) -> int | None:
    match = re.search(r"\b(20\d{2}|19\d{2})\b", text)
    return int(match.group(1)) if match else None


def _normalize_year(raw_year: str | None, fallback_year: int) -> int:
    if not raw_year:
        return fallback_year
    value = int(raw_year)
    return 2000 + value if value < 100 else value


_MONTHS = {
    "jan": 1,
    "january": 1,
    "feb": 2,
    "february": 2,
    "mar": 3,
    "march": 3,
    "apr": 4,
    "april": 4,
    "may": 5,
    "jun": 6,
    "june": 6,
    "jul": 7,
    "july": 7,
    "aug": 8,
    "august": 8,
    "sep": 9,
    "sept": 9,
    "september": 9,
    "oct": 10,
    "october": 10,
    "nov": 11,
    "november": 11,
    "dec": 12,
    "december": 12,
}
_MONTH_PATTERN = "|".join(_MONTHS)


def _month_number(value: str | None) -> int:
    if value is None:
        raise ValueError("Month is required")
    return _MONTHS[value.strip().lower()]


PRE_TRIP_PROMPT = """
You are Raaste, a personal Indian travel guide. Generate a highly personalized
pre-trip checklist for the following trip. Every item must be specific to THIS
trip, not generic travel advice.

TRIP DETAILS:
- Destination: {destination_name}, {state}
- Dates: {start_date} to {end_date} ({num_days} days)
- Season: {season}
- Travelling as: {companions}
- Travel style: {travel_style}
- Dietary preference: {dietary_preference}
- Interests: {interests}

DESTINATION KNOWLEDGE:
- Transport reality: {transport_notes}
- Connectivity: {connectivity_notes}
- Cash situation: {cash_vs_upi}
- Weather this season: {seasonal_weather}
- Key local tips: {local_tips}
- Tourist traps to warn about: {tourist_traps}
- Packing specific to destination: {packing_tips}

ITINERARY SUMMARY:
{itinerary_summary}

Generate a checklist with EXACTLY these 6 categories.
Each item must start with an action verb, be under 12 words, and be specific.

Return ONLY valid JSON:
{{
  "categories": [
    {{"name": "Book & Reserve", "emoji": "ticket", "items": [{{"text": "...", "priority": "high|medium|low", "days_before": 14}}]}},
    {{"name": "Pack", "emoji": "bag", "items": [{{"text": "...", "priority": "high|medium|low", "days_before": 3}}]}},
    {{"name": "Download & Save", "emoji": "phone", "items": [{{"text": "...", "priority": "high|medium|low", "days_before": 7}}]}},
    {{"name": "Know Before You Go", "emoji": "info", "items": [{{"text": "...", "priority": "high|medium|low", "days_before": null}}]}},
    {{"name": "Food & Dietary", "emoji": "food", "items": [{{"text": "...", "priority": "high|medium|low", "days_before": 7}}]}},
    {{"name": "Money & Documents", "emoji": "card", "items": [{{"text": "...", "priority": "high|medium|low", "days_before": 2}}]}}
  ],
  "generated_for": "{destination_name}",
  "season_note": "one sentence about why this season matters for this trip"
}}

Rules:
- Book & Reserve: 3-5 items.
- Pack: 6-8 items.
- Download & Save: 3-4 items.
- Know Before You Go: 4-5 items.
- Food & Dietary: 3-5 items.
- Money & Documents: 3-4 items.
"""


IN_TRIP_DAILY_PROMPT = """
You are Raaste, generating the morning briefing checklist for Day {day_number}
of a trip to {destination_name}.

TRAVELLER PROFILE:
- Companions: {companions}
- Dietary preference: {dietary_preference}
- Travel style: {travel_style}

TODAY'S ITINERARY:
{todays_itinerary}

CURRENT CONDITIONS:
- Day {day_number} of {total_days}
- Today's date: {today_date}
- Weather today: {weather_note}

Generate a morning checklist that prepares them for TODAY specifically.

Return ONLY valid JSON:
{{
  "day_number": {day_number},
  "date": "{today_date}",
  "morning_greeting": "One warm, specific sentence about today. Max 15 words.",
  "weather_heads_up": "One practical weather note for today if relevant.",
  "sections": [
    {{"name": "Before You Leave", "emoji": "sunrise", "time_context": "Do before stepping out", "items": [{{"text": "...", "type": "prep", "attraction_id": null}}]}},
    {{"name": "Today's Plan", "emoji": "pin", "time_context": "Your day at a glance", "items": [{{"text": "...", "type": "activity", "time": "8:00 AM", "attraction_id": "uuid-if-linked", "tip": "one-line tip"}}]}},
    {{"name": "Eat & Drink", "emoji": "food", "time_context": "Don't miss these", "items": [{{"text": "...", "type": "meal", "time": "1:00 PM", "attraction_id": null}}]}},
    {{"name": "Good to Know Today", "emoji": "idea", "time_context": "Practical tips for today", "items": [{{"text": "...", "type": "tip", "attraction_id": null}}]}}
  ],
  "end_of_day_note": "One sentence about what to check before sleeping tonight."
}}

Rules:
- Before You Leave: 2-3 items.
- Today's Plan: derived directly from today's itinerary, 4-6 items.
- Eat & Drink: 2-3 meal suggestions from today's itinerary.
- Good to Know Today: 2-3 practical tips.
- If first day: add check-in/orientation tasks.
- If last day: add checkout/departure tasks.
"""


POST_TRIP_PROMPT = """
You are Raaste, generating a post-trip wrap-up checklist after a trip to
{destination_name}.

TRIP SUMMARY:
- Destination: {destination_name}, {state}
- Duration: {num_days} days ({start_date} to {end_date})
- Companions: {companions}
- Travel style: {travel_style}
- Dietary: {dietary_preference}

ITINERARY COMPLETED:
{itinerary_summary}

Generate a warm, practical post-trip checklist.

Return ONLY valid JSON:
{{
  "wrap_up_message": "One warm sentence acknowledging the trip. Mention the destination. Max 20 words.",
  "sections": [
    {{"name": "Do Today", "emoji": "bolt", "items": [{{"text": "...", "priority": "high"}}]}},
    {{"name": "This Week", "emoji": "calendar", "items": [{{"text": "...", "priority": "medium"}}]}},
    {{"name": "Share & Remember", "emoji": "camera", "items": [{{"text": "...", "priority": "low"}}]}},
    {{"name": "Help Future Travellers", "emoji": "help", "items": [{{"text": "...", "priority": "low"}}]}}
  ]
}}

Rules:
- Do Today: 3-4 urgent items.
- This Week: 3-4 soon items.
- Share & Remember: 2-3 items.
- Help Future Travellers: 2-3 Raaste-specific useful items.
"""
