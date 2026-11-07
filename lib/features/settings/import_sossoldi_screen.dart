import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../data/import/sossoldi_import.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Importa conti, categorie, movimenti e trasferimenti da un export CSV di
/// Sossoldi, con anteprima della mappatura e verifica finale dei saldi.
class ImportSossoldiScreen extends ConsumerStatefulWidget {
  const ImportSossoldiScreen({super.key});

  @override
  ConsumerState<ImportSossoldiScreen> createState() =>
      _ImportSossoldiScreenState();
}

class _ImportSossoldiScreenState extends ConsumerState<ImportSossoldiScreen> {
  String? _fileName;
  SossoldiExport? _export;
  String? _error;
  bool _replace = false;
  bool _busy = false;
  SossoldiImportResult? _result;

  static const _csvTypes = XTypeGroup(
    label: 'CSV',
    extensions: ['csv'],
    mimeTypes: [
      'text/csv',
      'text/comma-separated-values',
      'text/plain',
      'application/csv',
      'application/vnd.ms-excel',
      'application/octet-stream',
    ],
    uniformTypeIdentifiers: ['public.comma-separated-values-text'],
  );

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final file = await openFile(acceptedTypeGroups: const [_csvTypes]);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final export = SossoldiExport.parse(text);
      setState(() {
        _fileName = file.name;
        _export = export;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Impossibile leggere il file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(SossoldiImportPlan plan) async {
    if (plan.replaceExisting) {
      final accounts = ref.read(accountsProvider).asData?.value ?? const [];
      final usage = ref.read(accountUsageProvider).asData?.value ?? const {};
      final hasMovements = usage.values.any((n) => n > 0);
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sostituire i dati attuali?'),
          content: Text(
            'Verranno eliminati definitivamente '
            '${accounts.length == 1 ? 'il conto "${accounts.single.name}"' : 'i ${accounts.length} conti attuali'}'
            '${hasMovements ? ' con tutti i loro movimenti e trasferimenti' : ' (non ci sono movimenti)'}. '
            'Le categorie restano.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sostituisci e importa'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(databaseProvider).importSossoldi(plan);
      ref.read(accountFilterProvider.notifier).set(null);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = 'Import non riuscito, nessun dato è stato modificato: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final export = _export;
    final categories = ref.watch(categoriesProvider).asData?.value;
    final accounts = ref.watch(accountsProvider).asData?.value;
    final plan = export == null || categories == null || accounts == null
        ? null
        : SossoldiImportPlan.build(
            export,
            existingCategories: categories,
            existingAccounts: accounts,
            replaceExisting: _replace,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Importa da Sossoldi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          PageContainer(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_result != null)
                  _ResultCard(result: _result!)
                else if (plan == null)
                  _IntroCard(busy: _busy, onPick: _pickFile)
                else ...[
                  _SummaryCard(fileName: _fileName!, plan: plan, onChange: _pickFile),
                  const SizedBox(height: 16),
                  _AccountsCard(plan: plan),
                  const SizedBox(height: 16),
                  _CategoriesCard(plan: plan),
                  const SizedBox(height: 16),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SwitchListTile(
                      value: _replace,
                      onChanged: _busy ? null : (v) => setState(() => _replace = v),
                      title: const Text('Sostituisci i dati attuali'),
                      subtitle: Text(
                        _replace
                            ? 'Conti, movimenti e trasferimenti presenti (es. i dati di esempio) verranno eliminati. Le categorie restano.'
                            : 'I conti importati si aggiungono a quelli già presenti.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    label:
                        'Importa ${plural(plan.transactionCount + plan.transferCount, 'voce', 'voci')}',
                    icon: Icons.download_done_rounded,
                    loading: _busy,
                    onPressed: () => _import(plan),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.expense),
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

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.busy, required this.onPick});

  final bool busy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => AppCard(
        child: EmptyState(
          icon: Icons.upload_file_rounded,
          title: 'Porta qui i tuoi dati',
          message: 'In Sossoldi vai su Impostazioni → Esporta dati e crea il '
              'file CSV, poi selezionalo qui. Prima di importare vedrai come '
              'verranno trasformati conti e categorie.',
          actions: [
            FilledButton.icon(
              onPressed: busy ? null : onPick,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_rounded),
              label: const Text('Scegli il file CSV'),
            ),
          ],
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.fileName,
    required this.plan,
    required this.onChange,
  });

  final String fileName;
  final SossoldiImportPlan plan;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = plan.firstDate;
    final to = plan.lastDate;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: fileName,
            subtitle: from == null
                ? 'Nessun movimento'
                : 'Dal ${formatDate(from)} al ${formatDate(to!)}',
            trailing: TextButton(onPressed: onChange, child: const Text('Cambia')),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(plural(plan.accounts.length, 'conto', 'conti')),
              _Pill(plural(plan.transactionCount, 'movimento', 'movimenti')),
              _Pill(plural(plan.transferCount, 'trasferimento', 'trasferimenti')),
              if (plan.newCategoryNames.isNotEmpty)
                _Pill(plural(plan.newCategoryNames.length, 'categoria nuova',
                    'categorie nuove')),
            ],
          ),
          if (plan.skippedAccounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Non importati (disattivati e senza movimenti): '
                '${plan.skippedAccounts.map((a) => a.name).join(', ')}.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

class _AccountsCard extends StatelessWidget {
  const _AccountsCard({required this.plan});

  final SossoldiImportPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Conti',
            subtitle: 'Saldo finale come in Sossoldi: dopo l\'import deve tornare uguale',
          ),
          const SizedBox(height: 8),
          for (final a in plan.accounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a.source.name} → ${a.targetName}',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Saldo iniziale ${formatMoney(a.source.startingCents)} · '
                          '${plural(a.movementCount, 'movimento', 'movimenti')}',
                          style: theme.textTheme.labelSmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(a.expectedBalanceCents),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.plan});

  final SossoldiImportPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget section(TxType type) {
      final items = plan.categories.where((c) => c.type == type).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              type == TxType.income ? 'Entrate' : 'Uscite',
              style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.forIncome(type == TxType.income),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final c in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: c.sourceName ?? '(senza categoria)',
                            style: TextStyle(color: muted),
                          ),
                          const TextSpan(text: '  →  '),
                          TextSpan(
                            text: c.targetName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (!c.exists)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.income.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'nuova',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.income,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatMoney(c.totalCents),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        plural(c.count, 'mov.', 'mov.'),
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Categorie',
            subtitle: 'Come verranno raggruppate in Financiee',
          ),
          section(TxType.expense),
          section(TxType.income),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final SossoldiImportResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = result.balancesMatch;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmptyState(
            icon: ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
            title: ok ? 'Import completato: tutto torna' : 'Import completato con differenze',
            message: 'Importati ${plural(result.transactions, 'movimento', 'movimenti')} e '
                '${plural(result.transfers, 'trasferimento', 'trasferimenti')}'
                '${result.createdCategories > 0 ? ', create ${plural(result.createdCategories, 'categoria', 'categorie')}' : ''}.',
          ),
          for (final c in result.checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                children: [
                  Icon(
                    c.ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 20,
                    color: c.ok ? AppColors.income : AppColors.expense,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    c.ok
                        ? formatMoney(c.actualCents)
                        : '${formatMoney(c.actualCents)} (atteso ${formatMoney(c.expectedCents)})',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fine'),
          ),
        ],
      ),
    );
  }
}
