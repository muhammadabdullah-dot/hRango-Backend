"""Paging, as the frontend sends it: ?page=1&pageSize=10 (pageSize capped at 100)."""
from dataclasses import dataclass

from fastapi import Query

MAX_PAGE_SIZE = 100


@dataclass(frozen=True)
class PageParams:
    page: int
    page_size: int


def page_params(page: int = Query(1), page_size: int = Query(10, alias="pageSize")) -> PageParams:
    return PageParams(page=max(page, 1), page_size=min(max(page_size, 1), MAX_PAGE_SIZE))
