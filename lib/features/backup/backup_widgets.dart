import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/backup/backup.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../reports/export/file_export.dart';
import 'restore_backup_screen.dart';

/// Dopo quanti giorni dall'ultimo backup la dashboard lo ricorda.
const kBackupReminderDays = 30;

/// Copia di tutti i dati con le impostazioni da conservare.
Future<BackupFile> createAppBackup(WidgetRef ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return ref.read(databaseProvider).createBackup(
    settings: {
      for (final k in kBackupSettingKeys)
        if (prefs.get(k) case final Object v) k: v,
    },
  );
}

/// Esporta un backup (web: download; Android: menu di condivisione) e
/// mostra l'esito. Restituisce `true` se il file è stato salvato.
Future<bool> exportBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final backup = await createAppBackup(ref);
    final result = await exportJson(
      backupFileName(backup.createdAt),
      backup.encode(),
    );
    if (result.saved) {
      ref.read(lastBackupProvider.notifier).set(backup.createdAt);
    }
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
    return result.saved;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Backup non riuscito: $e')),
    );
    return false;
  }
}

/// `true` se l'ultimo backup manca o è più vecchio di [kBackupReminderDays].
bool backupIsDue(DateTime? lastBackup, DateTime now) =>
    lastBackup == null ||
    now.difference(lastBackup).inDays >= kBackupReminderDays;

/// Card "Backup" delle impostazioni: esporta e ripristina tutti i dati.
class BackupSettingsCard extends ConsumerStatefulWidget {
  const BackupSettingsCard({super.key});

  @override
  ConsumerState<BackupSettingsCard> createState() => _BackupSettingsCardState();
}

class _BackupSettingsCardState extends ConsumerState<BackupSettingsCard> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    await exportBackup(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = ref.watch(lastBackupProvider);
    final due = backupIsDue(last, DateTime.now());
    final statusColor = due ? AppColors.warning : AppColors.income;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SectionHeader(
              title: 'Backup',
              subtitle:
                  'I dati sono salvati solo su questo dispositivo (sul web, '
                  'in questo browser): un backup li mette al sicuro',
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  due ? Icons.warning_amber_rounded : Icons.verified_rounded,
                  size: 18,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    last == null
                        ? 'Non hai ancora fatto un backup'
                        : 'Ultimo backup il ${formatDate(last)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: _busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : const Icon(Icons.save_alt_rounded),
            title: const Text('Esporta backup'),
            subtitle: const Text(
              'Un file .json con conti, movimenti, categorie, debiti e '
              'obiettivi: conservalo su Drive, sul PC o su una chiavetta',
            ),
            enabled: !_busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_rounded),
            title: const Text('Ripristina da un backup'),
            subtitle: const Text(
              'Sostituisce tutti i dati con quelli del file, dopo '
              'un\'anteprima',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RestoreBackupScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Promemoria della dashboard quando il backup manca o è vecchio.
class BackupReminderCard extends ConsumerStatefulWidget {
  const BackupReminderCard({super.key});

  /// Da mostrare se ci sono movimenti, il backup è da fare e il promemoria
  /// non è stato rimandato.
  static bool isVisible(WidgetRef ref) {
    final count = ref.watch(transactionCountProvider).asData?.value ?? 0;
    final snoozedUntil = ref.watch(backupReminderSnoozeProvider);
    final now = DateTime.now();
    if (count == 0) return false;
    if (snoozedUntil != null && now.isBefore(snoozedUntil)) return false;
    return backupIsDue(ref.watch(lastBackupProvider), now);
  }

  @override
  ConsumerState<BackupReminderCard> createState() => _BackupReminderCardState();
}

class _BackupReminderCardState extends ConsumerState<BackupReminderCard> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    await exportBackup(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = ref.watch(lastBackupProvider);
    return AppCard(
      color: AppColors.warning.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_rounded, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      last == null
                          ? 'Metti al sicuro i tuoi dati'
                          : 'È ora di un nuovo backup',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      last == null
                          ? 'I dati sono salvati solo su questo dispositivo: '
                                'se svuoti il browser o cambi telefono li '
                                'perdi. Esporta un backup e conservalo al '
                                'sicuro.'
                          : 'L\'ultimo backup è del ${formatDate(last)}. '
                                'Esportane uno nuovo per non perdere i '
                                'movimenti registrati da allora.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => ref
                    .read(backupReminderSnoozeProvider.notifier)
                    .snooze(const Duration(days: 7)),
                child: const Text('Più tardi'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_rounded),
                label: const Text('Esporta backup'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
