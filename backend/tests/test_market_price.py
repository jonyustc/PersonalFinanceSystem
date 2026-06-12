from decimal import Decimal
from datetime import date

import httpx

from app.services.market_price import MarketPriceService


def test_parse_dse_latest_prices():
    page = """
    <table>
      <tr>
        <td>1</td>
        <td><a href="displayCompany.php?name=SQURPHARMA"> SQURPHARMA </a></td>
        <td>225.5</td>
        <td>226</td>
      </tr>
      <tr>
        <td>2</td>
        <td><a href="displayCompany.php?name=BRACBANK">BRACBANK</a></td>
        <td>51.2</td>
      </tr>
    </table>
    """

    prices = MarketPriceService()._parse_dse_latest_prices(page)

    assert prices["SQURPHARMA"].last_price == Decimal("225.5")
    assert prices["BRACBANK"].last_price == Decimal("51.2")
    assert prices["SQURPHARMA"].source == "DSE"


def test_parse_dse_company_name():
    page = '<h2 class="BodyHead"> Company Name: <i>Square Pharmaceuticals PLC.</i></h2>'

    name = MarketPriceService()._parse_dse_company_name(page)

    assert name == "Square Pharmaceuticals PLC."


def test_parse_dse_cash_dividends_and_face_value():
    page = """
    <tr><th>Face/par Value</th><td>10.0</td></tr>
    <tr><th width="30%">Cash Dividend  </th>
    <td width="70%">120% 2025, 110% 2024, 105.50% 2023</td></tr>
    """
    service = MarketPriceService()

    assert service._parse_face_value(page) == Decimal("10.0")
    assert service._parse_cash_dividends(page) == {
        2025: Decimal("120"),
        2024: Decimal("110"),
        2023: Decimal("105.50"),
    }


def test_parse_record_dates_text():
    service = MarketPriceService()

    dates = service._parse_record_dates_text(
        """
        SQURPHARMA Annual AGM 15-Dec-2025 10:00 AM
        GP EGM 03/06/2026
        """
    )

    assert dates["SQURPHARMA"] == date(2025, 12, 15)
    assert dates["GP"] == date(2026, 6, 3)


def test_detects_dse_certificate_error():
    service = MarketPriceService()
    error = httpx.ConnectError(
        "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed"
    )

    assert service._is_certificate_error(error)
