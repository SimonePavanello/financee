import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';
import '../transactions/transaction_form_screen.dart';
import 'account_editor_sheet.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key, required this.onShowMovements});

  /// Apre la lista movimenti filtrata sul conto.
  final ValueChanged<int> onShowMovements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final balances = ref.watch(accountBalancesProvider).asData?.value ?? const {};
    final usage = ref.watch(accountUsageProvider).asData?.value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conti'),
        actions: const [PrivacyToggleButton(), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-account',
        onPressed: () => showAccountEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuovo conto'),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e),
        data: (list) {
          final total = list.fold<int>(0, (s, a) => s + (balances[a.id] ?? 0));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            children: [
              PageContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NetWorthCard(
                      totalCents: total,
                      accountCount: list.length,
                      onTransfer: () => openTransferForm(context),
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(
                      title: 'I tuoi conti',
                      subtitle: 'Tocca un conto per vederne i movimenti',
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            (constraints.maxWidth / 360).floor().clamp(1, 3);
                        const spacing = 12.0;
                        final width = (constraints.maxWidth -
                                spacing * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final a in list)
                              SizedBox(
                                width: width,
                                child: _AccountCard(
                                  account: a,
                                  balance: balances[a.id] ?? a.initialBalanceCents,
                                  usage: usage[a.id] ?? 0,
                                  onTap: () => onShowMovements(a.id),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({
    required this.totalCents,
    required this.accountCount,
    required this.onTransfer,
  });

  final int totalCents;
  final int accountCount;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withValues(alpha: 0.3),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        runSpacing: 16,
        spacing: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Patrimonio totale',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SensitiveAmount(
                cents: totalCents,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Somma dei saldi di ${plural(accountCount, 'conto', 'conti')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: accountCount < 2 ? null : onTransfer,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.indigo,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.3),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
            ),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: Text(
              accountCount < 2 ? 'Crea un altro conto per trasferire' : 'Trasferisci',
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.balance,
    required this.usage,
    required this.onTap,
  });

  final AccountEntity account;
  final int balance;
  final int usage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      onTap: onTap,
      child: Row(
        children: [
          CategoryAvatar.account(account, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                SensitiveAmount(
                  cents: balance,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: balance < 0 ? AppColors.expense : null,
                  ),
                ),
                Text(
                  usage == 0
                      ? 'Nessun movimento'
                      : plural(usage, 'movimento', 'movimenti'),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Modifica conto',
            onPressed: () => showAccountEditor(context, existing: account),
            icon: Icon(Icons.edit_rounded, size: 20, color: muted),
          ),
        ],
      ),
    );
  }
}
