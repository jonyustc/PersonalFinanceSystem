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
            notes=payload.notes,
        )
        await self.create_transaction(user_id, transaction)
        return (await self.repo.dividends(user_id))[0]

    async def dividends(self, user_id: UUID):
        return await self.repo.dividends(user_id)

    async def summary(self, user_id: UUID):
        holdings = await self.repo.holdings(user_id)
        dividends = await self.repo.dividends(user_id)
        broker_accounts = await self.repo.broker_accounts(user_id)
        transactions = await self.repo.transactions(user_id, 10000)

        dividend_by_stock = {}
        dividend_report = {}
        for dividend in dividends:
            dividend_by_stock[dividend.stock_id] = dividend_by_stock.get(dividend.stock_id, ZERO) + dividend.amount
            key = (dividend.stock_id, dividend.payment_date.year)
            dividend_report[key] = dividend_report.get(key, ZERO) + dividend.amount

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
            dividend_income = dividend_by_stock.get(holding.stock_id, ZERO)
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
        dividend_income_total = sum((dividend.amount for dividend in dividends), ZERO)
        realized_total = realized_capital
        overall = realized_total + unrealized_gain_loss

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
                }
                for (stock_id, year), amount in sorted(dividend_report.items(), key=lambda item: (item[0][1], str(item[0][0])))
            ],
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
                self.db.add(Dividend(user_id=user_id, stock_id=trx.stock_id, amount=trx.price, payment_date=trx.txn_date, notes=trx.notes))
            if not trx.stock_id:
                continue
            stock_data = aggregates.setdefault(
                trx.stock_id,
                {"quantity": ZERO, "cost_basis": ZERO, "realized": ZERO},
            )
            if trx.txn_type == "buy":
                stock_data["quantity"] += trx.quantity
                stock_data["cost_basis"] += self._total_amount(trx)
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

    def _cash_flow(self, trx: PortfolioTransaction) -> Decimal:
        amount = self._total_amount(trx)
        if trx.txn_type in {"buy", "withdraw"}:
            return -amount
        if trx.txn_type in {"sell", "income", "deposit"}:
            return amount
        return ZERO

    async def _response_transaction(self, trx: PortfolioTransaction):
        stock = trx.stock
        if not stock and trx.stock_id:
            stock = await self.repo.get_stock(trx.stock_id)
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
            "notes": trx.notes,
            "stock": stock,
        }

    def _percent(self, value: Decimal, base: Decimal) -> Decimal:
        if not base:
            return ZERO
        return value / base * Decimal("100")
