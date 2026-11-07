import 'package:drift/drift.dart';

import '../app_database.dart';
import 'csv_parser.dart';

// =============================================================================
// Lettura dell'export CSV di Sossoldi
// =============================================================================
//
// Sossoldi esporta tutte le tabelle in un unico CSV: la colonna `table_name`
// dice a quale tabella appartiene la riga (bankAccount, categoryTransaction,
// transaction, budget, currency, ...). Per i movimenti `type` vale IN, OUT o
// TRSF; nei trasferimenti `idBankAccount` è il conto di origine e
// `idBankAccountTransfer` quello di destinazione.

enum SossoldiMovementType { income, expense, transfer }

class SossoldiAccount {
  const SossoldiAccount({
    required this.id,
    required this.name,
    required this.symbol,
    required this.colorIndex,
    required this.startingCents,
    required this.active,
    required this.isMain,
    required this.position,
  });

  final int id;
  final String name;
  final String symbol;
  final int colorIndex;
  final int startingCents;
  final bool active;
  final bool isMain;
  final int position;
}

class SossoldiCategory {
  const SossoldiCategory({
    required this.id,
    required this.name,
    required this.type,
  });

  final int id;
  final String name;
  final TxType type;
}

class SossoldiMovement {
  const SossoldiMovement({
    required this.id,
    required this.type,
    required this.date,
    required this.createdAt,
    required this.amountCents,
    required this.note,
    required this.categoryId,
    required this.accountId,
    required this.toAccountId,
  });

  final int id;
  final SossoldiMovementType type;
  final DateTime date;
  final DateTime? createdAt;
  final int amountCents;
  final String note;
  final int? categoryId;
  final int accountId;

  /// Solo per i trasferimenti: conto di destinazione.
  final int? toAccountId;
}

class SossoldiExport {
  const SossoldiExport({
    required this.accounts,
    required this.categories,
    required this.movements,
  });

  /// Legge il CSV esportato da Sossoldi. Lancia [FormatException] con un
  /// messaggio comprensibile se il file non è un export valido.
  factory SossoldiExport.parse(String csv) {
    final rows = parseCsv(csv);
    if (rows.isEmpty) throw const FormatException('Il file è vuoto.');
    final header = rows.first.map((h) => h.trim()).toList();
    final col = {for (final (i, h) in header.indexed) h: i};
    for (final required in ['table_name', 'id', 'type', 'amount', 'idBankAccount']) {
      if (!col.containsKey(required)) {
        throw const FormatException(
          'Questo non sembra un export di Sossoldi: mancano le colonne attese.',
        );
      }
    }

    String get(List<String> row, String name) {
      final i = col[name];
      return i == null || i >= row.length ? '' : row[i].trim();
    }

    int? intOrNull(String s) => s.isEmpty ? null : int.tryParse(s);

    final accounts = <SossoldiAccount>[];
    final categories = <SossoldiCategory>[];
    final movements = <SossoldiMovement>[];

    for (final row in rows.skip(1)) {
      switch (get(row, 'table_name')) {
        case 'bankAccount':
          accounts.add(
            SossoldiAccount(
              id: int.parse(get(row, 'id')),
              name: get(row, 'name'),
              symbol: get(row, 'symbol'),
              colorIndex: intOrNull(get(row, 'color')) ?? 0,
              startingCents: _cents(get(row, 'startingValue')),
              active: get(row, 'active') != '0',
              isMain: get(row, 'mainAccount') == '1',
              position: intOrNull(get(row, 'position')) ?? accounts.length,
            ),
          );
        case 'categoryTransaction':
          categories.add(
            SossoldiCategory(
              id: int.parse(get(row, 'id')),
              name: get(row, 'name'),
              type: get(row, 'type') == 'IN' ? TxType.income : TxType.expense,
            ),
          );
        case 'transaction':
          if (get(row, 'deletedAt').isNotEmpty) continue;
          final type = switch (get(row, 'type')) {
            'IN' => SossoldiMovementType.income,
            'OUT' => SossoldiMovementType.expense,
            'TRSF' => SossoldiMovementType.transfer,
            final other => throw FormatException(
                'Tipo di movimento sconosciuto "$other" (riga ${get(row, 'id')}).',
              ),
          };
          final date = DateTime.parse(get(row, 'date'));
          final created = get(row, 'createdAt');
          movements.add(
            SossoldiMovement(
              id: int.parse(get(row, 'id')),
              type: type,
              date: DateTime(date.year, date.month, date.day),
              createdAt: created.isEmpty ? null : DateTime.tryParse(created),
              amountCents: _cents(get(row, 'amount')).abs(),
              note: get(row, 'note'),
              categoryId: type == SossoldiMovementType.transfer
                  ? null
                  : intOrNull(get(row, 'idCategory')),
              accountId: int.parse(get(row, 'idBankAccount')),
              toAccountId: intOrNull(get(row, 'idBankAccountTransfer')),
            ),
          );
      }
    }
    if (accounts.isEmpty) {
      throw const FormatException('Nel file non ci sono conti da importare.');
    }
    final accountIds = accounts.map((a) => a.id).toSet();
    for (final m in movements) {
      if (!accountIds.contains(m.accountId) ||
          (m.type == SossoldiMovementType.transfer &&
              !accountIds.contains(m.toAccountId))) {
        throw FormatException(
          'Il movimento ${m.id} fa riferimento a un conto inesistente.',
        );
      }
    }
    movements.sort((a, b) {
      final d = a.date.compareTo(b.date);
      if (d != 0) return d;
      return (a.createdAt ?? a.date).compareTo(b.createdAt ?? b.date);
    });
    return SossoldiExport(
      accounts: accounts..sort((a, b) => a.position.compareTo(b.position)),
      categories: categories,
      movements: movements,
    );
  }

  final List<SossoldiAccount> accounts;
  final List<SossoldiCategory> categories;

  /// In ordine cronologico.
  final List<SossoldiMovement> movements;

  /// Saldo finale di ogni conto calcolato come fa Sossoldi:
  /// saldo iniziale + entrate − uscite + trasferimenti in entrata − in uscita.
  Map<int, int> get balances {
    final result = {for (final a in accounts) a.id: a.startingCents};
    for (final m in movements) {
      switch (m.type) {
        case SossoldiMovementType.income:
          result[m.accountId] = result[m.accountId]! + m.amountCents;
        case SossoldiMovementType.expense:
          result[m.accountId] = result[m.accountId]! - m.amountCents;
        case SossoldiMovementType.transfer:
          result[m.accountId] = result[m.accountId]! - m.amountCents;
          result[m.toAccountId!] = result[m.toAccountId!]! + m.amountCents;
      }
    }
    return result;
  }
}

/// "880.9400000000004" -> 88094
int _cents(String value) {
  if (value.isEmpty) return 0;
  final v = double.tryParse(value);
  if (v == null) throw FormatException('Importo non valido: "$value"');
  return (v * 100).round();
}

// =============================================================================
// Mappatura verso Financiee
// =============================================================================

/// Categorie di Sossoldi (nome in minuscolo) -> categoria di Financiee.
/// Il tipo (entrata/uscita) resta quello della categoria di origine.
/// Le categorie non elencate vengono create con lo stesso nome.
const kSossoldiCategoryMap = <String, String>{
  // Uscite
  'auto': 'Auto',
  'car': 'Auto',
  'gasolio': 'Carburante',
  'benzina': 'Carburante',
  'fuel': 'Carburante',
  'dining': 'Ristoranti e bar',
  'dining out': 'Ristoranti e bar',
  'dining auto': 'Ristoranti e bar',
  'restaurants': 'Ristoranti e bar',
  'bar': 'Ristoranti e bar',
  'subscription': 'Abbonamenti',
  'subscriptions': 'Abbonamenti',
  'hobby': 'Hobby',
  'hobbies': 'Hobby',
  'healthcare': 'Salute',
  'health': 'Salute',
  'unkown': 'Altre spese',
  'unknown': 'Altre spese',
  'other': 'Altre spese',
  'university': 'Istruzione',
  'education': 'Istruzione',
  'know - how': 'Istruzione',
  'shopping': 'Shopping',
  'transportation': 'Trasporti',
  'transport': 'Trasporti',
  'dog': 'Cane',
  'pets': 'Animali',
  'parents': 'Famiglia',
  'family': 'Famiglia',
  'groceries': 'Spesa',
  'grocery': 'Spesa',
  'travel': 'Viaggi',
  'viaggi': 'Viaggi',
  'home': 'Casa',
  'house': 'Casa',
  'bills': 'Bollette',
  'utilities': 'Bollette',
  'entertainment': 'Svago',
  'gifts': 'Regali',
  // Entrate
  'salary': 'Stipendio',
  'refund': 'Rimborsi',
  'refunds': 'Rimborsi',
  'sales': 'Vendite',
  'conto deposito': 'Investimenti',
  'investments': 'Investimenti',
  'interest': 'Investimenti',
  'soldi da mese prima': 'Altre entrate',
  'cane': 'Cane',
};

/// Aspetto delle categorie che l'import può dover creare.
const _newCategoryStyle = <String, (String, int)>{
  'Auto': ('car', 0xFF0EA5E9),
  'Carburante': ('fuel', 0xFFF97316),
  'Hobby': ('game', 0xFFA855F7),
  'Cane': ('pets', 0xFFEAB308),
  'Animali': ('pets', 0xFFEAB308),
  'Famiglia': ('family', 0xFFEC4899),
  'Vendite': ('sell', 0xFF14B8A6),
  'Spesa': ('cart', 0xFF22C55E),
  'Ristoranti e bar': ('restaurant', 0xFFF97316),
  'Casa': ('home', 0xFF6366F1),
  'Bollette': ('bolt', 0xFFF59E0B),
  'Trasporti': ('train', 0xFF0EA5E9),
  'Salute': ('health', 0xFFEF4444),
  'Svago': ('movie', 0xFFA855F7),
  'Shopping': ('shopping', 0xFFEC4899),
  'Abbonamenti': ('subscriptions', 0xFF8B5CF6),
  'Viaggi': ('flight', 0xFF14B8A6),
  'Istruzione': ('school', 0xFF3B82F6),
  'Regali': ('gift', 0xFFD946EF),
  'Altre spese': ('other', 0xFF64748B),
  'Stipendio': ('work', 0xFF10B981),
  'Investimenti': ('trending', 0xFF84CC16),
  'Rimborsi': ('refund', 0xFF0EA5E9),
  'Altre entrate': ('payments', 0xFF64748B),
};

/// Conti di Sossoldi (nome in minuscolo) -> titolo in Financiee.
const kSossoldiAccountNames = <String, String>{
  'income': 'Conto principale',
  'main': 'Conto principale',
  'savings': 'Risparmi',
  'cash': 'Contanti',
  'contanti': 'Contanti',
};

String _targetCategoryName(SossoldiCategory? c, TxType type) {
  if (c == null) return type == TxType.income ? 'Altre entrate' : 'Altre spese';
  final key = c.name.trim().toLowerCase();
  return kSossoldiCategoryMap[key] ?? _capitalize(c.name.trim());
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// =============================================================================
// Piano di import (anteprima) e applicazione
// =============================================================================

class AccountImportPlan {
  const AccountImportPlan({
    required this.source,
    required this.targetName,
    required this.iconKey,
    required this.color,
    required this.expectedBalanceCents,
    required this.movementCount,
  });

  final SossoldiAccount source;
  final String targetName;
  final String iconKey;
  final int color;

  /// Saldo finale secondo Sossoldi: dopo l'import deve tornare uguale.
  final int expectedBalanceCents;
  final int movementCount;
}

class CategoryImportPlan {
  CategoryImportPlan({
    required this.sourceName,
    required this.type,
    required this.targetName,
    required this.exists,
  });

  /// `null` per i movimenti senza categoria.
  final String? sourceName;
  final TxType type;
  final String targetName;

  /// La categoria esiste già in Financiee (altrimenti verrà creata).
  final bool exists;
  int count = 0;
  int totalCents = 0;
}

class SossoldiImportPlan {
  const SossoldiImportPlan({
    required this.export,
    required this.accounts,
    required this.skippedAccounts,
    required this.categories,
    required this.replaceExisting,
  });

  /// Prepara l'import. I conti disattivati e senza movimenti vengono saltati.
  /// Se [replaceExisting] è falso e un titolo esiste già, si aggiunge
  /// " (Sossoldi)" così i saldi dei conti importati restano esatti.
  factory SossoldiImportPlan.build(
    SossoldiExport export, {
    required List<CategoryEntity> existingCategories,
    required List<AccountEntity> existingAccounts,
    required bool replaceExisting,
  }) {
    final balances = export.balances;
    final usage = <int, int>{};
    for (final m in export.movements) {
      usage[m.accountId] = (usage[m.accountId] ?? 0) + 1;
      if (m.toAccountId != null) {
        usage[m.toAccountId!] = (usage[m.toAccountId!] ?? 0) + 1;
      }
    }

    final takenNames = replaceExisting
        ? <String>{}
        : existingAccounts.map((a) => a.name.toLowerCase()).toSet();
    final accounts = <AccountImportPlan>[];
    final skipped = <SossoldiAccount>[];
    for (final a in export.accounts) {
      if (!a.active && (usage[a.id] ?? 0) == 0) {
        skipped.add(a);
        continue;
      }
      var name = kSossoldiAccountNames[a.name.trim().toLowerCase()] ??
          _capitalize(a.name.trim());
      if (takenNames.contains(name.toLowerCase())) name = '$name (Sossoldi)';
      takenNames.add(name.toLowerCase());
      final (icon, color) = a.isMain
          ? ('bank', 0xFF6366F1)
          : switch (a.symbol) {
              'savings' => ('savings', 0xFFF59E0B),
              'credit_card' => ('card', 0xFF0EA5E9),
              'payments' => ('cash', 0xFF22C55E),
              _ => ('wallet', 0xFF8B5CF6),
            };
      accounts.add(
        AccountImportPlan(
          source: a,
          targetName: name,
          iconKey: icon,
          color: color,
          expectedBalanceCents: balances[a.id]!,
          movementCount: usage[a.id] ?? 0,
        ),
      );
    }

    final byId = {for (final c in export.categories) c.id: c};
    final existing = {
      for (final c in existingCategories) (c.name.toLowerCase(), c.type),
    };
    final plans = <(int?, TxType), CategoryImportPlan>{};
    for (final m in export.movements) {
      if (m.type == SossoldiMovementType.transfer) continue;
      final type =
          m.type == SossoldiMovementType.income ? TxType.income : TxType.expense;
      final source = byId[m.categoryId];
      final target = _targetCategoryName(source, type);
      final plan = plans.putIfAbsent(
        (source?.id, type),
        () => CategoryImportPlan(
          sourceName: source?.name.trim(),
          type: type,
          targetName: target,
          exists: existing.contains((target.toLowerCase(), type)),
        ),
      );
      plan
        ..count += 1
        ..totalCents += m.amountCents;
    }
    final categories = plans.values.toList()
      ..sort((a, b) {
        final t = a.type.index.compareTo(b.type.index);
        return t != 0 ? t : b.totalCents.compareTo(a.totalCents);
      });

    return SossoldiImportPlan(
      export: export,
      accounts: accounts,
      skippedAccounts: skipped,
      categories: categories,
      replaceExisting: replaceExisting,
    );
  }

  final SossoldiExport export;
  final List<AccountImportPlan> accounts;
  final List<SossoldiAccount> skippedAccounts;
  final List<CategoryImportPlan> categories;
  final bool replaceExisting;

  int get transactionCount => export.movements
      .where((m) => m.type != SossoldiMovementType.transfer)
      .length;
  int get transferCount => export.movements
      .where((m) => m.type == SossoldiMovementType.transfer)
      .length;
  DateTime? get firstDate => export.movements.firstOrNull?.date;
  DateTime? get lastDate => export.movements.lastOrNull?.date;

  /// Nomi delle categorie che verranno create (senza duplicati).
  List<String> get newCategoryNames => {
        for (final c in categories)
          if (!c.exists) c.targetName,
      }.toList();
}

class AccountCheck {
  const AccountCheck(this.name, this.expectedCents, this.actualCents);

  final String name;
  final int expectedCents;
  final int actualCents;

  bool get ok => expectedCents == actualCents;
}

class SossoldiImportResult {
  const SossoldiImportResult({
    required this.transactions,
    required this.transfers,
    required this.createdCategories,
    required this.checks,
  });

  final int transactions;
  final int transfers;
  final int createdCategories;
  final List<AccountCheck> checks;

  bool get balancesMatch => checks.every((c) => c.ok);
}

extension SossoldiImport on AppDatabase {
  /// Esegue l'import in un'unica transazione (o tutto o niente) e verifica
  /// che i saldi finali coincidano con quelli di Sossoldi.
  Future<SossoldiImportResult> importSossoldi(SossoldiImportPlan plan) async {
    var createdCategories = 0;
    final accountIds = <int, int>{}; // id Sossoldi -> id Financiee

    await transaction(() async {
      if (plan.replaceExisting) {
        await deleteAllMovements();
        await delete(accounts).go();
      }

      for (final (i, a) in plan.accounts.indexed) {
        accountIds[a.source.id] = await into(accounts).insert(
          AccountsCompanion.insert(
            name: a.targetName,
            iconKey: a.iconKey,
            color: a.color,
            initialBalanceCents: Value(a.source.startingCents),
            sortOrder: Value(i),
          ),
        );
      }

      // Categorie: riusa quelle esistenti (stesso nome e tipo), crea le altre.
      final existing = await getCategories();
      final categoryIds = <(String, TxType), int>{
        for (final c in existing) (c.name.toLowerCase(), c.type): c.id,
      };
      for (final c in plan.categories) {
        final key = (c.targetName.toLowerCase(), c.type);
        if (categoryIds.containsKey(key)) continue;
        final (icon, color) =
            _newCategoryStyle[c.targetName] ?? ('other', 0xFF64748B);
        categoryIds[key] = await createCategory(
          name: c.targetName,
          type: c.type,
          iconKey: icon,
          color: color,
        );
        createdCategories++;
      }

      final byId = {for (final c in plan.export.categories) c.id: c};
      final txRows = <TransactionsCompanion>[];
      final transferRows = <TransfersCompanion>[];
      for (final m in plan.export.movements) {
        final created = Value.absentIfNull(m.createdAt);
        if (m.type == SossoldiMovementType.transfer) {
          transferRows.add(
            TransfersCompanion.insert(
              fromAccountId: accountIds[m.accountId]!,
              toAccountId: accountIds[m.toAccountId]!,
              amountCents: m.amountCents,
              date: m.date,
              note: Value(m.note),
              createdAt: created,
            ),
          );
          continue;
        }
        final type =
            m.type == SossoldiMovementType.income ? TxType.income : TxType.expense;
        final target = _targetCategoryName(byId[m.categoryId], type);
        txRows.add(
          TransactionsCompanion.insert(
            type: type,
            amountCents: m.amountCents,
            categoryId: categoryIds[(target.toLowerCase(), type)]!,
            accountId: accountIds[m.accountId]!,
            date: m.date,
            note: Value(m.note),
            createdAt: created,
          ),
        );
      }
      await batch((b) {
        b.insertAll(transactions, txRows);
        b.insertAll(transfers, transferRows);
      });
    });

    final balances = await watchAccountBalances().first;
    return SossoldiImportResult(
      transactions: plan.transactionCount,
      transfers: plan.transferCount,
      createdCategories: createdCategories,
      checks: [
        for (final a in plan.accounts)
          AccountCheck(
            a.targetName,
            a.expectedBalanceCents,
            balances[accountIds[a.source.id]] ?? 0,
          ),
      ],
    );
  }
}
