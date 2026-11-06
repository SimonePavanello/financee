import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/sample_data.dart';
import '../../domain/analytics.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../settings/settings_screen.dart';
import '../transactions/transaction_form_screen.dart';
import 'dashboard_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(error: e),
          data: (data) => _DashboardContent(data: data, onSeeAll: onSeeAll),
        ),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.data, required this.onSeeAll});

  final DashboardData data;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = ref.watch(transactionCountProvider).asData?.value;
    final monthNotifier = ref.read(selectedMonthProvider.notifier);

    final header = _Header(
      period: PeriodNavigator(
        label: formatMonthYear(data.period.start),
        onPrevious: monthNotifier.previous,
        onNext: monthNotifier.next,
        onTapLabel: monthNotifier.reset,
      ),
    );
    final hero = BalanceCard(data: data);
    final stats = QuickStats(data: data);
    final breakdown = CategoryBreakdownCard(summary: data.current);
    final trend = TrendCard(buckets: data.trend);
    final recent = RecentTransactionsCard(
      items: data.recent,
      onSeeAll: onSeeAll,
      onTapItem: (i) => openTransactionForm(context, existing: i),
    );
    final welcome = totalCount == 0 ? const _WelcomeCard() : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        const gap = SizedBox(height: 20, width: 20);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            PageContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 20),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 11,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [hero, gap, trend, gap, recent],
                          ),
                        ),
                        gap,
                        Expanded(
                          flex: 9,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [?welcome, if (welcome != null) gap, stats, gap, breakdown],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    hero,
                    gap,
                    if (welcome != null) ...[welcome, gap],
                    stats,
                    gap,
                    breakdown,
                    gap,
                    trend,
                    gap,
                    recent,
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.period});

  final Widget period;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'Buonanotte';
    if (h < 13) return 'Buongiorno';
    if (h < 18) return 'Buon pomeriggio';
    return 'Buonasera';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _greeting(),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          'La tua panoramica',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
    final settings = IconButton.filledTonal(
      tooltip: 'Impostazioni',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
      icon: const Icon(Icons.tune_rounded),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Row(
            children: [
              Expanded(child: title),
              period,
              const SizedBox(width: 12),
              settings,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: title), settings]),
            const SizedBox(height: 14),
            period,
          ],
        );
      },
    );
  }
}

class _WelcomeCard extends ConsumerStatefulWidget {
  const _WelcomeCard();

  @override
  ConsumerState<_WelcomeCard> createState() => _WelcomeCardState();
}

class _WelcomeCardState extends ConsumerState<_WelcomeCard> {
  bool _loading = false;

  Future<void> _loadSample() async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    final n = await insertSampleData(ref.read(databaseProvider));
    if (mounted) setState(() => _loading = false);
    messenger.showSnackBar(
      SnackBar(content: Text('Aggiunti $n movimenti di esempio')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.indigo.withValues(alpha: 0.06),
      child: EmptyState(
        icon: Icons.auto_awesome_rounded,
        title: 'Benvenuto!',
        message:
            'Registra il tuo primo movimento oppure esplora l\'app con sei mesi di dati di esempio.',
        actions: [
          FilledButton.icon(
            onPressed: () => openTransactionForm(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Aggiungi movimento'),
          ),
          OutlinedButton.icon(
            onPressed: _loading ? null : _loadSample,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.science_rounded),
            label: const Text('Dati di esempio'),
          ),
        ],
      ),
    );
  }
}
