from __future__ import annotations
from typing import Optional
from datetime import datetime, timezone

from ..models.dto import AgentAccountDTO, AgentBillsDTO, AgentBillDTO
from ..provider.client import ProviderClient


def _to_float(val, default=0.0) -> float:
    try:
        if isinstance(val, str):
            return float(val.strip())
        return float(val)
    except Exception:
        return float(default)


def _to_int(val, default=0) -> int:
    try:
        if isinstance(val, str):
            return int(float(val.strip()))
        return int(val)
    except Exception:
        return int(default)


def _to_epoch(val) -> int:
    """Parse various timestamp representations to epoch seconds.
    Supports: int/float seconds, ISO strings, and 'Nov 04, 2025 at 16:46:48' format.
    Fallbacks to current UTC time on failure.
    """
    try:
        if val is None:
            raise ValueError("None")
        if isinstance(val, (int, float)):
            ts = int(float(val))
            return ts if ts > 0 else int(datetime.now(tz=timezone.utc).timestamp())
        if isinstance(val, str):
            s = val.strip()
            if s.isdigit():
                ts = int(float(s))
                return ts if ts > 0 else int(datetime.now(tz=timezone.utc).timestamp())
            # ISO 8601 like '2025-11-08T10:20:30Z' or with offset
            try:
                iso = s.replace("Z", "+00:00")
                dt = datetime.fromisoformat(iso)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                ts = int(dt.timestamp())
                return ts if ts > 0 else int(datetime.now(tz=timezone.utc).timestamp())
            except Exception:
                pass
            # 'Nov 04, 2025 at 16:46:48'
            try:
                dt = datetime.strptime(s, "%b %d, %Y at %H:%M:%S").replace(tzinfo=timezone.utc)
                ts = int(dt.timestamp())
                return ts if ts > 0 else int(datetime.now(tz=timezone.utc).timestamp())
            except Exception:
                pass
    except Exception:
        pass
    return int(datetime.now(tz=timezone.utc).timestamp())


class AgentService:
    def __init__(self):
        self.provider = ProviderClient()

        
    def get_account(self, request_id: Optional[str] = None) -> Optional[AgentAccountDTO]:
        data = self.provider.get_agent_account(request_id=request_id)
        if not data:
            return None
        return AgentAccountDTO(
            agent_id=data.get("agent_id"),
            username=data.get("username"),
            name=data.get("name"),
            balance=_to_float(data.get("balance", 0.0)),
            revenue_rate=_to_int(data.get("revenue_rate", 0)),
            status=_to_int(data.get("status", 0)),
            # Accept created_at/createdAt/created_time or string formats
            created_at=_to_epoch(
                data.get("created_at")
                or data.get("createdAt")
                or data.get("created_time")
                or data.get("created")
            ),
        )

    def list_bills(
        self,
        page_number: int,
        page_size: int,
        reference: Optional[str] = None,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
        request_id: Optional[str] = None,
    ) -> AgentBillsDTO:
        data = self.provider.get_agent_bills(
            page_number=page_number,
            page_size=page_size,
            reference=reference,
            start_date=start_date,
            end_date=end_date,
            request_id=request_id,
        )
        bills_raw = data.get("bills") or []
        bills = [
            AgentBillDTO(
                bill_id=b.get("bill_id"),
                trade=_to_int(b.get("trade", 0)),
                amount=_to_float(b.get("amount", 0.0)),
                reference=str(b.get("reference" or "")),
                description=str(b.get("description" or "")),
                created_at=_to_epoch(b.get("created_at")),
            )
            for b in bills_raw
        ]
        return AgentBillsDTO(bills=bills, bills_count=_to_int(data.get("bills_count", len(bills))))