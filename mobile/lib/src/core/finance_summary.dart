import 'dart:convert';

import 'formatters.dart';

class FinanceSummary {
  FinanceSummary({
    required this.netWorth,
    required this.assets,
    required this.creditCardOutstanding,
    required this.monthlyIncome,
    required this.monthlyExpense,
    required this.cashFlow,
    required this.savingsRate,
    required this.totalBudget,
    required this.totalBudgetSpent,
    required this.budgetUsage,
    required this.portfolioValue,
    required this.portfolioCost,
    required this.portfolioGain,
    required this.topExpenseCategories,
    required this.monthlyTrend,
    required this.accountSpending,
    required this.insights,
  });

  final double netWorth;
  final double assets;
  final double creditCardOutstanding;
  final double monthlyIncome;
  final double monthlyExpense;
  final double cashFlow;
  final double savingsRate;
  final double totalBudget;
  final double totalBudgetSpent;
  final double budgetUsage;
  final double portfolioValue;
  final double portfolioCost;
  final double portfolioGain;
  final List<CategoryTotal> topExpenseCategories;
  final List<MonthlyTotal> monthlyTrend;
  final List<AccountTotal> accountSpending;
  final List<FinanceInsight> insights;
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.amount,
    this.parentId,
  });

  final String categoryId;
  final String name;
  final double amount;
  final String? parentId;
}

class MonthlyTotal {
  const MonthlyTotal({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });

  final int year;
  final int month;
  final double income;
  final double expense;

  String get label => '$month/${year.toString().substring(2)}';
  double get cashFlow => income - expense;
}

class AccountTotal {
  const AccountTotal({required this.accountId, required this.name, required this.amount});

  final String accountId;
  final String name;
  final double amount;
}

class FinanceInsight {
  const FinanceInsight({
    required this.title,
    required this.body,
    required this.severity,
  });

  final String title;
  final String body;
  final InsightSeverity severity;
}

enum InsightSeverity { info, warning, positive }

FinanceSummary buildFinanceSummary({
  required List<Map<String, dynamic>> accounts,
  required List<Map<String, dynamic>> categories,
  required List<Map<String, dynamic>> transactions,
  required List<Map<String, dynamic>> budgets,
  required List<Map<String, dynamic>> stocks,
  required List<Map<String, dynamic>> portfolioTransactions,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final currentMonth = DateTime(today.year, today.month);
  final previousMonth = DateTime(today.year, today.month - 1);
  final categoryById = {for (final row in categories) row['id'] as String: row};
  final accountById = {for (final row in accounts) row['id'] as String: row};

  final cashAssets = accounts.where((row) => !isCreditCardAccount(row)).fold<double>(
        0,
        (sum, row) => sum + asDouble(row['balance']),
      );
  final cardDebt = accounts.where(isCreditCardAccount).fold<double>(
        0,
        (sum, row) => sum + asDouble(row['balance']),
      );

  double monthIncome = 0;
  double monthExpense = 0;
  double previousExpense = 0;
  final categoryTotals = <String, double>{};
  final monthBuckets = <String, ({int year, int month, double income, double expense})>{};
  final accountSpending = <String, double>{};

  for (final row in transactions) {
    if ((row['transaction_status'] as String? ?? 'posted') != 'posted') continue;
    final amount = asDouble(row['amount']);
    final type = row['type'] as String? ?? 'expense';
    final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
    if (date == null) continue;

    final bucketKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final bucket = monthBuckets[bucketKey] ??
        (year: date.year, month: date.month, income: 0.0, expense: 0.0);
    monthBuckets[bucketKey] = (
      year: bucket.year,
      month: bucket.month,
      income: bucket.income + (type == 'income' ? amount : 0),
      expense: bucket.expense + (type == 'expense' ? amount : 0),
    );

    final rowMonth = DateTime(date.year, date.month);
    if (type == 'income' && rowMonth == currentMonth) monthIncome += amount;
    if (type == 'expense') {
      if (rowMonth == currentMonth) monthExpense += amount;
      if (rowMonth == previousMonth) previousExpense += amount;

      final rawCategoryId = row['category_id'] as String?;
      final category = categoryById[rawCategoryId];
      final parentId = category?['parent_id'] as String?;
      final categoryId = parentId ?? rawCategoryId ?? 'uncategorized';
      categoryTotals[categoryId] = (categoryTotals[categoryId] ?? 0) + amount;

      final accountId = row['account_id'] as String?;
      if (accountId != null) {
        accountSpending[accountId] = (accountSpending[accountId] ?? 0) + amount;
      }
    }
  }

  final currentBudgets = budgets
      .where((row) => row['month'] == today.month && row['year'] == today.year)
      .toList();
  final totalBudget = currentBudgets.fold<double>(
    0,
    (sum, row) => sum + asDouble(row['amount']),
  );
  final totalBudgetSpent = currentBudgets.fold<double>(
    0,
    (sum, row) => sum + asDouble(row['spent']),
  );

  final holdings = buildPortfolioHoldings(stocks, portfolioTransactions);
  final portfolioValue = holdings.fold<double>(0, (sum, row) => sum + row.marketValue);
  final portfolioCost = holdings.fold<double>(0, (sum, row) => sum + row.cost);
  final assets = cashAssets + portfolioValue;

  final topCategories = categoryTotals.entries.map((entry) {
    final category = categoryById[entry.key];
    return CategoryTotal(
      categoryId: entry.key,
      name: category?['name'] as String? ?? 'Uncategorized',
      amount: entry.value,
      parentId: category?['parent_id'] as String?,
    );
  }).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  final trend = monthBuckets.values
      .map(
        (row) => MonthlyTotal(
          year: row.year,
          month: row.month,
          income: row.income,
          expense: row.expense,
        ),
      )
      .toList()
    ..sort((a, b) {
      final yearCompare = a.year.compareTo(b.year);
      return yearCompare != 0 ? yearCompare : a.month.compareTo(b.month);
    });

  final accountRows = accountSpending.entries.map((entry) {
    final account = accountById[entry.key];
    return AccountTotal(
      accountId: entry.key,
      name: account?['name'] as String? ?? 'Account',
      amount: entry.value,
    );
  }).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  final savingsRate = monthIncome <= 0 ? 0.0 : (monthIncome - monthExpense) / monthIncome;
  final budgetUsage = totalBudget <= 0 ? 0.0 : totalBudgetSpent / totalBudget;

  final insights = _buildInsights(
    monthIncome: monthIncome,
    monthExpense: monthExpense,
    previousExpense: previousExpense,
    savingsRate: savingsRate,
    budgetUsage: budgetUsage,
    topCategories: topCategories,
    cardDebt: cardDebt,
  );

  return FinanceSummary(
    netWorth: assets - cardDebt,
    assets: assets,
    creditCardOutstanding: cardDebt,
    monthlyIncome: monthIncome,
    monthlyExpense: monthExpense,
    cashFlow: monthIncome - monthExpense,
    savingsRate: savingsRate,
    totalBudget: totalBudget,
    totalBudgetSpent: totalBudgetSpent,
    budgetUsage: budgetUsage,
    portfolioValue: portfolioValue,
    portfolioCost: portfolioCost,
    portfolioGain: portfolioValue - portfolioCost,
    topExpenseCategories: topCategories,
    monthlyTrend: trend,
    accountSpending: accountRows,
    insights: insights,
  );
}

List<PortfolioHolding> buildPortfolioHoldings(
  List<Map<String, dynamic>> stocks,
  List<Map<String, dynamic>> transactions,
) {
  final byId = <String, PortfolioHolding>{
    for (final stock in stocks)
      stock['id'] as String: PortfolioHolding(
        id: stock['id'] as String,
        symbol: stock['symbol'] as String? ?? 'S',
        name: stock['name'] as String? ?? 'Stock',
        currency: stock['currency'] as String? ?? 'BDT',
        lastPrice: asDouble(stock['last_price']),
      ),
  };

  for (final row in transactions) {
    final stockId = row['stock_id'] as String?;
    if (stockId == null) continue;
    final embeddedStock = _decodeMap(row['stock_json']);
    final holding = byId.putIfAbsent(
      stockId,
      () => PortfolioHolding(
        id: stockId,
        symbol: embeddedStock['symbol'] as String? ?? 'S',
        name: embeddedStock['name'] as String? ?? 'Stock',
        currency: embeddedStock['currency'] as String? ?? 'BDT',
        lastPrice: asDouble(embeddedStock['last_price'] ?? row['price']),
      ),
    );
    final quantity = asDouble(row['quantity']);
    final total = asDouble(row['total_amount']);
    final shareValue = quantity * asDouble(row['price']);
    switch (row['txn_type']) {
      case 'buy':
        holding.quantity += quantity;
        holding.cost += shareValue;
      case 'sell':
        if (holding.quantity <= 0) break;
        final soldQuantity = quantity.clamp(0, holding.quantity).toDouble();
        final removedCost = (holding.cost / holding.quantity) * soldQuantity;
        holding.realized += total - removedCost;
        holding.cost -= removedCost;
        holding.quantity -= soldQuantity;
    }
  }

  return byId.values.where((row) => row.quantity > 0).toList()
    ..sort((a, b) => b.marketValue.compareTo(a.marketValue));
}

Map<String, dynamic> _decodeMap(Object? value) {
  if (value is! String || value.isEmpty) return {};
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {
    return {};
  }
  return {};
}

class PortfolioHolding {
  PortfolioHolding({
    required this.id,
    required this.symbol,
    required this.name,
    required this.currency,
    required this.lastPrice,
  });

  final String id;
  final String symbol;
  final String name;
  final String currency;
  final double lastPrice;
  double quantity = 0;
  double cost = 0;
  double realized = 0;

  double get marketValue => quantity * lastPrice;
}

bool isCreditCardAccount(Map<String, dynamic> row) {
  final type = (row['type'] as String? ?? '').toLowerCase();
  return type == 'card' || type == 'credit_card';
}

List<FinanceInsight> _buildInsights({
  required double monthIncome,
  required double monthExpense,
  required double previousExpense,
  required double savingsRate,
  required double budgetUsage,
  required double cardDebt,
  required List<CategoryTotal> topCategories,
}) {
  final insights = <FinanceInsight>[];
  if (previousExpense > 0 && monthExpense > previousExpense * 1.1) {
    final change = ((monthExpense - previousExpense) / previousExpense * 100).round();
    insights.add(
      FinanceInsight(
        title: 'Spending increased',
        body: 'Expenses are up $change% from last month.',
        severity: InsightSeverity.warning,
      ),
    );
  }
  if (budgetUsage >= 0.8) {
    insights.add(
      FinanceInsight(
        title: 'Budget usage is high',
        body: "You used ${(budgetUsage * 100).round()}% of this month's budget.",
        severity: budgetUsage > 1 ? InsightSeverity.warning : InsightSeverity.info,
      ),
    );
  }
  if (savingsRate < 0.1 && monthIncome > 0) {
    insights.add(
      const FinanceInsight(
        title: 'Savings rate is low',
        body: 'Cash flow is tight this month.',
        severity: InsightSeverity.warning,
      ),
    );
  }
  if (cardDebt > 0) {
    insights.add(
      FinanceInsight(
        title: 'Credit card balance',
        body: 'Outstanding card balance is ${cardDebt.toStringAsFixed(0)} before the next payment.',
        severity: InsightSeverity.info,
      ),
    );
  }
  if (topCategories.isNotEmpty) {
    insights.add(
      FinanceInsight(
        title: 'Top expense category',
        body: '${topCategories.first.name} is your largest spending area.',
        severity: InsightSeverity.info,
      ),
    );
  }
  if (insights.isEmpty) {
    insights.add(
      const FinanceInsight(
        title: 'Finances are steady',
        body: 'No unusual spending or budget pressure found this month.',
        severity: InsightSeverity.positive,
      ),
    );
  }
  return insights.take(5).toList();
}
