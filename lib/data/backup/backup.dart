import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';

/// Identificativo del formato, scritto in ogni file di backup.
const kBackupFormat = 'financee-backup';

/// Identificativi accettati in lettura: anche quello dei backup creati
/// quando l'app si chiamava Financiee.
const _readableFormats = {kBackupFormat, 'financiee-backup'};

/// Versione del formato del file (non dello schema del database).
const kBackupFormatVersion = 1;

/// Impostazioni (chiavi delle preferenze) salvate insieme ai dati.
const kBackupSettingKeys = ['meal_voucher_value_cents', 'meal_voucher_last_load'];

/// Nome del file di backup: `financee-backup-2026-11-08.json`.
String backupFileName(DateTime d) =>
    'financee-backup-${d.year}-${_two(d.month)}-${_two(d.day)}.json';

String _two(int n) => n.toString().padLeft(2, '0');

/// Righe di una tabella: nomi delle colonne e valori così come sono salvati
/// nel database (le date sono secondi dal 1970).
class BackupTable {
  const BackupTable(this.columns, this.rows);

  final List<String> columns;
  final List<List<Object?>> rows;

  /// Valori della colonna [name] (vuoto se la colonna non c'è).
  Iterable<Object?> column(String name) {
    final i = columns.indexOf(name);
    return i < 0 ? const [] : rows.map((r) => r[i]);
  }
}

/// Contenuto di un file di backup: tutte le tabelle e alcune impostazioni.
class BackupFile {
  const BackupFile({
    required this.createdAt,
    required this.schemaVersion,
    required this.tables,
    this.settings = const {},
  });

  final DateTime createdAt;

  /// Versione dello schema del database da cui è stato creato.
  final int schemaVersion;
  final Map<String, BackupTable> tables;
  final Map<String, Object> settings;

  int count(String table) => tables[table]?.rows.length ?? 0;

  int get accounts => count('accounts');
  int get categories => count('categories');
  int get transactions => count('transactions');
  int get transfers => count('transfers');
  int get debts => count('debts');
  int get savingsGoals => count('savings_goals');

  /// Giorni del primo e dell'ultimo movimento o trasferimento.
  (DateTime, DateTime)? get dateRange {
    final dates = [
      for (final t in ['transactions', 'transfers'])
        ...?tables[t]?.column('date').whereType<int>(),
    ];
    if (dates.isEmpty) return null;
    dates.sort();
    DateTime toDate(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000);
    return (toDate(dates.first), toDate(dates.last));
  }

  /// `true` se le tabelle di [other] contengono esattamente gli stessi dati
  /// (stesse colonne e stesse righe, nello stesso ordine).
  bool hasSameData(BackupFile other) {
    if (tables.length != other.tables.length) return false;
    for (final MapEntry(:key, :value) in tables.entries) {
      final o = other.tables[key];
      if (o == null ||
          !_sameList(value.columns, o.columns) ||
          value.rows.length != o.rows.length) {
        return false;
      }
      for (final (i, row) in value.rows.indexed) {
        if (!_sameList(row, o.rows[i])) return false;
      }
    }
    return true;
  }

  static bool _sameList(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String encode() => jsonEncode({
    'format': kBackupFormat,
    'formatVersion': kBackupFormatVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toIso8601String(),
    'settings': settings,
    'tables': {
      for (final MapEntry(:key, :value) in tables.entries)
        key: {'columns': value.columns, 'rows': value.rows},
    },
  });

  /// Legge un file di backup. Lancia [FormatException] con un messaggio per
  /// l'utente se il file non è un backup valido o è di una versione più
  /// recente dell'app ([currentSchemaVersion]).
  static BackupFile parse(String text, {required int currentSchemaVersion}) {
    const notBackup = 'Il file non è un backup di Financee.';
    const damaged = 'Il backup è incompleto o danneggiato.';
    const newer =
        'Il backup è stato creato con una versione più recente di '
        'Financee: aggiorna l\'app per ripristinarlo.';

    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException(notBackup);
    }
    if (json is! Map<String, Object?> ||
        !_readableFormats.contains(json['format'])) {
      throw const FormatException(notBackup);
    }
    final formatVersion = json['formatVersion'];
    final schema = json['schemaVersion'];
    if (formatVersion is! int || schema is! int) {
      throw const FormatException(damaged);
    }
    if (formatVersion > kBackupFormatVersion || schema > currentSchemaVersion) {
      throw const FormatException(newer);
    }
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    final rawTables = json['tables'];
    if (createdAt == null || rawTables is! Map<String, Object?>) {
      throw const FormatException(damaged);
    }

    final tables = <String, BackupTable>{};
    for (final MapEntry(:key, :value) in rawTables.entries) {
      if (value is! Map<String, Object?>) throw const FormatException(damaged);
      final columns = value['columns'];
      final rows = value['rows'];
      if (columns is! List || rows is! List) {
        throw const FormatException(damaged);
      }
      final names = columns.whereType<String>().toList();
      if (names.length != columns.length || !names.contains('id')) {
        throw const FormatException(damaged);
      }
      final parsed = <List<Object?>>[];
      for (final row in rows) {
        if (row is! List || row.length != names.length) {
          throw const FormatException(damaged);
        }
        for (final v in row) {
          if (v != null && v is! int && v is! double && v is! String) {
            throw const FormatException(damaged);
          }
        }
        parsed.add(List<Object?>.unmodifiable(row));
      }
      tables[key] = BackupTable(List.unmodifiable(names), parsed);
    }
    if (!tables.containsKey('accounts') || !tables.containsKey('categories')) {
      throw const FormatException(damaged);
    }
    if (tables['accounts']!.rows.isEmpty) {
      throw const FormatException('Il backup non contiene nessun conto.');
    }

    final rawSettings = json['settings'];
    final settings = <String, Object>{
      if (rawSettings is Map<String, Object?>)
        for (final k in kBackupSettingKeys)
          if (rawSettings[k] case final Object v
              when v is int || v is String || v is bool)
            k: v,
    };

    return BackupFile(
      createdAt: createdAt,
      schemaVersion: schema,
      tables: tables,
      settings: settings,
    );
  }
}

/// Il ripristino è fallito perché il backup ha riferimenti non validi (es.
/// un movimento di un conto che non c'è). Nessun dato è stato modificato.
class BackupIntegrityException implements Exception {
  const BackupIntegrityException(this.violations);

  final int violations;

  @override
  String toString() =>
      'Il backup contiene $violations riferimenti non validi: nessun dato '
      'è stato modificato.';
}

extension BackupDatabase on AppDatabase {
  /// Tabelle del backup, nell'ordine in cui vanno reinserite (prima quelle
  /// a cui le altre fanno riferimento).
  List<TableInfo<Table, Object?>> get backupTables => [
    accounts,
    categories,
    debts,
    transactions,
    transfers,
    savingsGoals,
  ];

  /// Copia di tutti i dati, letta in un'unica transazione (un'istantanea
  /// coerente anche se nel frattempo si registra un movimento).
  Future<BackupFile> createBackup({
    Map<String, Object> settings = const {},
    DateTime? now,
  }) async {
    final tables = <String, BackupTable>{};
    await transaction(() async {
      for (final t in backupTables) {
        final columns = [for (final c in t.$columns) c.name];
        final rows = await customSelect(
          'SELECT ${columns.map((c) => '"$c"').join(', ')} '
          'FROM "${t.actualTableName}" ORDER BY "id"',
        ).get();
        tables[t.actualTableName] = BackupTable(columns, [
          for (final r in rows) [for (final c in columns) r.data[c]],
        ]);
      }
    });
    return BackupFile(
      createdAt: now ?? DateTime.now(),
      schemaVersion: schemaVersion,
      tables: tables,
      settings: settings,
    );
  }

  /// Sostituisce tutti i dati con quelli del backup, in un'unica
  /// transazione: se qualcosa va storto i dati attuali restano com'erano.
  /// Le colonne aggiunte dopo la creazione del backup prendono il valore
  /// predefinito.
  Future<void> restoreBackup(BackupFile backup) async {
    await transaction(() async {
      // I riferimenti tra tabelle si controllano alla fine, tutti insieme.
      await customStatement('PRAGMA defer_foreign_keys = ON');
      for (final t in backupTables.reversed) {
        await delete(t).go();
      }
      for (final t in backupTables) {
        final data = backup.tables[t.actualTableName];
        if (data == null || data.rows.isEmpty) continue;
        final known = {for (final c in t.$columns) c.name};
        final indexes = [
          for (final (i, c) in data.columns.indexed)
            if (known.contains(c)) i,
        ];
        final sql =
            'INSERT INTO "${t.actualTableName}" '
            '(${indexes.map((i) => '"${data.columns[i]}"').join(', ')}) '
            'VALUES (${List.filled(indexes.length, '?').join(', ')})';
        await batch((b) {
          for (final row in data.rows) {
            b.customStatement(sql, [for (final i in indexes) row[i]]);
          }
        });
      }
      final violations = await customSelect('PRAGMA foreign_key_check').get();
      if (violations.isNotEmpty) {
        throw BackupIntegrityException(violations.length);
      }
    });
    notifyUpdates({for (final t in backupTables) TableUpdate.onTable(t)});
  }
}

/// Copia tutti i dati di [from] in [to] (sostituendo quelli di [to]) e
/// controlla che la copia sia identica. Lancia un'eccezione se non
/// coincide. Non chiude i database.
Future<void> copyDatabase({
  required AppDatabase from,
  required AppDatabase to,
}) async {
  final data = await from.createBackup();
  await to.restoreBackup(data);
  final check = await to.createBackup();
  if (!data.hasSameData(check)) {
    throw StateError('La copia del database non coincide con l\'originale');
  }
}
