from datetime import date
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.stock import Dividend, Holding, PortfolioTransaction
from app.repositories.stock import StockRepository
from app.schemas.stock import DividendCreate, PortfolioTransactionCreate, StockCreate, StockUpdate
from app.services.market_price import MarketPriceService


ZERO = Decimal("0")
BROKER_FEE_RATE = Decimal("0.004")
DEFAULT_DIVIDEND_TAX_RATE = Decimal("10")


class PortfolioService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = StockRepository(db)

    async def stocks(self):
        return await self.repo.stocks()

    async def create_stock(self, payload: StockCreate):
        stock = await self.repo.get_or_create_stock(payload)
        await self.db.commit()
        await self.db.refresh(stock)
        return stock

    async def update_stock(self, stock_id: UUID, payload: StockUpdate):
        stock = await self.repo.get_stock(stock_id)
        if not stock:
            raise HTTPException(404, "Stock not found")
        data = payload.model_dump(exclude_unset=True)
        for field, value in data.items():
            if field == "currency" and value:
                value = value.upper()
            if field == "symbol" and value:
                value = value.strip().upper()
                existing = (
                    await self.db.execute(
                        select(type(stock)).where(
                            func.upper(type(stock).symbol) == value,
                            type(stock).id != stock_id,
                        )
                    )
                ).scalar_one_or_none()
                if existing:
                    raise HTTPException(409, "Stock symbol already exists")
            setattr(stock, field, value)
        await self.db.commit()
        await self.db.refresh(stock)
        return stock

    async def refresh_stock_price(self, stock_id: UUID):
        stock = await self.repo.get_stock(stock_id)
        if not stock:
            raise HTTPException(404, "Stock not found")
        price_map = await MarketPriceService().fetch_dse_latest_prices()
        price = price_map.get(stock.symbol.upper())
        if not price:
            raise HTTPException(404, f"Latest DSE price not found for {stock.symbol}")
        stock.last_price = price.last_price
        if not stock.exchange:
            stock.exchange = price.source
        await self.db.commit()
        await self.db.refresh(stock)
        return {
            "updated": 1,
            "source": price.source,
            "fetched_at": price.fetched_at.isoformat(),
            "missing_symbols": [],
            "stocks": [stock],
        }

    async def refresh_stock_prices(self):
        stocks = await self.repo.stocks()
        if not stocks:
            return {
                "updated": 0,
                "source": "DSE",
                "fetched_at": "",
                "missing_symbols": [],
                "stocks": [],
            }
        price_map = await MarketPriceService().fetch_dse_latest_prices()
        updated = []
        missing = []
        fetched_at = ""
        for stock in stocks:
            price = price_map.get(stock.symbol.upper())
            if not price:
                missing.append(stock.symbol)
                continue
            stock.last_price = price.last_price
            if not stock.exchange:
                stock.exchange = price.source
            fetched_at = price.fetched_at.isoformat()
            updated.append(stock)
        await self.db.commit()
        for stock in updated:
            await self.db.refresh(stock)
        return {
            "updated": len(updated),
            "source": "DSE",
            "fetched_at": fetched_at,
            "missing_symbols": missing,
            "stocks": updated,
        }

    async def dse_dividend_estimate(
        self,
        user_id: UUID,
        symbol: str,
        stock_id: UUID | None = None,
        tax_rate_percent: Decimal = DEFAULT_DIVIDEND_TAX_RATE,
    ):
        normalized_symbol = symbol.strip().upper()
        if not normalized_symbol:
            raise HTTPException(400, "Stock symbol is required")

        stock = (
            await self.repo.get_stock(stock_id)
            if stock_id
            else await self.repo.get_stock_by_symbol(normalized_symbol)
        )
        if stock_id and not stock:
            raise HTTPException(404, "Stock not found")

        try:
            events = await MarketPriceService().fetch_dse_dividend_events(normalized_symbol)
        except Exception as exc:
            return self._empty_dividend_estimate(
                normalized_symbol,
                tax_rate_percent,
                f"DSE dividend lookup failed: {exc}",
            )

        if not events:
            return self._empty_dividend_estimate(
                normalized_symbol,
                tax_rate_percent,
                "DSE cash dividend declaration was not found",
            )

        event = sorted(events, key=lambda item: item.year, reverse=True)[0]
        stock_transactions = []
        if stock:
            transactions = await self.repo.transactions(user_id, 10000)
            stock_transactions = [
                transaction
                for transaction in transactions
                if transaction.stock_id == stock.id
                and transaction.txn_type in {"buy", "sell"}
            ]
        eligible_quantity = (
            self._quantity_on_date(stock_transactions, event.record_date)
            if event.record_date is not None
            else ZERO
        )
        dividend_per_share = event.face_value * event.cash_percent / Decimal("100")
        gross_amount = eligible_quantity * dividend_per_share
        tax_amount = gross_amount * tax_rate_percent / Decimal("100")
        net_amount = gross_amount - tax_amount
        return {
            "symbol": normalized_symbol,
            "found": True,
            "source": event.source,
            "record_date": event.record_date,
            "payment_date": date.today(),
            "year": event.year,
            "cash_dividend_percent": event.cash_percent,
            "dividend_per_share": dividend_per_share,
            "eligible_quantity": eligible_quantity,
            "gross_amount": gross_amount,
            "tax_rate_percent": tax_rate_percent,
            "tax_amount": tax_amount,
            "net_amount": net_amount,
            "message": self._dividend_estimate_message(stock is not None, event.record_date is not None),
        }

    async def create_transaction(self, user_id: UUID, payload: PortfolioTransactionCreate):
        try:
            stock = None
            if payload.stock_id:
                stock = await self.repo.get_stock(payload.stock_id)
                if not stock:
                    raise HTTPException(404, "Stock not found")
            elif payload.stock:
                stock = await self.repo.get_or_create_stock(payload.stock)

            broker_account = await self._get_broker_account(user_id, payload.broker_account_id)
            fees = payload.fees if payload.fees is not None else self._default_fee(payload)
            trx = PortfolioTransaction(
                user_id=user_id,
                stock_id=stock.id if stock else None,
                broker_account_id=broker_account.id if broker_account else None,
                txn_type=payload.txn_type,
                quantity=payload.quantity,
                price=payload.price,
                fees=fees,
                txn_date=payload.txn_date,
                record_date=payload.record_date if payload.txn_type == "income" else None,
                notes=payload.notes,
            )
            self.db.add(trx)
            await self._apply_broker_cash(trx, broker_account)
            await self.db.flush()
            await self._rebuild_derived(user_id)
            await self.db.commit()
            await self.db.refresh(trx)
            return await self._response_transaction(trx)
        except Exception:
            await self.db.rollback()
            raise

    async def list_transactions(self, user_id: UUID, limit: int = 100):
        return [await self._response_transaction(item) for item in await self.repo.transactions(user_id, limit) if item.txn_type != "deposit"]

    async def update_transaction(self, user_id: UUID, transaction_id: UUID, payload: PortfolioTransactionCreate):
        try:
            trx = await self.repo.get_transaction(user_id, transaction_id)
            if not trx:
                raise HTTPException(404, "Portfolio transaction not found")
            old_broker = await self._get_broker_account(user_id, trx.broker_account_id)
            await self._apply_broker_cash(trx, old_broker, reverse=True)

            stock = None
            if payload.stock_id:
                stock = await self.repo.get_stock(payload.stock_id)
                if not stock:
                    raise HTTPException(404, "Stock not found")
            elif payload.stock:
                stock = await self.repo.get_or_create_stock(payload.stock)

            new_broker = await self._get_broker_account(user_id, payload.broker_account_id)
            trx.stock_id = stock.id if stock else None
            trx.broker_account_id = new_broker.id if new_broker else None
            trx.txn_type = payload.txn_type
            trx.quantity = payload.quantity
            trx.price = payload.price
            trx.fees = payload.fees if payload.fees is not None else self._default_fee(payload)
            trx.txn_date = payload.txn_date
            trx.record_date = payload.record_date if payload.txn_type == "income" else None
            trx.notes = payload.notes
            await self._apply_broker_cash(trx, new_broker)
            await self._rebuild_derived(user_id)
            await self.db.commit()
            await self.db.refresh(trx)
            return await self._response_transaction(trx)
        except Exception:
            await self.db.rollback()
            raise

    async def delete_transaction(self, user_id: UUID, transaction_id: UUID):
        try:
            trx = await self.repo.get_transaction(user_id, transaction_id)
            if not trx:
                raise HTTPException(404, "Portfolio transaction not found")
            broker_account = await self._get_broker_account(user_id, trx.broker_account_id)
            await self._apply_broker_cash(trx, broker_account, reverse=True)
            await self.db.delete(trx)
            await self.db.flush()
            await self._rebuild_derived(user_id)
            await self.db.commit()
        except Exception:
            await self.db.rollback()
            raise

    async def create_dividend(self, user_id: UUID, payload: DividendCreate):
        stock = await self.repo.get_stock(payload.stock_id)
        if not stock:
            raise HTTPException(404, "Stock not found")
        transaction = PortfolioTransactionCreate(
            stock_id=payload.stock_id,
            broker_account_id=payload.broker_account_id,
            txn_type="income",
            quantity=Decimal("1"),
            price=payload.amount,
            fees=ZERO,
            txn_date=payload.payment_date,
            record_date=payload.record_date,
            notes=payload.notes,
        )
        await self.create_transaction(user_id, transaction)
        return (await self.repo.dividends(user_id))[0]

    async def dividends(self, user_id: UUID):
        return await self.repo.dividends(user_id)

    async def summary(self, user_id: UUID, include_auto_dividends: bool = False):
        await self._rebuild_derived(user_id)
        await self.db.commit()
        holdings = await self.repo.holdings(user_id)
        dividends = await self.repo.dividends(user_id)
        broker_accounts = await self.repo.broker_accounts(user_id)
        transactions = await self.repo.transactions(user_id, 10000)

        dividend_by_stock = {}
        dividend_report = {}
        for dividend in dividends:
            dividend_by_stock[dividend.stock_id] = (
                dividend_by_stock.get(dividend.stock_id, ZERO) + dividend.amount
            )
            key_date = dividend.record_date or dividend.payment_date
            key = (dividend.stock_id, key_date.year)
            dividend_report[key] = dividend_report.get(key, ZERO) + dividend.amount

        manual_dividend_keys = set(dividend_report)
        auto_dividend_report = (
            await self._automatic_dividend_report(
                transactions,
                manual_dividend_keys,
            )
            if include_auto_dividends
            else []
        )
        auto_dividend_by_stock = {}
        for row in auto_dividend_report:
            auto_dividend_by_stock[row["stock_id"]] = (
                auto_dividend_by_stock.get(row["stock_id"], ZERO) + row["dividend_gain"]
            )

        holding_rows = []
        active_cost_basis = ZERO
        equity_value = ZERO
        realized_capital = ZERO
        for holding in holdings:
            if holding.quantity <= ZERO:
                realized_capital += holding.realized_profit_loss
                continue
            invested = holding.quantity * holding.avg_buy_price
            market_value = holding.quantity * (holding.stock.last_price or ZERO)
            unrealized = market_value - invested
            dividend_income = (
                dividend_by_stock.get(holding.stock_id, ZERO)
                + auto_dividend_by_stock.get(holding.stock_id, ZERO)
            )
            total_pl = unrealized + holding.realized_profit_loss
            active_cost_basis += invested
            equity_value += market_value
            realized_capital += holding.realized_profit_loss
            holding_rows.append(
                {
                    "stock": holding.stock,
                    "quantity": holding.quantity,
                    "avg_buy_price": holding.avg_buy_price,
                    "invested_amount": invested,
                    "market_value": market_value,
                    "unrealized_profit_loss": unrealized,
                    "unrealized_percent": self._percent(unrealized, invested),
                    "realized_profit_loss": holding.realized_profit_loss,
                    "dividend_income": dividend_income,
                    "total_profit_loss": total_pl,
                }
            )

        principal = sum((self._total_amount(t) for t in transactions if t.txn_type == "deposit"), ZERO)
        derived_cash = sum((self._cash_flow(t) for t in transactions), ZERO)
        broker_cash = sum((account.balance for account in broker_accounts), ZERO)
        cash_balance = derived_cash
        total_portfolio = equity_value + cash_balance
        unrealized_gain_loss = equity_value - active_cost_basis
        dividend_income_total = sum((dividend.amount for dividend in dividends), ZERO) + sum(
            (row["dividend_gain"] for row in auto_dividend_report),
            ZERO,
        )
        realized_total = realized_capital
        overall = realized_total + unrealized_gain_loss
        cagr_percent = self._cagr_percent(principal, total_portfolio, transactions)

        return {
            "total_principal_investment": principal,
            "invested_capital": principal,
            "active_cost_basis": active_cost_basis,
            "current_equity_value": equity_value,
            "unrealized_gain_loss": unrealized_gain_loss,
            "cash_balance": cash_balance,
            "total_portfolio_value": total_portfolio,
            "total_realized_capital_gain_loss": realized_capital,
            "dividend_income": dividend_income_total,
            "total_realized_profit": realized_total,
            "overall_profit_loss": overall,
            "return_percent": self._percent(overall, principal),
            "cagr_percent": cagr_percent,
            "broker_accounts": [
                {"id": account.id, "name": account.name, "balance": account.balance, "currency": account.currency}
                for account in broker_accounts
            ],
            "holdings": holding_rows,
            "dividend_report": [
                {
                    "stock_id": stock_id,
                    "stock_name": next((d.stock.name for d in dividends if d.stock_id == stock_id), ""),
                    "year": year,
                    "dividend_gain": amount,
                    "source": "manual",
                }
                for (stock_id, year), amount in sorted(dividend_report.items(), key=lambda item: (item[0][1], str(item[0][0])))
            ] + auto_dividend_report,
            "auto_dividend_report": auto_dividend_report,
        }

    async def _apply_broker_cash(self, trx: PortfolioTransaction, broker_account: Account | None, reverse: bool = False):
        if broker_account:
            cash_flow = -self._cash_flow(trx) if reverse else self._cash_flow(trx)
            if broker_account.balance + cash_flow < ZERO:
                raise HTTPException(400, "Insufficient broker cash")
            broker_account.balance += cash_flow

    async def _rebuild_derived(self, user_id: UUID) -> None:
        await self.db.execute(delete(Holding).where(Holding.user_id == user_id))
        await self.db.execute(delete(Dividend).where(Dividend.user_id == user_id))
        await self.db.flush()
        transactions = list(
            (
                await self.db.execute(
                    select(PortfolioTransaction)
                    .where(PortfolioTransaction.user_id == user_id)
                    .order_by(PortfolioTransaction.txn_date, PortfolioTransaction.created_at, PortfolioTransaction.id)
                )
            ).scalars()
        )
        aggregates: dict[UUID, dict[str, Decimal]] = {}
        for trx in transactions:
            if trx.txn_type == "income" and trx.stock_id:
                self.db.add(
                    Dividend(
                        user_id=user_id,
                        stock_id=trx.stock_id,
                        amount=trx.price,
                        payment_date=trx.txn_date,
                        record_date=trx.record_date,
                        notes=trx.notes,
                    )
                )
            if not trx.stock_id:
                continue
            stock_data = aggregates.setdefault(
                trx.stock_id,
                {"quantity": ZERO, "cost_basis": ZERO, "realized": ZERO},
            )
            if trx.txn_type == "buy":
                stock_data["quantity"] += trx.quantity
                stock_data["cost_basis"] += self._share_value(trx)
            elif trx.txn_type == "sell":
                if trx.quantity > stock_data["quantity"]:
                    raise HTTPException(400, "Sell quantity exceeds holding")
                avg_cost = stock_data["cost_basis"] / stock_data["quantity"] if stock_data["quantity"] else ZERO
                removed_cost = avg_cost * trx.quantity
                stock_data["quantity"] -= trx.quantity
                stock_data["cost_basis"] -= removed_cost
                stock_data["realized"] += self._total_amount(trx) - removed_cost

        for stock_id, data in aggregates.items():
            net_qty = data["quantity"]
            adjusted_cost_basis = data["cost_basis"] if net_qty > ZERO else ZERO
            realized_profit_loss = data["realized"]
            avg_buy_price = adjusted_cost_basis / net_qty if net_qty > ZERO else ZERO
            self.db.add(
                Holding(
                    user_id=user_id,
                    stock_id=stock_id,
                    quantity=net_qty,
                    avg_buy_price=avg_buy_price,
                    realized_profit_loss=realized_profit_loss,
                )
            )

    async def _get_broker_account(self, user_id: UUID, account_id: UUID | None):
        if not account_id:
            return None
        account = await self.db.get(Account, account_id)
        if not account or account.user_id != user_id:
            raise HTTPException(404, "Broker account not found")
        return account

    def _default_fee(self, payload: PortfolioTransactionCreate) -> Decimal:
        if payload.txn_type in {"buy", "sell"}:
            return payload.quantity * payload.price * BROKER_FEE_RATE
        return ZERO

    def _total_amount(self, trx: PortfolioTransaction) -> Decimal:
        gross = trx.quantity * trx.price if trx.txn_type in {"buy", "sell"} else trx.price
        if trx.txn_type == "sell":
            return gross - trx.fees
        if trx.txn_type == "buy":
            return gross + trx.fees
        return gross

    def _share_value(self, trx: PortfolioTransaction) -> Decimal:
        if trx.txn_type in {"buy", "sell"}:
            return trx.quantity * trx.price
        return trx.price

    def _cash_flow(self, trx: PortfolioTransaction) -> Decimal:
        amount = self._total_amount(trx)
        if trx.txn_type in {"buy", "withdraw"}:
            return -amount
        if trx.txn_type in {"sell", "income", "deposit"}:
            return amount
        return ZERO

    async def _response_transaction(self, trx: PortfolioTransaction):
        stock = await self.repo.get_stock(trx.stock_id) if trx.stock_id else None
        return {
            "id": trx.id,
            "stock_id": trx.stock_id,
            "broker_account_id": trx.broker_account_id,
            "txn_type": trx.txn_type,
            "quantity": trx.quantity,
            "price": trx.price,
            "fees": trx.fees,
            "total_amount": self._total_amount(trx),
            "cash_flow": self._cash_flow(trx),
            "txn_date": trx.txn_date,
            "record_date": trx.record_date,
            "notes": trx.notes,
            "stock": stock,
        }

    def _percent(self, value: Decimal, base: Decimal) -> Decimal:
        if not base:
            return ZERO
        return value / base * Decimal("100")

    def _cagr_percent(
        self,
        invested_capital: Decimal,
        ending_value: Decimal,
        transactions: list[PortfolioTransaction],
    ) -> Decimal:
        if invested_capital <= ZERO or ending_value <= ZERO:
            return ZERO
        start_date = self._portfolio_start_date(transactions)
        if start_date is None:
            return ZERO
        days = max((date.today() - start_date).days, 1)
        years = Decimal(days) / Decimal("365.25")
        if years <= ZERO:
            return ZERO
        ratio = ending_value / invested_capital
        try:
            annualized = Decimal(str(float(ratio) ** (1 / float(years)))) - Decimal("1")
        except (OverflowError, ValueError):
            return ZERO
        return annualized * Decimal("100")

    def _portfolio_start_date(self, transactions: list[PortfolioTransaction]) -> date | None:
        candidates = [
            transaction.txn_date
            for transaction in transactions
            if transaction.txn_type in {"deposit", "buy"}
        ]
        return min(candidates) if candidates else None

    def _empty_dividend_estimate(self, symbol: str, tax_rate_percent: Decimal, message: str):
        return {
            "symbol": symbol,
            "found": False,
            "source": None,
            "record_date": None,
            "payment_date": date.today(),
            "year": None,
            "cash_dividend_percent": None,
            "dividend_per_share": None,
            "eligible_quantity": ZERO,
            "gross_amount": ZERO,
            "tax_rate_percent": tax_rate_percent,
            "tax_amount": ZERO,
            "net_amount": ZERO,
            "message": message,
        }

    def _dividend_estimate_message(self, has_stock: bool, has_record_date: bool) -> str | None:
        if not has_stock:
            return "DSE declaration found, but no saved local holding was found"
        if not has_record_date:
            return "DSE declaration found. Enter record date manually to calculate eligible holding"
        return None

    async def _automatic_dividend_report(
        self,
        transactions: list[PortfolioTransaction],
        manual_dividend_keys: set[tuple[UUID, int]] | None = None,
    ) -> list[dict]:
        manual_dividend_keys = manual_dividend_keys or set()
        by_stock: dict[UUID, list[PortfolioTransaction]] = {}
        for transaction in transactions:
            if transaction.stock_id and transaction.txn_type in {"buy", "sell"}:
                by_stock.setdefault(transaction.stock_id, []).append(transaction)

        rows = []
        market = MarketPriceService()
        for stock_id, stock_transactions in by_stock.items():
            stock = stock_transactions[0].stock or await self.repo.get_stock(stock_id)
            if not stock:
                continue
            try:
                events = await market.fetch_dse_dividend_events(stock.symbol)
            except Exception:
                continue
            for event in events:
                if event.record_date is None:
                    continue
                if (stock_id, event.year) in manual_dividend_keys:
                    continue
                quantity = self._quantity_on_date(stock_transactions, event.record_date)
                if quantity <= ZERO:
                    continue
                gross_amount = quantity * event.face_value * event.cash_percent / Decimal("100")
                amount = gross_amount - (gross_amount * DEFAULT_DIVIDEND_TAX_RATE / Decimal("100"))
                if amount <= ZERO:
                    continue
                rows.append(
                    {
                        "stock_id": stock_id,
                        "stock_name": stock.name,
                        "year": event.year,
                        "dividend_gain": amount,
                        "record_date": event.record_date,
                        "cash_dividend_percent": event.cash_percent,
                        "eligible_quantity": quantity,
                        "source": event.source,
                    }
                )
        return sorted(rows, key=lambda row: (row["year"], row["stock_name"]), reverse=True)

    def _quantity_on_date(self, transactions: list[PortfolioTransaction], record_date) -> Decimal:
        quantity = ZERO
        for transaction in sorted(transactions, key=lambda item: item.txn_date):
            if transaction.txn_date > record_date:
                continue
            if transaction.txn_type == "buy":
                quantity += transaction.quantity
            elif transaction.txn_type == "sell":
                quantity -= transaction.quantity
        return quantity
