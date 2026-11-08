import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/backup/backup.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import 'backup_widgets.dart';

/// Ripristina tutti i dati da un file di backup, con anteprima del contenuto.
class RestoreBackupScreen extends ConsumerStatefulWidget {
  const RestoreBackupScreen({super.key});

  @override
  ConsumerState<RestoreBackupScreen> createState() =>
      _RestoreBackupScreenState();
}

class _RestoreBackupScreenState extends ConsumerState<RestoreBackupScreen> {
  String? _fileName;
  BackupFile? _backup;
  String? _error;
  bool _busy = false;
  bool _saveCurrentFirst = true;
  bool _done = false;

  static const _jsonTypes = XTypeGroup(
    label: 'Backup di Financee',
    extensions: ['json'],
    mimeTypes: ['application/json', 'text/plain', 'application/octet-stream'],
    uniformTypeIdentifiers: ['public.json'],
  );

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final file = await openFile(acceptedTypeGroups: const [_jsonTypes]);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final backup = BackupFile.parse(
        text,
        currentSchemaVersion: ref.read(databaseProvider).schemaVersion,
      );
      setState(() {
        _fileName = file.name;
        _backup = backup;
      });
    } on FormatException catch (e) {
      setState(() {
        _backup = null;
        _error = e.message;
      });
    } catch (e) {
      setState(() => _error = 'Impossibile leggere il file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupFile backup) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sostituire tutti i dati?'),
        content: Text(
          'Conti, movimenti, trasferimenti, categorie, debiti e obiettivi '
          'attuali verranno sostituiti da quelli del backup del '
          '${formatDate(backup.createdAt)}.'
          '${_saveCurrentFirst ? ' Prima verrà scaricato un backup dei dati attuali.' : ' I dati attuali non si potranno recuperare.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sostituisci i dati'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_saveCurrentFirst && !await exportBackup(context, ref)) {
        setState(
          () => _error = 'Il backup dei dati attuali non è stato salvato: '
              'ripristino annullato, nessun dato è stato modificato.',
        );
        return;
      }
      await ref.read(databaseProvider).restoreBackup(backup);
      final prefs = ref.read(sharedPreferencesProvider);
      for (final MapEntry(:key, :value) in backup.settings.entries) {
        switch (value) {
          case final int v:
            await prefs.setInt(key, v);
          case final String v:
            await prefs.setString(key, v);
          case final bool v:
            await prefs.setBool(key, v);
        }
      }
      ref.invalidate(mealVoucherValueProvider);
      ref.read(lastBackupProvider.notifier).set(backup.createdAt);
      ref.read(accountFilterProvider.notifier).set(null);
      setState(() => _done = true);
    } on BackupIntegrityException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(
        () => _error = 'Ripristino non riuscito, nessun dato è stato '
            'modificato: $e',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backup = _backup;
    return Scaffold(
      appBar: AppBar(title: const Text('Ripristina da un backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          PageContainer(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_done && backup != null)
                  _DoneCard(backup: backup)
                else if (backup == null)
                  AppCard(
                    child: EmptyState(
                      icon: Icons.settings_backup_restore_rounded,
                      title: 'Scegli un backup',
                      message:
                          'Seleziona un file financee-backup-….json creato '
                          'con "Esporta backup". Prima di sostituire i dati '
                          'vedrai cosa contiene.',
                      actions: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _pickFile,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.folder_open_rounded),
                          label: const Text('Scegli il file'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _PreviewCard(
                    fileName: _fileName!,
                    backup: backup,
                    onChange: _busy ? null : _pickFile,
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    color: AppColors.expense.withValues(alpha: 0.06),
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: AppColors.expense,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Tutti i dati attuali verranno sostituiti '
                                  'da quelli del backup: non si aggiungono, '
                                  'li rimpiazzano.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          value: _saveCurrentFirst,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _saveCurrentFirst = v),
                          title: const Text(
                            'Prima scarica un backup dei dati attuali',
                          ),
                          subtitle: const Text(
                            'Così puoi tornare indietro se hai scelto il file '
                            'sbagliato',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: 'Ripristina il backup',
                    icon: Icons.settings_backup_restore_rounded,
                    loading: _busy,
                    onPressed: () => _restore(backup),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.expense,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Cosa contiene il backup, confrontato con i dati attuali.
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({
    required this.fileName,
    required this.backup,
    required this.onChange,
  });

  final String fileName;
  final BackupFile backup;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final range = backup.dateRange;
    final currentMovements =
        ref.watch(transactionCountProvider).asData?.value ?? 0;
    final currentAccounts = ref.watch(accountsProvider).asData?.value.length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: fileName,
            subtitle:
                'Creato il ${formatDate(backup.createdAt)} alle '
                '${_time(backup.createdAt)}',
            trailing: TextButton(
              onPressed: onChange,
              child: const Text('Cambia'),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(plural(backup.accounts, 'conto', 'conti')),
              _Pill(plural(backup.transactions, 'movimento', 'movimenti')),
              _Pill(
                plural(backup.transfers, 'trasferimento', 'trasferimenti'),
              ),
              _Pill(plural(backup.categories, 'categoria', 'categorie')),
              if (backup.debts > 0)
                _Pill(plural(backup.debts, 'debito', 'debiti')),
              if (backup.savingsGoals > 0)
                _Pill(plural(backup.savingsGoals, 'obiettivo', 'obiettivi')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            range == null
                ? 'Nessun movimento nel backup.'
                : 'Movimenti dal ${formatDate(range.$1)} al '
                      '${formatDate(range.$2)}.',
            style: theme.textTheme.bodyMedium,
          ),
          if (currentAccounts != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ora nell\'app: ${plural(currentAccounts, 'conto', 'conti')} e '
                '${plural(currentMovements, 'movimento', 'movimenti')}.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.backup});

  final BackupFile backup;

  @override
  Widget build(BuildContext context) => AppCard(
    child: EmptyState(
      icon: Icons.verified_rounded,
      title: 'Backup ripristinato',
      message:
          'Ora l\'app contiene i dati del ${formatDate(backup.createdAt)}: '
          '${plural(backup.accounts, 'conto', 'conti')}, '
          '${plural(backup.transactions, 'movimento', 'movimenti')} e '
          '${plural(backup.transfers, 'trasferimento', 'trasferimenti')}.',
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fine'),
        ),
      ],
    ),
  );
}
