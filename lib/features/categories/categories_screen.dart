import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_database.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import 'category_editor_sheet.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  TxType get _currentType => _tabs.index == 0 ? TxType.expense : TxType.income;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final usage = ref.watch(categoryUsageProvider).asData?.value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorie'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: PageContainer(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _PillTabBar(controller: _tabs),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-category',
        onPressed: () => showCategoryEditor(context, initialType: _currentType),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuova categoria'),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e),
        data: (all) => TabBarView(
          controller: _tabs,
          children: [
            for (final type in [TxType.expense, TxType.income])
              _CategoryGrid(
                categories: all.where((c) => c.type == type).toList(),
                usage: usage,
                type: type,
              ),
          ],
        ),
      ),
    );
  }
}

class _PillTabBar extends StatelessWidget {
  const _PillTabBar({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        tabs: const [Tab(text: 'Spese'), Tab(text: 'Entrate')],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.usage,
    required this.type,
  });

  final List<CategoryEntity> categories;
  final Map<int, int> usage;
  final TxType type;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.category_rounded,
          title: 'Nessuna categoria',
          message: type == TxType.income
              ? 'Crea una categoria per classificare le tue entrate.'
              : 'Crea una categoria per classificare le tue spese.',
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          sliver: SliverToBoxAdapter(
            child: PageContainer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 340).floor().clamp(1, 3);
                  const spacing = 12.0;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) / columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final c in categories)
                        SizedBox(
                          width: width,
                          child: _CategoryCard(
                            category: c,
                            count: usage[c.id] ?? 0,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.count});

  final CategoryEntity category;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => showCategoryEditor(context, existing: category),
      child: Row(
        children: [
          CategoryAvatar.of(category, size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  switch (count) {
                    0 => 'Nessun movimento',
                    1 => '1 movimento',
                    _ => '$count movimenti',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.edit_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
