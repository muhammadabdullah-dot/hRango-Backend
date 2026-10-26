"""Envelopes and base model, matching the frontend's src/types/api.ts:
  single item  {"data": T}
  list         {"data": [T], "meta": {"page", "pageSize", "total", "totalPages"}}
Ids are BIGINT in the database and strings in JSON.
"""
import math
from collections.abc import Callable, Iterable
from datetime import UTC, datetime
from typing import Any, ClassVar, Generic, TypeVar

from pydantic import BaseModel, ConfigDict, SerializationInfo, model_serializer
from pydantic.alias_generators import to_camel

T = TypeVar("T")


class ApiModel(BaseModel):
    """Base for every request and response body: snake_case in Python, camelCase in JSON.
    Numbers given to a str field become strings, so a BIGINT id is sent as "123".

    Time: the database keeps server stamps (created_at, decided_at, ...) in UTC without a zone; they are
    sent with "Z" so browsers show them in local time. Times people enter as wall-clock time (punches,
    shifts, interview slots) are listed in a model's `__local_times__` and sent as they are, without a zone."""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, coerce_numbers_to_str=True,
                              serialize_by_alias=True)
    __local_times__: ClassVar[frozenset[str]] = frozenset()

    @model_serializer(mode="wrap")
    def _stamp_utc(self, handler, info: SerializationInfo):
        data = handler(self)
        if not isinstance(data, dict):
            return data
        local = type(self).__local_times__
        for name, field in type(self).model_fields.items():
            value = getattr(self, name, None)
            if name in local or not isinstance(value, datetime) or value.tzinfo is not None:
                continue
            stamped = value.replace(tzinfo=UTC)
            out = stamped.isoformat().replace("+00:00", "Z") if info.mode == "json" else stamped
            for key in {field.serialization_alias or field.alias or name, name}:
                if key in data:
                    data[key] = out
        return data


class Item(ApiModel, Generic[T]):
    data: T


class PageMeta(ApiModel):
    page: int
    page_size: int
    total: int
    total_pages: int


class Paginated(ApiModel, Generic[T]):
    data: list[T]
    meta: PageMeta


def paginated(rows: Iterable[dict[str, Any]], total: int, page: int, page_size: int,
              to_item: Callable[[dict[str, Any]], T]) -> dict[str, Any]:
    return {"data": [to_item(r) for r in rows],
            "meta": PageMeta(page=page, page_size=page_size, total=total,
                             total_pages=max(1, math.ceil(total / page_size)))}
