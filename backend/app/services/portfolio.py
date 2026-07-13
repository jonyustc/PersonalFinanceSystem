from datetime import date
from decimal import Decimal
import logging
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.portfolio import Portfolio, PortfolioValueSnapshot
from app.models.stock import Dividend, Holding, PortfolioTransaction
from app.repositories.stock import StockRepository
from app.schemas.stock import (
    DividendCreate,
    PortfolioCreate,
    PortfolioTransactionCreate,
    PortfolioUpdate,
    StockCreate,
    StockUpdate,
)
from app.services.market_price import MarketPriceService
from app.services.sync_tombstone import (
    RESOURCE_PORTFOLIO_TRANSACTIONS,
    RESOURCE_PORTFOLIOS,
    record_tombstone,
)


ZERO = Decimal("0")
BROKER_FEE_RATE = Decimal("0.004")
DEFAULT_DIVIDEND_TAX_RATE = Decimal("10")
DAYS_PER_YEAR = Decimal("365.25")
logger = logging.getLogger("app.portfolio")


class PortfolioService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = StockRepository(db)

    # ===== Portfolios =======================================================
    async def list_portfolios(self, user_id: UUID) -> list[Portfolio]:
        # Broker account = portfolio: keep one portfolio per broker account in sync.
        changed = await self._sync_account_portfolios(user_id)
        if changed:
            await self.db.commit()
        return await self.repo.portfolios(user_id)

    @staticmethod
    def _infer_kind(name: str) -> str:
        low = (name or "").lower()
        if "trade" in low:
            return "mid_term_trading"
        if "invest" in low or "sip" in low:
            return "long_term_sip"
        return "general"

    async def _sync_account_portfolios(self, user_id: UUID) -> bool:
        """Ensure every broker account has a matching portfolio + a general default."""
        portfolios = await self.repo.portfolios(user_id)
        by_account = {p.broker_account_id for p in portfolios if p.broker_account_id}
        has_default = any(p.is_default for p in portfolios)
        changed = False
        for account in await self.repo.broker_accounts(user_id):
            if account.id not in by_account:
                self.db.add(
                    Portfolio(
                        user_id=user_id,
                        name=account.name,
                        kind=self._infer_kind(account.name),
                        broker_account_id=account.id,
                        is_default=False,
                    )
                )
                changed = True
        if not has_default:
            self.db.add(
                Portfolio(
                    user_id=user_id,
                    name="My Portfolio",
                    kind="general",
                    is_default=True,
                )
            )
            changed = True
        if changed:
            await self.db.flush()
        return changed

    async def create_portfolio(self, user_id: UUID, payload: PortfolioCreate) -> Portfolio:
        existing = await self.repo.get_portfolio_by_name(user_id, payload.name)
        if existing:
            raise HTTPException(409, "A portfolio with this name already exists")
        has_any = bool(await self.repo.portfolios(user_id))
        portfolio = Portfolio(
            user_id=user_id,
            name=payload.name.strip(),
            kind=payload.kind,
            description=payload.description,
            is_default=not has_any,
        )
        self.db.add(portfolio)
        await self.db.commit()
        await self.db.refresh(portfolio)
        return portfolio

    async def update_portfolio(
        self, user_id: UUID, portfolio_id: UUID, payload: PortfolioUpdate
    ) -> Portfolio:
        portfolio = await self.repo.get_portfolio(user_id, portfolio_id)
        if not portfolio:
            raise HTTPException(404, "Portfolio not found")
        data = payload.model_dump(exclude_unset=True)
        if "name" in data and data["name"]:
            clash = await self.repo.get_portfolio_by_name(user_id, data["name"])
            if clash and clash.id != portfolio_id:
                raise HTTPException(409, "A portfolio with this name already exists")
            data["name"] = data["name"].strip()
        for field, value in data.items():
            setattr(portfolio, field, value)
        await self.db.commit()
        await self.db.refresh(portfolio)
        return portfolio

    async def delete_portfolio(self, user_id: UUID, portfolio_id: UUID) -> None:
        portfolio = await self.repo.get_portfolio(user_id, portfolio_id)
        if not portfolio:
            raise HTTPException(404, "Portfolio not found")
        if portfolio.is_default:
            raise HTTPException(400, "Cannot delete the default portfolio")
        transactions = await self.repo.transactions(user_id, 1, portfolio_id)
        if transactions:
            raise HTTPException(
                400, "Move or delete this portfolio's transactions before deleting it"
            )
        await self.db.delete(portfolio)
        await record_tombstone(self.db, user_id, RESOURCE_PORTFOLIOS, portfolio_id)
        await self.db.commit()

    async def _create_default_portfolio(self, user_id: UUID) -> Portfolio:
        portfolio = Portfolio(
            user_id=user_id,
            name="My Portfolio",
            kind="general",
            is_default=True,
        )
        self.db.add(portfolio)
        await self.db.flush()
        return portfolio

    async def _resolve_portfolio(
        self,
        user_id: UUID,
        portfolio_id: UUID | None,
        broker_account_id: UUID | None = None,
    ) -> Portfolio:
        # Broker account wins: a trade's portfolio is its broker account's portfolio.
        if broker_account_id:
            portfolios = await self.repo.portfolios(user_id)
            for portfolio in portfolios:
                if portfolio.broker_account_id == broker_account_id:
                    return portfolio
            account = await self.db.get(Account, broker_account_id)
            portfolio = Portfolio(
                user_id=user_id,
                name=account.name if account else "Broker Portfolio",
                kind=self._infer_kind(account.name) if account else "general",
                broker_account_id=broker_account_id,
                is_default=False,
            )
            self.db.add(portfolio)
            await self.db.flush()
            return portfolio
        if portfolio_id:
            portfolio = await self.repo.get_portfolio(user_id, portfolio_id)
            if not portfolio:
                raise HTTPException(404, "Portfolio not found")
            return portfolio
        portfolio = await self.repo.get_default_portfolio(user_id)
        if not portfolio:
            portfolio = await self._create_default_portfolio(user_id)
        return portfolio

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
        try:
            price_map = await MarketPriceService().fetch_dse_latest_prices()
        except Exception as exc:
            return {
                "updated": 0,
                "source": "DSE",
                "fetched_at": "",
                "missing_symbols": [stock.symbol],
                "stocks": [],
                "message": f"Could not reach DSE market data right now ({type(exc).__name__}). Please try again later.",
            }
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
                "message": "No stocks to update.",
            }
        try:
            price_map = await MarketPriceService().fetch_dse_latest_prices()
        except Exception as exc:
            return {
                "updated": 0,
                "source": "DSE",
                "fetched_at": "",
                "missing_symbols": [stock.symbol for stock in stocks],
                "stocks": [],
                "message": f"Could not reach DSE market data right now ({type(exc).__name__}). Please try again later.",
            }
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
            events = await MarketPriceService().fetch_dse_dividend_events(
                normalized_symbol
            )
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
            "message": self._dividend_estimate_message(
                stock is not None, event.record_date is not None
            ),
        }

    async def create_transaction(
        self, user_id: UUID, payload: PortfolioTransactionCreate
    ):
        try:
            # Idempotent create for replayed offline pushes.
            if payload.id is not None:
                existing = await self.repo.get_transaction(user_id, payload.id)
                if existing is not None:
                    return await self._response_transaction(existing)
            stock = None
            if payload.stock_id:
                stock = await self.repo.get_stock(payload.stock_id)
                if not stock:
                    raise HTTPException(404, "Stock not found")
            elif payload.stock:
                stock = await self.repo.get_or_create_stock(payload.stock)

            broker_account = await self._get_broker_account(
                user_id, payload.broker_account_id
            )
            portfolio = await self._resolve_portfolio(
                user_id,
                payload.portfolio_id,
                broker_account.id if broker_account else None,
            )
            fees = (
                payload.fees if payload.fees is not None else self._default_fee(payload)
            )
            trx = PortfolioTransaction(
                **({"id": payload.id} if payload.id is not None else {}),
                user_id=user_id,
                portfolio_id=portfolio.id,
                stock_id=stock.id if stock else None,
                broker_account_id=broker_account.id if broker_account else None,
                txn_type=payload.txn_type,
                quantity=payload.quantity,
                price=payload.price,
                fees=fees,
                txn_date=payload.txn_date,
                record_date=payload.record_date
                if payload.txn_type == "income"
                else None,
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

    async def list_transactions(
        self, user_id: UUID, limit: int = 100, portfolio_id: UUID | None = None
    ):
        return [
            await self._response_transaction(item)
            for item in await self.repo.transactions(user_id, limit, portfolio_id)
            if item.txn_type != "deposit"
        ]

    async def update_transaction(
        self, user_id: UUID, transaction_id: UUID, payload: PortfolioTransactionCreate
    ):
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

            new_broker = await self._get_broker_account(
                user_id, payload.broker_account_id
            )
            portfolio = await self._resolve_portfolio(
                user_id,
                payload.portfolio_id or trx.portfolio_id,
                new_broker.id if new_broker else None,
            )
            trx.portfolio_id = portfolio.id
            trx.stock_id = stock.id if stock else None
            trx.broker_account_id = new_broker.id if new_broker else None
            trx.txn_type = payload.txn_type
            trx.quantity = payload.quantity
            trx.price = payload.price
            trx.fees = (
                payload.fees if payload.fees is not None else self._default_fee(payload)
            )
            trx.txn_date = payload.txn_date
            trx.record_date = (
                payload.record_date if payload.txn_type == "income" else None
            )
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
            broker_account = await self._get_broker_account(
                user_id, trx.broker_account_id
            )
            await self._apply_broker_cash(trx, broker_account, reverse=True)
            await self.db.delete(trx)
            await record_tombstone(
                self.db, user_id, RESOURCE_PORTFOLIO_TRANSACTIONS, transaction_id
            )
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
            portfolio_id=payload.portfolio_id,
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

    async def summary(
        self,
        user_id: UUID,
        include_auto_dividends: bool = False,
        portfolio_id: UUID | None = None,
    ):
        portfolio = None
        if portfolio_id is not None:
            portfolio = await self._resolve_portfolio(user_id, portfolio_id)
            portfolio_id = portfolio.id

        transactions = await self.repo.transactions(user_id, 10000)
        has_stock_activity = any(
            transaction.stock_id and transaction.txn_type in {"buy", "sell", "income"}
            for transaction in transactions
        )
        rebuilt = False
        if has_stock_activity:
            try:
                await self._rebuild_derived(user_id)
                await self.db.commit()
                rebuilt = True
            except HTTPException as exc:
                await self.db.rollback()
                logger.warning(
                    "portfolio_summary_rebuild_failed_using_existing_rows",
                    extra={"user_id": str(user_id), "detail": exc.detail},
                )

        # Capture today's per-portfolio value snapshot (chart history, forward-only).
        if rebuilt:
            try:
                await self._capture_today_snapshots(user_id)
                await self.db.commit()
            except Exception:
                await self.db.rollback()

        # Re-fetch scoped to the requested portfolio (or whole account).
        transactions = await self.repo.transactions(user_id, 10000, portfolio_id)
        holdings = await self.repo.holdings(user_id, portfolio_id)
        dividends = await self.repo.dividends(user_id, portfolio_id)
        broker_accounts = await self.repo.broker_accounts(user_id)

        core = self._core_valuation(holdings, dividends, transactions)

        # Year-grouped manual dividend report.
        dividend_report: dict[tuple[UUID, int], dict] = {}
        for dividend in dividends:
            key_date = dividend.record_date or dividend.payment_date
            key = (dividend.stock_id, key_date.year)
            row = dividend_report.setdefault(
                key,
                {
                    "amount": ZERO,
                    "record_date": dividend.record_date,
                    "payment_date": dividend.payment_date,
                },
            )
            row["amount"] += dividend.amount
            if row["record_date"] is None:
                row["record_date"] = dividend.record_date
            if (
                row["payment_date"] is None
                or dividend.payment_date > row["payment_date"]
            ):
                row["payment_date"] = dividend.payment_date

        manual_dividend_keys = set(dividend_report)
        auto_dividend_report = (
            await self._automatic_dividend_report(transactions, manual_dividend_keys)
            if include_auto_dividends
            else []
        )
        auto_dividend_by_stock: dict[UUID, Decimal] = {}
        for row in auto_dividend_report:
            auto_dividend_by_stock[row["stock_id"]] = (
                auto_dividend_by_stock.get(row["stock_id"], ZERO) + row["dividend_gain"]
            )

        # Layer auto dividends onto the per-holding rows (once per stock).
        auto_credited: set[UUID] = set()
        for holding_row in core["holding_rows"]:
            stock_id = holding_row["stock"].id
            if stock_id in auto_dividend_by_stock and stock_id not in auto_credited:
                auto_amount = auto_dividend_by_stock[stock_id]
                auto_credited.add(stock_id)
                holding_row["dividend_income"] += auto_amount
                holding_row["total_profit_loss"] += auto_amount
                holding_row["total_return"] += auto_amount
                self._apply_recovery_metrics(holding_row)

        equity_value = core["equity_value"]
        active_cost_basis = core["active_cost_basis"]
        realized_total = core["realized_total"]
        unrealized_gain_loss = core["unrealized_gain_loss"]
        principal = core["principal"]
        total_withdrawals = core["total_withdrawals"]
        # Total Investment = deposited cash. If a portfolio has no recorded deposits,
        # fall back to its current cost basis so ROI/Wealth don't divide by zero.
        total_investment = core["total_investment"] or active_cost_basis or core[
            "total_buy_investment"
        ]

        # Portfolio cash is derived from portfolio activity (deposits − buys + sells +
        # dividends − withdrawals). Broker-account balances are maintained separately in
        # the Accounts module and would double-count the deposited capital here.
        cash_balance = core["derived_cash"]
        total_portfolio = equity_value + cash_balance

        dividend_income_total = core["dividend_income_manual"] + sum(
            (row["dividend_gain"] for row in auto_dividend_report), ZERO
        )
        total_return = realized_total + dividend_income_total + unrealized_gain_loss
        overall = realized_total + unrealized_gain_loss
        cagr_percent = self._cagr_percent(principal, total_portfolio, transactions)
        net_capital_invested = (
            total_investment - realized_total - dividend_income_total - total_withdrawals
        )
        capital_recovery_percent = self._percent(
            realized_total + dividend_income_total, total_investment
        )
        wealth_multiple = (
            (equity_value + total_withdrawals) / total_investment
            if total_investment > ZERO
            else ZERO
        )

        return {
            "total_principal_investment": principal,
            "invested_capital": principal,
            "active_cost_basis": active_cost_basis,
            "current_equity_value": equity_value,
            "unrealized_gain_loss": unrealized_gain_loss,
            "cash_balance": cash_balance,
            "total_portfolio_value": total_portfolio,
            "total_realized_capital_gain_loss": realized_total,
            "dividend_income": dividend_income_total,
            "total_realized_profit": realized_total,
            "overall_profit_loss": overall,
            "return_percent": self._percent(overall, principal),
            "cagr_percent": cagr_percent,
            "portfolio_id": portfolio.id if portfolio else None,
            "portfolio_name": portfolio.name if portfolio else None,
            "total_investment": total_investment,
            "total_dividend_income": dividend_income_total,
            "total_unrealized_gain": unrealized_gain_loss,
            "total_return": total_return,
            "roi_percent": self._percent(total_return, total_investment),
            "net_capital_invested": net_capital_invested,
            "capital_recovery_percent": capital_recovery_percent,
            "wealth_multiple": wealth_multiple,
            "total_withdrawals": total_withdrawals,
            "broker_accounts": [
                {
                    "id": account.id,
                    "name": account.name,
                    "balance": account.balance,
                    "currency": account.currency,
                }
                for account in broker_accounts
            ],
            "holdings": core["holding_rows"],
            "dividend_report": [
                {
                    "stock_id": stock_id,
                    "stock_name": next(
                        (d.stock.name for d in dividends if d.stock_id == stock_id), ""
                    ),
                    "year": year,
                    "dividend_gain": row["amount"],
                    "record_date": row["record_date"],
                    "payment_date": row["payment_date"],
                    "source": "manual",
                }
                for (stock_id, year), row in sorted(
                    dividend_report.items(),
                    key=lambda item: (item[0][1], str(item[0][0])),
                )
            ]
            + auto_dividend_report,
            "auto_dividend_report": auto_dividend_report,
        }

    def _core_valuation(
        self,
        holdings: list[Holding],
        dividends: list[Dividend],
        transactions: list[PortfolioTransaction],
    ) -> dict:
        """Shared valuation math for both the summary and daily snapshots.

        Broker Cost Basis = avg_buy_price (BUY-only weighted average).
        Effective Cost Basis = (holding cost − realized − dividend) / qty.
        """
        dividend_by_key: dict[tuple[UUID | None, UUID], Decimal] = {}
        for dividend in dividends:
            key = (dividend.portfolio_id, dividend.stock_id)
            dividend_by_key[key] = dividend_by_key.get(key, ZERO) + dividend.amount

        holding_rows: list[dict] = []
        active_cost_basis = ZERO
        equity_value = ZERO
        realized_total = ZERO
        for holding in holdings:
            realized_total += holding.realized_profit_loss
            if holding.quantity <= ZERO:
                continue
            last_price = holding.stock.last_price or ZERO
            market_price = last_price if last_price > ZERO else holding.avg_buy_price
            invested = holding.quantity * holding.avg_buy_price
            market_value = holding.quantity * market_price
            unrealized = market_value - invested
            key = (holding.portfolio_id, holding.stock_id)
            dividend_income = dividend_by_key.get(key, ZERO)
            # Per-holding recovery/wealth use the current cost basis as the base.
            stock_total_investment = invested
            realized = holding.realized_profit_loss
            total_pl = unrealized + realized
            total_return = unrealized + realized + dividend_income
            recovered = realized + dividend_income
            effective_cost_basis = (
                (invested - recovered) / holding.quantity if holding.quantity else ZERO
            )
            active_cost_basis += invested
            equity_value += market_value
            holding_rows.append(
                {
                    "stock": holding.stock,
                    "portfolio_id": holding.portfolio_id,
                    "quantity": holding.quantity,
                    "avg_buy_price": holding.avg_buy_price,
                    "broker_cost_basis": holding.avg_buy_price,
                    "market_price": market_price,
                    "invested_amount": invested,
                    "market_value": market_value,
                    "unrealized_profit_loss": unrealized,
                    "unrealized_percent": self._percent(unrealized, invested),
                    "realized_profit_loss": realized,
                    "dividend_income": dividend_income,
                    "total_profit_loss": total_pl,
                    "total_return": total_return,
                    "effective_cost_basis": effective_cost_basis,
                    "net_capital_invested": stock_total_investment - recovered,
                    "capital_recovery_percent": self._percent(
                        recovered, stock_total_investment
                    ),
                    "wealth_multiple": (
                        market_value / stock_total_investment
                        if stock_total_investment > ZERO
                        else ZERO
                    ),
                    "_stock_total_investment": stock_total_investment,
                }
            )

        principal = sum(
            (self._total_amount(t) for t in transactions if t.txn_type == "deposit"),
            ZERO,
        )
        # Total Investment = cash deposited into the portfolio (buys/sells are internal
        # reallocation). Cumulative gross buys kept separately for reference only.
        total_buy_investment = sum(
            (self._total_amount(t) for t in transactions if t.txn_type == "buy"), ZERO
        )
        total_investment = principal
        total_withdrawals = sum(
            (self._total_amount(t) for t in transactions if t.txn_type == "withdraw"),
            ZERO,
        )
        derived_cash = sum((self._cash_flow(t) for t in transactions), ZERO)
        dividend_income_manual = sum((d.amount for d in dividends), ZERO)
        return {
            "holding_rows": holding_rows,
            "active_cost_basis": active_cost_basis,
            "equity_value": equity_value,
            "realized_total": realized_total,
            "unrealized_gain_loss": equity_value - active_cost_basis,
            "principal": principal,
            "total_investment": total_investment,
            "total_buy_investment": total_buy_investment,
            "total_withdrawals": total_withdrawals,
            "derived_cash": derived_cash,
            "dividend_income_manual": dividend_income_manual,
        }

    def _apply_recovery_metrics(self, holding_row: dict) -> None:
        """Recompute recovery-style metrics after dividends change on a row."""
        invested = holding_row["invested_amount"]
        recovered = holding_row["realized_profit_loss"] + holding_row["dividend_income"]
        stock_total_investment = holding_row["_stock_total_investment"]
        qty = holding_row["quantity"]
        holding_row["effective_cost_basis"] = (
            (invested - recovered) / qty if qty else ZERO
        )
        holding_row["net_capital_invested"] = stock_total_investment - recovered
        holding_row["capital_recovery_percent"] = self._percent(
            recovered, stock_total_investment
        )

    # ===== Daily value snapshots ===========================================
    async def _capture_today_snapshots(self, user_id: UUID) -> None:
        portfolios = await self.repo.portfolios(user_id)
        today = date.today()
        for portfolio in portfolios:
            holdings = await self.repo.holdings(user_id, portfolio.id)
            dividends = await self.repo.dividends(user_id, portfolio.id)
            transactions = await self.repo.transactions(user_id, 100000, portfolio.id)
            if not transactions:
                continue
            core = self._core_valuation(holdings, dividends, transactions)
            equity = core["equity_value"]
            cash = core["derived_cash"]
            realized = core["realized_total"]
            unrealized = core["unrealized_gain_loss"]
            dividend_income = core["dividend_income_manual"]
            total_value = equity + cash
            total_return = realized + dividend_income + unrealized
            snapshot = await self.repo.get_snapshot(user_id, portfolio.id, today)
            if snapshot is None:
                snapshot = PortfolioValueSnapshot(
                    user_id=user_id,
                    portfolio_id=portfolio.id,
                    snapshot_date=today,
                )
                self.db.add(snapshot)
            snapshot.equity_value = equity
            snapshot.cash_balance = cash
            snapshot.total_value = total_value
            snapshot.invested_capital = core["total_investment"]
            snapshot.realized_gain = realized
            snapshot.unrealized_gain = unrealized
            snapshot.dividend_income = dividend_income
            snapshot.total_return = total_return

    # ===== Annual performance report =======================================
    async def annual_performance(
        self, user_id: UUID, portfolio_id: UUID | None = None
    ) -> dict:
        if portfolio_id is not None:
            portfolio_id = (await self._resolve_portfolio(user_id, portfolio_id)).id
        transactions = sorted(
            await self.repo.transactions(user_id, 100000, portfolio_id),
            key=lambda t: (t.txn_date, t.created_at, str(t.id)),
        )
        dividends = await self.repo.dividends(user_id, portfolio_id)
        if not transactions and not dividends:
            return {"portfolio_id": portfolio_id, "rows": []}

        price_by_stock: dict[UUID, Decimal] = {}
        for txn in transactions:
            if txn.stock_id and txn.stock is not None:
                price_by_stock[txn.stock_id] = txn.stock.last_price or ZERO

        first_year = min(
            [t.txn_date.year for t in transactions]
            + [(d.record_date or d.payment_date).year for d in dividends]
        )
        last_year = date.today().year
        years = list(range(first_year, last_year + 1))

        per_year = {y: {"new_investment": ZERO, "realized": ZERO, "dividend": ZERO} for y in years}
        for dividend in dividends:
            year = (dividend.record_date or dividend.payment_date).year
            if year in per_year:
                per_year[year]["dividend"] += dividend.amount

        running: dict[tuple[UUID | None, UUID], dict[str, Decimal]] = {}
        year_end_state: dict[int, dict] = {}
        txns_by_year: dict[int, list[PortfolioTransaction]] = {}
        for txn in transactions:
            txns_by_year.setdefault(txn.txn_date.year, []).append(txn)

        for year in years:
            for txn in txns_by_year.get(year, []):
                if not txn.stock_id:
                    continue
                key = (txn.portfolio_id, txn.stock_id)
                data = running.setdefault(key, {"qty": ZERO, "cost": ZERO})
                if txn.txn_type == "buy":
                    per_year[year]["new_investment"] += self._total_amount(txn)
                    data["qty"] += txn.quantity
                    data["cost"] += self._total_amount(txn)
                elif txn.txn_type == "sell" and data["qty"] > ZERO:
                    avg = data["cost"] / data["qty"]
                    removed = avg * txn.quantity
                    per_year[year]["realized"] += self._total_amount(txn) - removed
                    data["qty"] -= txn.quantity
                    data["cost"] -= removed
            year_end_state[year] = {
                k: {"qty": v["qty"], "cost": v["cost"]}
                for k, v in running.items()
                if v["qty"] > ZERO
            }

        rows = []
        prev_ending = ZERO
        for year in years:
            state = year_end_state[year]
            ending_cost = sum((v["cost"] for v in state.values()), ZERO)
            ending_value = sum(
                (v["qty"] * price_by_stock.get(key[1], ZERO) for key, v in state.items()),
                ZERO,
            )
            unrealized = ending_value - ending_cost
            new_investment = per_year[year]["new_investment"]
            realized = per_year[year]["realized"]
            dividend_income = per_year[year]["dividend"]
            beginning = prev_ending
            base = beginning + new_investment
            total_return = (ending_value + realized + dividend_income) - base
            rows.append(
                {
                    "year": year,
                    "beginning_value": beginning,
                    "new_investment": new_investment,
                    "realized_gain": realized,
                    "dividend_income": dividend_income,
                    "unrealized_gain": unrealized,
                    "ending_value": ending_value,
                    "total_return": total_return,
                    "annual_return_percent": self._percent(total_return, base),
                }
            )
            prev_ending = ending_value

        # Trim leading years with no activity at all.
        rows = [
            row
            for row in rows
            if not (
                row["new_investment"] == ZERO
                and row["realized_gain"] == ZERO
                and row["dividend_income"] == ZERO
                and row["beginning_value"] == ZERO
                and row["ending_value"] == ZERO
            )
        ]
        return {"portfolio_id": portfolio_id, "rows": rows}

    # ===== Performance series (charts) =====================================
    async def performance_series(
        self, user_id: UUID, portfolio_id: UUID | None = None
    ) -> dict:
        if portfolio_id is not None:
            portfolio_id = (await self._resolve_portfolio(user_id, portfolio_id)).id
        transactions = sorted(
            await self.repo.transactions(user_id, 100000, portfolio_id),
            key=lambda t: (t.txn_date, t.created_at, str(t.id)),
        )
        dividends = await self.repo.dividends(user_id, portfolio_id)
        holdings = await self.repo.holdings(user_id, portfolio_id)
        snapshots = await self.repo.snapshots(user_id, portfolio_id)

        growth = self._reconstruct_monthly_growth(transactions, dividends, snapshots)

        core = self._core_valuation(holdings, dividends, transactions)
        return_composition = [
            {"label": "Realized Gain", "value": core["realized_total"]},
            {"label": "Unrealized Gain", "value": core["unrealized_gain_loss"]},
            {"label": "Dividend Income", "value": core["dividend_income_manual"]},
        ]

        annual = await self.annual_performance(user_id, portfolio_id)
        annual_return = [
            {"year": row["year"], "annual_return_percent": row["annual_return_percent"]}
            for row in annual["rows"]
        ]
        return {
            "portfolio_id": portfolio_id,
            "growth": growth,
            "return_composition": return_composition,
            "annual_return": annual_return,
        }

    def _reconstruct_monthly_growth(
        self,
        transactions: list[PortfolioTransaction],
        dividends: list[Dividend],
        snapshots: list[PortfolioValueSnapshot],
    ) -> list[dict]:
        if not transactions:
            return []
        price_by_stock: dict[UUID, Decimal] = {}
        for txn in transactions:
            if txn.stock_id and txn.stock is not None:
                price_by_stock[txn.stock_id] = txn.stock.last_price or ZERO

        # Aggregate authoritative snapshots by month (latest day in the month wins).
        snapshot_by_month: dict[str, PortfolioValueSnapshot] = {}
        for snap in snapshots:
            month = snap.snapshot_date.strftime("%Y-%m")
            current = snapshot_by_month.get(month)
            if current is None or snap.snapshot_date > current.snapshot_date:
                snapshot_by_month[month] = snap

        dividends_by_month: dict[str, Decimal] = {}
        for dividend in dividends:
            month = dividend.payment_date.strftime("%Y-%m")
            dividends_by_month[month] = dividends_by_month.get(month, ZERO) + dividend.amount

        txns_by_month: dict[str, list[PortfolioTransaction]] = {}
        for txn in transactions:
            txns_by_month.setdefault(txn.txn_date.strftime("%Y-%m"), []).append(txn)

        months = self._month_range(
            transactions[0].txn_date, date.today()
        )
        running: dict[tuple[UUID | None, UUID], dict[str, Decimal]] = {}
        realized_cum = ZERO
        dividend_cum = ZERO
        cash_cum = ZERO
        points = []
        for month in months:
            for txn in txns_by_month.get(month, []):
                cash_cum += self._cash_flow(txn)
                if not txn.stock_id:
                    continue
                key = (txn.portfolio_id, txn.stock_id)
                data = running.setdefault(key, {"qty": ZERO, "cost": ZERO})
                if txn.txn_type == "buy":
                    data["qty"] += txn.quantity
                    data["cost"] += self._total_amount(txn)
                elif txn.txn_type == "sell" and data["qty"] > ZERO:
                    avg = data["cost"] / data["qty"]
                    removed = avg * txn.quantity
                    realized_cum += self._total_amount(txn) - removed
                    data["qty"] -= txn.quantity
                    data["cost"] -= removed
            dividend_cum += dividends_by_month.get(month, ZERO)

            snap = snapshot_by_month.get(month)
            if snap is not None:
                portfolio_value = snap.total_value
                cumulative_return = snap.total_return
            else:
                equity = sum(
                    (
                        v["qty"] * price_by_stock.get(key[1], ZERO)
                        for key, v in running.items()
                    ),
                    ZERO,
                )
                cost = sum((v["cost"] for v in running.values()), ZERO)
                unrealized = equity - cost
                portfolio_value = equity + cash_cum
                cumulative_return = realized_cum + dividend_cum + unrealized
            points.append(
                {
                    "period": month,
                    "portfolio_value": portfolio_value,
                    "cumulative_return": cumulative_return,
                }
            )
        return points

    @staticmethod
    def _month_range(start: date, end: date) -> list[str]:
        months = []
        year, month = start.year, start.month
        while (year, month) <= (end.year, end.month):
            months.append(f"{year:04d}-{month:02d}")
            month += 1
            if month > 12:
                month = 1
                year += 1
        return months

    # ===== Advanced analytics (XIRR + trade statistics) ====================
    async def analytics(self, user_id: UUID, portfolio_id: UUID | None = None) -> dict:
        if portfolio_id is not None:
            portfolio_id = (await self._resolve_portfolio(user_id, portfolio_id)).id
        transactions = sorted(
            await self.repo.transactions(user_id, 100000, portfolio_id),
            key=lambda t: (t.txn_date, t.created_at, str(t.id)),
        )
        dividends = await self.repo.dividends(user_id, portfolio_id)
        holdings = await self.repo.holdings(user_id, portfolio_id)
        core = self._core_valuation(holdings, dividends, transactions)
        equity_value = core["equity_value"]

        # ---- Portfolio XIRR ----
        flows: list[tuple[date, Decimal]] = []
        for txn in transactions:
            if txn.txn_type == "buy":
                flows.append((txn.txn_date, -self._total_amount(txn)))
            elif txn.txn_type == "sell":
                flows.append((txn.txn_date, self._total_amount(txn)))
            elif txn.txn_type == "withdraw":
                flows.append((txn.txn_date, self._total_amount(txn)))
        for dividend in dividends:
            flows.append((dividend.payment_date, dividend.amount))
        if equity_value > ZERO:
            flows.append((date.today(), equity_value))
        portfolio_xirr = self._xirr(flows)

        # ---- Stock-wise XIRR ----
        market_price: dict[UUID, Decimal] = {}
        symbol_name: dict[UUID, tuple[str, str]] = {}
        for txn in transactions:
            if txn.stock_id and txn.stock is not None:
                market_price[txn.stock_id] = txn.stock.last_price or ZERO
                symbol_name[txn.stock_id] = (txn.stock.symbol, txn.stock.name)
        qty_by_stock: dict[UUID, Decimal] = {}
        for holding in holdings:
            qty_by_stock[holding.stock_id] = (
                qty_by_stock.get(holding.stock_id, ZERO) + holding.quantity
            )
        dividend_by_stock: dict[UUID, list[tuple[date, Decimal]]] = {}
        for dividend in dividends:
            dividend_by_stock.setdefault(dividend.stock_id, []).append(
                (dividend.payment_date, dividend.amount)
            )
        txns_by_stock: dict[UUID, list[PortfolioTransaction]] = {}
        for txn in transactions:
            if txn.stock_id and txn.txn_type in {"buy", "sell"}:
                txns_by_stock.setdefault(txn.stock_id, []).append(txn)

        stock_xirr = []
        for stock_id, stock_txns in txns_by_stock.items():
            stock_flows: list[tuple[date, Decimal]] = []
            for txn in stock_txns:
                amount = self._total_amount(txn)
                stock_flows.append(
                    (txn.txn_date, -amount if txn.txn_type == "buy" else amount)
                )
            for pay_date, amount in dividend_by_stock.get(stock_id, []):
                stock_flows.append((pay_date, amount))
            remaining_qty = qty_by_stock.get(stock_id, ZERO)
            if remaining_qty > ZERO:
                stock_flows.append(
                    (date.today(), remaining_qty * market_price.get(stock_id, ZERO))
                )
            symbol, name = symbol_name.get(stock_id, ("", ""))
            stock_xirr.append(
                {
                    "stock_id": stock_id,
                    "symbol": symbol,
                    "name": name,
                    "xirr_percent": self._xirr(stock_flows),
                }
            )
        stock_xirr.sort(key=lambda row: row["symbol"])

        # ---- Trade statistics (per realized sell) ----
        trade_stats = self._trade_statistics(transactions, symbol_name)

        return {
            "portfolio_id": portfolio_id,
            "portfolio_xirr_percent": portfolio_xirr,
            "cagr_percent": self._cagr_percent(
                core["principal"], equity_value + core["derived_cash"], transactions
            ),
            "stock_xirr": stock_xirr,
            **trade_stats,
        }

    def _trade_statistics(
        self,
        transactions: list[PortfolioTransaction],
        symbol_name: dict[UUID, tuple[str, str]],
    ) -> dict:
        # Replay buys/sells per stock to derive realized trades and holding periods.
        running: dict[UUID, dict[str, Decimal]] = {}
        trades: list[dict] = []
        for txn in transactions:
            if not txn.stock_id or txn.txn_type not in {"buy", "sell"}:
                continue
            data = running.setdefault(
                txn.stock_id, {"qty": ZERO, "cost": ZERO, "weighted_days": ZERO}
            )
            if txn.txn_type == "buy":
                data["qty"] += txn.quantity
                data["cost"] += self._total_amount(txn)
                # Track quantity-weighted buy date as ordinal days.
                data["weighted_days"] += txn.quantity * Decimal(txn.txn_date.toordinal())
            elif txn.txn_type == "sell" and data["qty"] > ZERO:
                avg_cost = data["cost"] / data["qty"]
                avg_buy_ordinal = data["weighted_days"] / data["qty"]
                removed = avg_cost * txn.quantity
                profit = self._total_amount(txn) - removed
                holding_days = Decimal(txn.txn_date.toordinal()) - avg_buy_ordinal
                symbol, name = symbol_name.get(txn.stock_id, ("", ""))
                trades.append(
                    {
                        "symbol": symbol,
                        "name": name,
                        "profit": profit,
                        "return_percent": self._percent(profit, removed),
                        "qty": txn.quantity,
                        "holding_days": holding_days,
                    }
                )
                # Reduce position proportionally (including weighted-date pool).
                fraction = (data["qty"] - txn.quantity) / data["qty"]
                data["cost"] -= removed
                data["weighted_days"] *= fraction
                data["qty"] -= txn.quantity

        total_trades = len(trades)
        winners = [t for t in trades if t["profit"] > ZERO]
        losers = [t for t in trades if t["profit"] < ZERO]
        gross_profit = sum((t["profit"] for t in winners), ZERO)
        gross_loss = sum((-t["profit"] for t in losers), ZERO)
        total_qty = sum((t["qty"] for t in trades), ZERO)
        weighted_holding = sum((t["holding_days"] * t["qty"] for t in trades), ZERO)

        best = max(trades, key=lambda t: t["profit"], default=None)
        worst = min(trades, key=lambda t: t["profit"], default=None)

        buy_total = sum(
            (self._total_amount(t) for t in transactions if t.txn_type == "buy"), ZERO
        )
        sell_total = sum(
            (self._total_amount(t) for t in transactions if t.txn_type == "sell"), ZERO
        )

        return {
            "win_rate_percent": self._percent(
                Decimal(len(winners)), Decimal(total_trades)
            )
            if total_trades
            else ZERO,
            "profit_factor": (gross_profit / gross_loss) if gross_loss > ZERO else None,
            "average_gain_percent": (
                sum((t["return_percent"] for t in winners), ZERO) / Decimal(len(winners))
                if winners
                else ZERO
            ),
            "average_loss_percent": (
                sum((t["return_percent"] for t in losers), ZERO) / Decimal(len(losers))
                if losers
                else ZERO
            ),
            "best_trade": self._trade_stat(best),
            "worst_trade": self._trade_stat(worst),
            "average_holding_period_days": (
                weighted_holding / total_qty if total_qty > ZERO else ZERO
            ),
            "portfolio_turnover_ratio": (
                min(buy_total, sell_total) / buy_total if buy_total > ZERO else ZERO
            ),
            "total_trades": total_trades,
            "winning_trades": len(winners),
            "losing_trades": len(losers),
        }

    @staticmethod
    def _trade_stat(trade: dict | None) -> dict | None:
        if trade is None:
            return None
        return {
            "symbol": trade["symbol"],
            "name": trade["name"],
            "profit": trade["profit"],
            "return_percent": trade["return_percent"],
        }

    def _xirr(self, flows: list[tuple[date, Decimal]]) -> Decimal | None:
        """Money-weighted return solved via Newton's method with a bisection fallback."""
        if len(flows) < 2:
            return None
        amounts = [float(amount) for _, amount in flows]
        if not any(a > 0 for a in amounts) or not any(a < 0 for a in amounts):
            return None
        base_date = min(d for d, _ in flows)
        days = [float((d - base_date).days) for d, _ in flows]

        def npv(rate: float) -> float:
            return sum(
                amount / ((1.0 + rate) ** (day / 365.0))
                for amount, day in zip(amounts, days)
            )

        def dnpv(rate: float) -> float:
            return sum(
                -(day / 365.0) * amount / ((1.0 + rate) ** (day / 365.0 + 1.0))
                for amount, day in zip(amounts, days)
            )

        rate = 0.1
        for _ in range(100):
            try:
                value = npv(rate)
            except (OverflowError, ZeroDivisionError, ValueError):
                break
            if abs(value) < 1e-7:
                return self._safe_percent(rate)
            slope = dnpv(rate)
            if slope == 0:
                break
            new_rate = rate - value / slope
            if new_rate <= -0.9999999:
                new_rate = (rate - 0.9999) / 2
            if abs(new_rate - rate) < 1e-9:
                return self._safe_percent(new_rate)
            rate = new_rate

        low, high = -0.9999, 100.0
        try:
            f_low, f_high = npv(low), npv(high)
        except (OverflowError, ValueError):
            return None
        if f_low * f_high > 0:
            return None
        for _ in range(200):
            mid = (low + high) / 2
            f_mid = npv(mid)
            if abs(f_mid) < 1e-7:
                return self._safe_percent(mid)
            if f_low * f_mid < 0:
                high, f_high = mid, f_mid
            else:
                low, f_low = mid, f_mid
        return self._safe_percent((low + high) / 2)

    @staticmethod
    def _safe_percent(rate: float) -> Decimal | None:
        try:
            return Decimal(str(round(rate * 100, 4)))
        except (ValueError, OverflowError):
            return None

    async def _apply_broker_cash(
        self,
        trx: PortfolioTransaction,
        broker_account: Account | None,
        reverse: bool = False,
    ):
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
                    .order_by(
                        PortfolioTransaction.txn_date,
                        PortfolioTransaction.created_at,
                        PortfolioTransaction.id,
                    )
                )
            ).scalars()
        )
        # Aggregate per (portfolio, stock) so holdings are portfolio-scoped.
        aggregates: dict[tuple[UUID | None, UUID], dict[str, Decimal]] = {}
        for trx in transactions:
            if trx.txn_type == "income" and trx.stock_id:
                self.db.add(
                    Dividend(
                        user_id=user_id,
                        portfolio_id=trx.portfolio_id,
                        stock_id=trx.stock_id,
                        amount=trx.price,
                        payment_date=trx.txn_date,
                        record_date=trx.record_date,
                        notes=trx.notes,
                    )
                )
            if not trx.stock_id:
                continue
            key = (trx.portfolio_id, trx.stock_id)
            stock_data = aggregates.setdefault(
                key,
                {"quantity": ZERO, "cost_basis": ZERO, "realized": ZERO},
            )
            if trx.txn_type == "buy":
                stock_data["quantity"] += trx.quantity
                # Capitalize buy charges into cost basis (keeps cost/realized fee-consistent).
                stock_data["cost_basis"] += self._total_amount(trx)
            elif trx.txn_type == "sell":
                if trx.quantity > stock_data["quantity"]:
                    raise HTTPException(400, "Sell quantity exceeds holding")
                avg_cost = (
                    stock_data["cost_basis"] / stock_data["quantity"]
                    if stock_data["quantity"]
                    else ZERO
                )
                removed_cost = avg_cost * trx.quantity
                stock_data["quantity"] -= trx.quantity
                stock_data["cost_basis"] -= removed_cost
                stock_data["realized"] += self._total_amount(trx) - removed_cost

        for (portfolio_id, stock_id), data in aggregates.items():
            net_qty = data["quantity"]
            adjusted_cost_basis = data["cost_basis"] if net_qty > ZERO else ZERO
            realized_profit_loss = data["realized"]
            avg_buy_price = adjusted_cost_basis / net_qty if net_qty > ZERO else ZERO
            self.db.add(
                Holding(
                    user_id=user_id,
                    portfolio_id=portfolio_id,
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
        gross = (
            trx.quantity * trx.price if trx.txn_type in {"buy", "sell"} else trx.price
        )
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
        stock = await self.repo.get_stock(trx.stock_id) if trx.stock_id else None
        return {
            "id": trx.id,
            "portfolio_id": trx.portfolio_id,
            "stock_id": trx.stock_id,
            "broker_account_id": trx.broker_account_id,
            "txn_type": trx.txn_type,
            "quantity": trx.quantity,
            "price": trx.price,
            "fees": trx.fees,
            "total_amount": self._total_amount(trx),
            "cash_flow": self._cash_flow(trx),
            "txn_date": trx.txn_date,
            "payment_date": trx.txn_date if trx.txn_type == "income" else None,
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

    def _portfolio_start_date(
        self, transactions: list[PortfolioTransaction]
    ) -> date | None:
        candidates = [
            transaction.txn_date
            for transaction in transactions
            if transaction.txn_type in {"deposit", "buy"}
        ]
        return min(candidates) if candidates else None

    def _empty_dividend_estimate(
        self, symbol: str, tax_rate_percent: Decimal, message: str
    ):
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

    def _dividend_estimate_message(
        self, has_stock: bool, has_record_date: bool
    ) -> str | None:
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
                gross_amount = (
                    quantity * event.face_value * event.cash_percent / Decimal("100")
                )
                amount = gross_amount - (
                    gross_amount * DEFAULT_DIVIDEND_TAX_RATE / Decimal("100")
                )
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
        return sorted(
            rows, key=lambda row: (row["year"], row["stock_name"]), reverse=True
        )

    def _quantity_on_date(
        self, transactions: list[PortfolioTransaction], record_date
    ) -> Decimal:
        quantity = ZERO
        for transaction in sorted(transactions, key=lambda item: item.txn_date):
            if transaction.txn_date > record_date:
                continue
            if transaction.txn_type == "buy":
                quantity += transaction.quantity
            elif transaction.txn_type == "sell":
                quantity -= transaction.quantity
        return quantity
