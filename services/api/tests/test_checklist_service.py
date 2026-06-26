from datetime import date

from app.services.checklist_service import (
    IN_TRIP_DAILY,
    POST_TRIP,
    PRE_TRIP,
    due_checklists_for_trip,
    parse_trip_window,
)


def test_parse_day_range_with_month():
    window = parse_trip_window("27th to 30th June", reference_date=date(2026, 6, 1))

    assert window is not None
    assert window.start_date == date(2026, 6, 27)
    assert window.end_date == date(2026, 6, 30)
    assert window.total_days == 4


def test_due_pre_trip_inside_two_week_window():
    window = parse_trip_window("27-30 June", reference_date=date(2026, 6, 13))

    assert window is not None
    due = due_checklists_for_trip(window, date(2026, 6, 13))

    assert len(due) == 1
    assert due[0].checklist_type == PRE_TRIP
    assert due[0].checklist_date == date(2026, 6, 13)


def test_due_in_trip_daily_day_number():
    window = parse_trip_window("27-30 June", reference_date=date(2026, 6, 28))

    assert window is not None
    due = due_checklists_for_trip(window, date(2026, 6, 28))

    assert len(due) == 1
    assert due[0].checklist_type == IN_TRIP_DAILY
    assert due[0].day_number == 2


def test_due_post_trip_after_end_date():
    window = parse_trip_window("27-30 June", reference_date=date(2026, 7, 1))

    assert window is not None
    due = due_checklists_for_trip(window, date(2026, 7, 1))

    assert len(due) == 1
    assert due[0].checklist_type == POST_TRIP
    assert due[0].checklist_date == date(2026, 7, 1)


def test_parse_compact_day_range_with_month():
    window = parse_trip_window("1st-4thJuly", reference_date=date(2026, 6, 27))

    assert window is not None
    assert window.start_date == date(2026, 7, 1)
    assert window.end_date == date(2026, 7, 4)
    assert window.total_days == 4