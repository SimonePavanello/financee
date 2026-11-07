import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers.dart';
import '../accounts/accounts_screen.dart';
import '../categories/categories_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../reports/reports_screen.dart';
import '../transactions/transaction_form_screen.dart';
import '../transactions/transactions_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Destination('Movimenti', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  _Destination('Conti', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded),
  _Destination('Report', Icons.insights_outlined, Icons.insights_rounded),
  _Destination('Categorie', Icons.category_outlined, Icons.category_rounded),
];

const _movementsTab = 1;
const _accountsTab = 2;
const _categoriesTab = 4;

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  late final List<Widget> _pages = [
    DashboardScreen(
      onSeeAll: () => _select(_movementsTab),
      onManageAccounts: () => _select(_accountsTab),
      onShowAccount: _showAccount,
    ),
    const TransactionsScreen(),
    AccountsScreen(onShowMovements: _showAccount),
    const ReportsScreen(),
    const CategoriesScreen(),
  ];

  void _select(int i) => setState(() => _index = i);

  /// Apre i movimenti filtrati sul conto indicato.
  void _showAccount(int accountId) {
    ref.read(accountFilterProvider.notifier).set(accountId);
    _select(_movementsTab);
  }

  Future<void> _addTransaction() async {
    final messenger = ScaffoldMessenger.of(context);
    // Dalla lista filtrata su un conto, il nuovo movimento parte da quel conto.
    final saved = await openTransactionForm(
      context,
      accountId: _index == _movementsTab ? ref.read(accountFilterProvider) : null,
    );
    if (saved == true) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Movimento salvato')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final body = IndexedStack(index: _index, children: _pages);

    if (width >= 840) {
      final extended = width >= 1200;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: extended,
              minExtendedWidth: 220,
              selectedIndex: _index,
              onDestinationSelected: _select,
              groupAlignment: -0.85,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                child: Column(
                  children: [
                    _Logo(extended: extended),
                    const SizedBox(height: 24),
                    extended
                        ? FloatingActionButton.extended(
                            heroTag: 'add-rail',
                            elevation: 0,
                            onPressed: _addTransaction,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Nuovo movimento'),
                          )
                        : FloatingActionButton(
                            heroTag: 'add-rail',
                            elevation: 0,
                            tooltip: 'Nuovo movimento',
                            onPressed: _addTransaction,
                            child: const Icon(Icons.add_rounded),
                          ),
                  ],
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      floatingActionButton: _index == _accountsTab || _index == _categoriesTab
          ? null
          : FloatingActionButton(
              heroTag: 'add-bottom',
              tooltip: 'Nuovo movimento',
              onPressed: _addTransaction,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
    );
    if (!extended) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text(
          'Financiee',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
