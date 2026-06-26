import asyncio
import json
import sys
from datetime import date

from app.services.checklist_service import ChecklistService


def _parse_run_date(value: str | None) -> date | None:
    if not value:
        return None
    return date.fromisoformat(value)


async def _run() -> int:
    run_date = _parse_run_date(sys.argv[1] if len(sys.argv) > 1 else None)
    result = await ChecklistService().run_due_checklists(run_date=run_date)
    print(json.dumps(result.model_dump(mode="json"), indent=2))
    return 0 if not result.errors else 1


def main() -> None:
    raise SystemExit(asyncio.run(_run()))


if __name__ == "__main__":
    main()
