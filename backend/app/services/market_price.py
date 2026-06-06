from __future__ import annotations

import html
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal, InvalidOperation

import httpx


DSE_LATEST_PRICE_URL = "https://www.dsebd.org/latest_share_price_scroll_l.php"


@dataclass(frozen=True)
class MarketPrice:
    symbol: str
    last_price: Decimal
    source: str
    fetched_at: datetime


class MarketPriceService:
    async def fetch_dse_latest_prices(self) -> dict[str, MarketPrice]:
        async with httpx.AsyncClient(
            timeout=20,
            headers={
                "User-Agent": "PersonalFinanceSystem/1.0",
                "Accept": "text/html,application/xhtml+xml",
            },
        ) as client:
            response = await client.get(DSE_LATEST_PRICE_URL)
            response.raise_for_status()

        return self._parse_dse_latest_prices(response.text)

    def _parse_dse_latest_prices(self, page: str) -> dict[str, MarketPrice]:
        fetched_at = datetime.now(UTC)
        prices: dict[str, MarketPrice] = {}
        for row in re.findall(r"<tr[^>]*>(.*?)</tr>", page, flags=re.IGNORECASE | re.DOTALL):
            cells = [
                self._clean_cell(cell)
                for cell in re.findall(r"<td[^>]*>(.*?)</td>", row, flags=re.IGNORECASE | re.DOTALL)
            ]
            if len(cells) < 3:
                continue
            symbol = cells[1].strip().upper()
            if not symbol or symbol == "TRADING CODE":
                continue
            try:
                last_price = Decimal(cells[2].replace(",", ""))
            except (InvalidOperation, ValueError):
                continue
            prices[symbol] = MarketPrice(
                symbol=symbol,
                last_price=last_price,
                source="DSE",
                fetched_at=fetched_at,
            )
        return prices

    def _clean_cell(self, value: str) -> str:
        without_tags = re.sub(r"<[^>]+>", "", value)
        return html.unescape(without_tags).strip()
