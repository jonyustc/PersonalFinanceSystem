import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'personal_finance.db');
    _db = await openDatabase(
      path,
      version: 9,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return _db!;
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        opening_balance REAL NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'BDT',
        current_outstanding REAL NOT NULL DEFAULT 0,
        credit_limit REAL,
        display_balance REAL NOT NULL DEFAULT 0,
        account_subtype TEXT,
        color TEXT,
        icon TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        archived INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        parent_id TEXT,
        color TEXT,
        icon TEXT,
        is_pending INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        category_id TEXT,
        transfer_account_id TEXT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        txn_date TEXT NOT NULL,
        description TEXT,
        merchant_name TEXT,
        payment_method TEXT,
        tags_json TEXT NOT NULL DEFAULT '[]',
        transaction_status TEXT NOT NULL DEFAULT 'posted',
        is_pending INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        method TEXT NOT NULL,
        path TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _createPortfolioTables(db);
    await _createBudgetTables(db);
    await _createRecurringTable(db);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createPortfolioTables(db);
      await _createBudgetTables(db);
    }
    if (oldVersion < 3) {
      await db.execute(
        "UPDATE accounts SET currency = 'BDT' WHERE currency = 'USD'",
      );
    }
    if (oldVersion < 4) {
      await _addColumnSafely(
        db,
        'accounts',
        'current_outstanding',
        'REAL NOT NULL DEFAULT 0',
      );
      await _addColumnSafely(db, 'accounts', 'credit_limit', 'REAL');
      await _addColumnSafely(
        db,
        'accounts',
        'display_balance',
        'REAL NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 5) {
      await _addColumnSafely(
        db,
        'portfolio_transactions',
        'record_date',
        'TEXT',
      );
    }
    if (oldVersion < 6) {
      await _addColumnSafely(db, 'accounts', 'account_subtype', 'TEXT');
    }
    if (oldVersion < 7) {
      await _addColumnSafely(
        db,
        'categories',
        'is_pending',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 8) {
      await _createRecurringTable(db);
    }
    if (oldVersion < 9) {
      await _addColumnSafely(db, 'portfolio_transactions', 'portfolio_id', 'TEXT');
    }
  }

  Future<void> _createRecurringTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_rules (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        account_id TEXT NOT NULL,
        transfer_account_id TEXT,
        category_id TEXT,
        amount REAL NOT NULL DEFAULT 0,
        merchant_name TEXT,
        description TEXT,
        frequency TEXT NOT NULL,
        interval_count INTEGER NOT NULL DEFAULT 1,
        next_run TEXT NOT NULL,
        end_date TEXT,
        last_run TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createBudgetTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL,
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        spent REAL NOT NULL DEFAULT 0,
        remaining REAL NOT NULL DEFAULT 0,
        overspending INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createPortfolioTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stocks (
        id TEXT PRIMARY KEY,
        symbol TEXT NOT NULL,
        name TEXT NOT NULL,
        exchange TEXT,
        currency TEXT NOT NULL DEFAULT 'BDT',
        last_price REAL NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS portfolio_transactions (
        id TEXT PRIMARY KEY,
        stock_id TEXT,
        portfolio_id TEXT,
        broker_account_id TEXT,
        txn_type TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        price REAL NOT NULL DEFAULT 0,
        fees REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        cash_flow REAL NOT NULL DEFAULT 0,
        txn_date TEXT NOT NULL,
        record_date TEXT,
        notes TEXT,
        stock_json TEXT,
        raw_json TEXT NOT NULL
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> accounts() async {
    final db = await database;
    return db.query(
      'accounts',
      where: 'is_active = 1 AND archived = 0',
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, dynamic>>> categories() async {
    final db = await database;
    return db.query('categories', orderBy: 'type, name COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> transactions() async {
    final db = await database;
    return db.query('transactions', orderBy: 'txn_date DESC', limit: 250);
  }

  Future<List<Map<String, dynamic>>> budgets() async {
    final db = await database;
    return db.query('budgets', orderBy: 'year DESC, month DESC');
  }

  Future<List<Map<String, dynamic>>> stocks() async {
    final db = await database;
    return db.query('stocks', orderBy: 'name COLLATE NOCASE');
  }

  Future<List<Map<String, dynamic>>> portfolioTransactions() async {
    final db = await database;
    return db.query(
      'portfolio_transactions',
      orderBy: 'txn_date DESC',
      limit: 250,
    );
  }

  /// Wipes all locally cached data and the pending-write queue. Used on logout
  /// so a different account never inherits the previous user's rows or a stuck
  /// sync queue.
  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in const [
        'accounts',
        'categories',
        'transactions',
        'budgets',
        'stocks',
        'portfolio_transactions',
        'sync_queue',
        'meta',
      ]) {
        await txn.delete(table);
      }
    });
  }

  /// Data tables included in a backup (the pending-write queue is intentionally
  /// excluded — a backup captures data, not in-flight sync operations).
  static const _backupTables = [
    'accounts',
    'categories',
    'transactions',
    'budgets',
    'stocks',
    'portfolio_transactions',
    'recurring_rules',
    'meta',
  ];

  /// Serializes all local data into a plain map suitable for JSON export.
  Future<Map<String, dynamic>> exportData() async {
    final db = await database;
    final tables = <String, dynamic>{};
    for (final table in _backupTables) {
      tables[table] = await db.query(table);
    }
    return {
      'format': 'personal_finance_backup',
      'schema_version': 7,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': tables,
    };
  }

  /// Replaces all local data with the contents of a previously exported backup.
  /// Throws [FormatException] if the document is not a recognized backup.
  Future<void> importData(Map<String, dynamic> data) async {
    if (data['format'] != 'personal_finance_backup') {
      throw const FormatException('Not a Personal Finance backup file');
    }
    final tables = (data['tables'] as Map?)?.cast<String, dynamic>() ?? {};
    final db = await database;
    await db.transaction((txn) async {
      for (final table in _backupTables) {
        await txn.delete(table);
        final rows = (tables[table] as List? ?? []).whereType<Map>();
        for (final row in rows) {
          await txn.insert(
            table,
            row.cast<String, Object?>(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> recurringRules() async {
    final db = await database;
    return db.query('recurring_rules', orderBy: 'next_run ASC');
  }

  Future<void> upsertRecurringRule(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'recurring_rules',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteRecurringRule(String id) async {
    final db = await database;
    await db.delete('recurring_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> pendingCount() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM sync_queue');
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<String?> lastSyncAt() async {
    final db = await database;
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['last_sync_at'],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> markSynced() async {
    final db = await database;
    await db.insert('meta', {
      'key': 'last_sync_at',
      'value': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> portfolioSummary() async {
    final db = await database;
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['portfolio_summary'],
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['value'] as String);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }

  Future<void> savePortfolioSummary(Map<String, dynamic> summary) async {
    final db = await database;
    await db.insert('meta', {
      'key': 'portfolio_summary',
      'value': jsonEncode(summary),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> portfolios() async {
    final decoded = await metaJsonList('portfolios');
    return decoded;
  }

  Future<void> savePortfolios(List<Map<String, dynamic>> rows) async {
    await saveMetaJson('portfolios', rows);
  }

  /// Reads a JSON value cached in the meta table. Returns a map, or null.
  Future<Map<String, dynamic>?> metaJson(String key) async {
    final db = await database;
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['value'] as String);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }

  Future<List<Map<String, dynamic>>> metaJsonList(String key) async {
    final db = await database;
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return const [];
    final decoded = jsonDecode(rows.first['value'] as String);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  Future<void> saveMetaJson(String key, Object value) async {
    final db = await database;
    await db.insert('meta', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> dashboardSummary() async {
    final db = await database;
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['dashboard_summary'],
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['value'] as String);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }

  Future<void> saveDashboardSummary(Map<String, dynamic> summary) async {
    final db = await database;
    await db.insert('meta', {
      'key': 'dashboard_summary',
      'value': jsonEncode(summary),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> replaceAccounts(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('accounts');
      for (final row in rows) {
        await txn.insert(
          'accounts',
          _accountRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> replaceCategories(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      final pendingRows = await txn.query(
        'categories',
        where: 'is_pending = 1',
      );
      final syncedIds = rows.map((row) => row['id']?.toString()).toSet();
      await txn.delete('categories');
      for (final row in rows) {
        await txn.insert(
          'categories',
          _categoryRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in pendingRows) {
        final localId = row['id']?.toString();
        if (localId != null && syncedIds.contains(localId)) continue;
        await txn.insert(
          'categories',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> replaceTransactions(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      final pendingRows = await txn.query(
        'transactions',
        where: 'is_pending = 1',
      );
      final syncedReferences = rows
          .map((row) => row['reference_number']?.toString())
          .whereType<String>()
          .toSet();
      await txn.delete('transactions');
      for (final row in rows) {
        await txn.insert(
          'transactions',
          _transactionRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final row in pendingRows) {
        final localId = row['id']?.toString();
        final rawReference = _rawReferenceNumber(row);
        if (syncedReferences.contains(localId) ||
            (rawReference != null && syncedReferences.contains(rawReference))) {
          continue;
        }
        await txn.insert(
          'transactions',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  String? _rawReferenceNumber(Map<String, dynamic> row) {
    final raw = row['raw_json'];
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded['reference_number']?.toString();
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> replaceBudgets(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('budgets');
      for (final row in rows) {
        await txn.insert(
          'budgets',
          _budgetRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deleteTransaction(String id) async {
    final db = await database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceStocks(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('stocks');
      for (final row in rows) {
        await txn.insert(
          'stocks',
          _stockRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> replacePortfolioTransactions(
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('portfolio_transactions');
      for (final row in rows) {
        await txn.insert(
          'portfolio_transactions',
          _portfolioTransactionRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> upsertTransaction(
    Map<String, dynamic> row, {
    bool pending = false,
  }) async {
    final db = await database;
    await db.insert(
      'transactions',
      _transactionRow(row, pending: pending),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertCategory(
    Map<String, dynamic> row, {
    bool pending = false,
  }) async {
    final db = await database;
    await db.insert(
      'categories',
      _categoryRow(row, pending: pending),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertPortfolioTransaction(
    Map<String, dynamic> row, {
    bool pending = false,
  }) async {
    final db = await database;
    final normalized = {...row};
    if (pending) normalized['pending'] = true;
    await db.insert(
      'portfolio_transactions',
      _portfolioTransactionRow(normalized),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePortfolioTransaction(String id) async {
    final db = await database;
    await db.delete('portfolio_transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertStock(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'stocks',
      _stockRow(row),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertBudget(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'budgets',
      _budgetRow(row),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> queuePost(String path, Map<String, dynamic> payload) async {
    await queueMutation('POST', path, payload);
  }

  Future<void> queueMutation(
    String method,
    String path,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    await db.insert('sync_queue', {
      'method': method,
      'path': path,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> queuedMutations() async {
    final db = await database;
    return db.query('sync_queue', orderBy: 'id ASC');
  }

  Future<void> deleteQueuedMutation(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Map<String, Object?> _accountRow(Map<String, dynamic> row) {
    final type = (row['type'] ?? 'cash').toString().toLowerCase();
    final isCreditCard = type == 'card' || type == 'credit_card';
    final displayBalance =
        row['display_balance'] ??
        (isCreditCard ? row['current_outstanding'] : row['balance']);
    return {
      'id': row['id'].toString(),
      'name': row['name'] ?? 'Account',
      'type': type,
      'balance': _num(displayBalance),
      'opening_balance': _num(row['opening_balance']),
      'currency': row['currency'] ?? 'BDT',
      'current_outstanding': _num(row['current_outstanding']),
      'credit_limit': row['credit_limit'] == null
          ? null
          : _num(row['credit_limit']),
      'display_balance': _num(displayBalance),
      'account_subtype': row['account_subtype'],
      'color': row['color'],
      'icon': row['icon'],
      'is_active': row['is_active'] == false ? 0 : 1,
      'archived': row['archived'] == true ? 1 : 0,
      'raw_json': jsonEncode(row),
    };
  }

  Map<String, Object?> _categoryRow(
    Map<String, dynamic> row, {
    bool pending = false,
  }) {
    return {
      'id': row['id'].toString(),
      'name': row['name'] ?? 'Category',
      'type': row['type'] ?? 'expense',
      'parent_id': row['parent_id']?.toString(),
      'color': row['color'],
      'icon': row['icon'],
      'is_pending': pending ? 1 : 0,
      'raw_json': jsonEncode(row),
    };
  }

  Map<String, Object?> _transactionRow(
    Map<String, dynamic> row, {
    bool pending = false,
  }) {
    final tags = row['tags'] is List ? row['tags'] as List : const [];
    return {
      'id': row['id'].toString(),
      'account_id': row['account_id'].toString(),
      'category_id': row['category_id']?.toString(),
      'transfer_account_id': row['transfer_account_id']?.toString(),
      'type': row['type'] ?? 'expense',
      'amount': _num(row['amount']),
      'txn_date': (row['txn_date'] ?? DateTime.now().toIso8601String())
          .toString(),
      'description': row['description'],
      'merchant_name': row['merchant_name'],
      'payment_method': row['payment_method'],
      'tags_json': jsonEncode(tags),
      'transaction_status': row['transaction_status'] ?? 'posted',
      'is_pending': pending ? 1 : 0,
      'raw_json': jsonEncode(row),
    };
  }

  Map<String, Object?> _budgetRow(Map<String, dynamic> row) {
    final monthValue = row['month'];
    final categoryId = row['category_id'].toString();
    return {
      'id': (row['id'] ?? '$monthValue-$categoryId').toString(),
      'category_id': categoryId,
      'month': _budgetMonth(monthValue),
      'year': _budgetYear(monthValue, row['year']),
      'amount': _num(row['amount'] ?? row['budget']),
      'spent': _num(row['spent']),
      'remaining': _num(row['remaining']),
      'overspending': row['overspending'] == true ? 1 : 0,
      'raw_json': jsonEncode(row),
    };
  }

  Map<String, Object?> _stockRow(Map<String, dynamic> row) {
    return {
      'id': row['id'].toString(),
      'symbol': row['symbol'] ?? row['name'] ?? 'STOCK',
      'name': row['name'] ?? row['symbol'] ?? 'Stock',
      'exchange': row['exchange'],
      'currency': row['currency'] ?? 'BDT',
      'last_price': _num(row['last_price']),
      'raw_json': jsonEncode(row),
    };
  }

  Map<String, Object?> _portfolioTransactionRow(Map<String, dynamic> row) {
    return {
      'id': row['id'].toString(),
      'stock_id': row['stock_id']?.toString(),
      'portfolio_id': row['portfolio_id']?.toString(),
      'broker_account_id': row['broker_account_id']?.toString(),
      'txn_type': row['txn_type'] ?? 'buy',
      'quantity': _num(row['quantity']),
      'price': _num(row['price']),
      'fees': _num(row['fees']),
      'total_amount': _num(row['total_amount']),
      'cash_flow': _num(row['cash_flow']),
      'txn_date': (row['txn_date'] ?? DateTime.now().toIso8601String())
          .toString(),
      'record_date': row['record_date']?.toString(),
      'notes': row['notes'],
      'stock_json': row['stock'] == null ? null : jsonEncode(row['stock']),
      'raw_json': jsonEncode(row),
    };
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _addColumnSafely(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  int _budgetMonth(Object? value) {
    if (value is num) return value.toInt();
    if (value is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) {
      return int.tryParse(value.substring(5, 7)) ?? DateTime.now().month;
    }
    return DateTime.now().month;
  }

  int _budgetYear(Object? month, Object? year) {
    if (year is num) return year.toInt();
    if (year is String) return int.tryParse(year) ?? DateTime.now().year;
    if (month is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(month)) {
      return int.tryParse(month.substring(0, 4)) ?? DateTime.now().year;
    }
    return DateTime.now().year;
  }
}
