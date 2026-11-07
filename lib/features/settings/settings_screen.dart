import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/sample_data.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../backup/backup_widgets.dart';
import '../meal_vouchers/meal_voucher_widgets.dart';
import 'import_sossoldi_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _loadSample(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(
      context,
      title: 'Caricare i dati di esempio?',
      message:
          'Verranno aggiunti circa 170 movimenti e trasferimenti degli ultimi sei mesi, più i conti "Contanti" e "Risparmi" se mancano. I tuoi dati restano invariati.',
      action: 'Carica',
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final n = await insertSampleData(ref.read(databaseProvider));
    messenger.showSnackBar(SnackBar(content: Text('Aggiunti $n movimenti e trasferimenti di esempio')));
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final count = ref.read(transactionCountProvider).asData?.value ?? 0;
    final ok = await _confirm(
      context,
      title: 'Eliminare tutti i movimenti?',
      message:
          'Verranno eliminati definitivamente $count movimenti e tutti i trasferimenti tra conti. Conti, categorie, debiti e obiettivi restano (i debiti senza pagamenti). Se vuoi conservarli, esporta prima un backup.',
      action: 'Elimina tutto',
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final n = await ref.read(databaseProvider).deleteAllMovements();
    messenger.showSnackBar(SnackBar(content: Text('Eliminati $n movimenti')));
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(backgroundColor: AppColors.expense)
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final count = ref.watch(transactionCountProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          PageContainer(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(
                        title: 'Aspetto',
                        subtitle: 'Scegli il tema dell\'app',
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('Sistema'),
                            icon: Icon(Icons.brightness_auto_rounded),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Chiaro'),
                            icon: Icon(Icons.light_mode_rounded),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Scuro'),
                            icon: Icon(Icons.dark_mode_rounded),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) =>
                            ref.read(themeModeProvider.notifier).set(s.first),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SectionHeader(
                          title: 'Privacy',
                          subtitle: 'Saldi e conti coperti da •••• finché non tocchi l\'occhio',
                        ),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.visibility_off_rounded),
                        title: const Text('Nascondi saldi all\'avvio'),
                        subtitle: const Text(
                          'Saldo del mese, patrimonio e saldi dei conti non sono in chiaro quando apri l\'app',
                        ),
                        value: ref.watch(hideBalancesOnStartProvider),
                        onChanged: (v) =>
                            ref.read(hideBalancesOnStartProvider.notifier).set(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const MealVoucherSettingsCard(),
                const SizedBox(height: 20),
                const BackupSettingsCard(),
                const SizedBox(height: 20),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: SectionHeader(
                          title: 'Dati',
                          subtitle: count == null
                              ? 'Salvati solo su questo dispositivo'
                              : '${plural(count, 'movimento salvato', 'movimenti salvati')} su questo dispositivo',
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.upload_file_rounded),
                        title: const Text('Importa da Sossoldi'),
                        subtitle: const Text(
                          'Conti, categorie, movimenti e trasferimenti da un export CSV',
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ImportSossoldiScreen(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.science_rounded),
                        title: const Text('Carica dati di esempio'),
                        subtitle: const Text('Sei mesi di movimenti realistici'),
                        onTap: () => _loadSample(context, ref),
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.delete_sweep_rounded,
                          color: AppColors.expense,
                        ),
                        title: const Text(
                          'Elimina tutti i movimenti',
                          style: TextStyle(color: AppColors.expense),
                        ),
                        subtitle: const Text('Conti, categorie, debiti e obiettivi non vengono toccati'),
                        enabled: (count ?? 0) > 0,
                        onTap: () => _deleteAll(context, ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'Financiee',
                      applicationVersion: '1.0.0',
                    ),
                    child: const Text('Licenze open source'),
                  ),
                ),
                Center(
                  child: Text(
                    'Financiee · versione 1.0.0',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
