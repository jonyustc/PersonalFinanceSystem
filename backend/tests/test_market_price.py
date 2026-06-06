from decimal import Decimal

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
