from __future__ import annotations

import html
import re
from io import BytesIO
from urllib.parse import quote
from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal, InvalidOperation

import httpx
from pypdf import PdfReader


DSE_LATEST_PRICE_URL = "https://www.dsebd.org/latest_share_price_scroll_l.php"
DSE_AGM_RECORD_DATE_PDF_URL = "https://www.dsebd.org/Company_AGM_EGM.pdf"


@dataclass(frozen=True)
class MarketPrice:
    symbol: str
    last_price: Decimal
    source: str
    fetched_at: datetime


@dataclass(frozen=True)
class DseStockQuote:
    symbol: str
    name: str
    last_price: Decimal
    source: str
    fetched_at: datetime


@dataclass(frozen=True)
class DseDividendEvent:
    symbol: str
    year: int
    cash_percent: Decimal
    face_value: Decimal
    record_date: date | None
    source: str


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

    async def search_dse_stocks(self, query: str = "", limit: int = 20) -> list[DseStockQuote]:
        prices = await self.fetch_dse_latest_prices()
        normalized = query.strip().upper()
        matches = [
            price
            for price in prices.values()
            if not normalized or normalized in price.symbol
        ][:limit]
        if not matches:
            return []

        async with httpx.AsyncClient(
            timeout=20,
            headers={
                "User-Agent": "PersonalFinanceSystem/1.0",
                "Accept": "text/html,application/xhtml+xml",
            },
        ) as client:
            quotes = []
            for price in matches:
                name = await self._fetch_dse_company_name(client, price.symbol)
                quotes.append(
                    DseStockQuote(
                        symbol=price.symbol,
                        name=name or price.symbol,
                        last_price=price.last_price,
                        source=price.source,
                        fetched_at=price.fetched_at,
                    )
                )
        return quotes

    async def fetch_dse_dividend_events(self, symbol: str) -> list[DseDividendEvent]:
        symbol = symbol.strip().upper()
        async with httpx.AsyncClient(
            timeout=20,
            headers={
                "User-Agent": "PersonalFinanceSystem/1.0",
                "Accept": "text/html,application/xhtml+xml,application/pdf",
            },
        ) as client:
            company_response = await client.get(f"https://www.dsebd.org/displayCompany.php?name={quote(symbol)}")
            company_response.raise_for_status()
            record_dates = await self._fetch_dse_record_dates(client)

        face_value = self._parse_face_value(company_response.text)
        dividends = self._parse_cash_dividends(company_response.text)
        events = []
        for year, cash_percent in dividends.items():
            record_date = record_dates.get(symbol)
            if record_date and record_date.year not in {year, year + 1}:
                record_date = None
            events.append(DseDividendEvent(
                symbol=symbol,
                year=year,
                cash_percent=cash_percent,
                face_value=face_value,
                record_date=record_date,
                source="DSE",
            ))
        return events

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

    async def _fetch_dse_company_name(self, client: httpx.AsyncClient, symbol: str) -> str | None:
        try:
            response = await client.get(f"https://www.dsebd.org/displayCompany.php?name={quote(symbol)}")
            response.raise_for_status()
        except httpx.HTTPError:
            return None
        return self._parse_dse_company_name(response.text)

    def _parse_dse_company_name(self, page: str) -> str | None:
        match = re.search(
            r"Company Name:\s*<i>\s*(.*?)\s*</i>",
            page,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if not match:
            return None
        return self._clean_cell(match.group(1))

    def _parse_face_value(self, page: str) -> Decimal:
        match = re.search(
            r"Face/par Value\s*</th>\s*<td[^>]*>\s*([0-9,.]+)",
            page,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if not match:
            return Decimal("10")
        try:
            return Decimal(match.group(1).replace(",", ""))
        except InvalidOperation:
            return Decimal("10")

    def _parse_cash_dividends(self, page: str) -> dict[int, Decimal]:
        match = re.search(
            r"Cash Dividend\s*</th>\s*<td[^>]*>(.*?)</td>",
            page,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if not match:
            return {}
        text = self._clean_cell(match.group(1))
        dividends: dict[int, Decimal] = {}
        for percent, year in re.findall(r"([0-9]+(?:\.[0-9]+)?)%\s*([0-9]{4})", text):
            try:
                dividends[int(year)] = Decimal(percent)
            except InvalidOperation:
                continue
        return dividends

    async def _fetch_dse_record_dates(self, client: httpx.AsyncClient) -> dict[str, date]:
        try:
            response = await client.get(DSE_AGM_RECORD_DATE_PDF_URL)
            response.raise_for_status()
        except httpx.HTTPError:
            return {}
        return self._parse_record_date_pdf(response.content)

    def _parse_record_date_pdf(self, content: bytes) -> dict[str, date]:
        try:
            reader = PdfReader(BytesIO(content))
            text = "\n".join(page.extract_text() or "" for page in reader.pages)
        except Exception:
            return {}
        return self._parse_record_dates_text(text)

    def _parse_record_dates_text(self, text: str) -> dict[str, date]:
        dates: dict[str, date] = {}
        for line in text.splitlines():
            compact = " ".join(line.split())
            if not compact:
                continue
            symbol_match = re.search(r"\b[A-Z0-9]{2,20}\b", compact)
            date_match = re.search(
                r"\b([0-9]{1,2})[-/ ]([A-Za-z]{3,9}|[0-9]{1,2})[-/ ]([0-9]{2,4})\b",
                compact,
            )
            if not symbol_match or not date_match:
                continue
            parsed = self._parse_dse_date(date_match.group(0))
            if parsed:
                dates[symbol_match.group(0).upper()] = parsed
        return dates

    def _parse_dse_date(self, value: str) -> date | None:
        normalized = value.replace("/", "-").replace(" ", "-")
        for fmt in ("%d-%m-%Y", "%d-%m-%y", "%d-%b-%Y", "%d-%b-%y", "%d-%B-%Y", "%d-%B-%y"):
            try:
                return datetime.strptime(normalized, fmt).date()
            except ValueError:
                continue
        return None
