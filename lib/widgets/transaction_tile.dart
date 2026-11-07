import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../data/models.dart';
import 'category_widgets.dart';

/// Riga della lista per qualsiasi movimento (entrata, uscita, trasferimento).
class MovementTile extends StatelessWidget {
  const MovementTile({
    super.key,
    required this.movement,
    this.onTap,
    this.showDate = true,
    this.showAccount = false,
    this.accountFilter,
  });

  final Movement movement;
  final VoidCallback? onTap;
  final bool showDate;

  /// Mostra il nome del conto (utile quando ce n'è più di uno).
  final bool showAccount;

  /// Se la lista è filtrata su un conto, i trasferimenti mostrano il segno
  /// rispetto a quel conto.
  final int? accountFilter;

  @override
  Widget build(BuildContext context) => switch (movement) {
        TransactionWithCategory t => TransactionTile(
            item: t,
            onTap: onTap,
            showDate: showDate,
            showAccount: showAccount,
          ),
        TransferWithAccounts t => TransferTile(
            item: t,
            onTap: onTap,
            showDate: showDate,
            accountFilter: accountFilter,
          ),
      };
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.item,
    this.onTap,
    this.showDate = true,
    this.showAccount = false,
  });

  final TransactionWithCategory item;
  final VoidCallback? onTap;
  final bool showDate;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final tx = item.tx;
    final hasNote = tx.note.trim().isNotEmpty;
    final parts = [
      if (hasNote) item.category.name,
      if (!hasNote && !showAccount) item.isIncome ? 'Entrata' : 'Uscita',
      if (showAccount) item.account.name,
      if (showDate) formatShortDate(tx.date),
    ];
    return _TileLayout(
      leading: CategoryAvatar.of(item.category),
      title: item.title,
      subtitle: parts.join(' · '),
      amount: formatSignedMoney(tx.amountCents, isIncome: item.isIncome),
      amountColor: AppColors.forIncome(item.isIncome),
      onTap: onTap,
    );
  }
}

class TransferTile extends StatelessWidget {
  const TransferTile({
    super.key,
    required this.item,
    this.onTap,
    this.showDate = true,
    this.accountFilter,
  });

  final TransferWithAccounts item;
  final VoidCallback? onTap;
  final bool showDate;
  final int? accountFilter;

  @override
  Widget build(BuildContext context) {
    final signed = item.signedCentsFor(accountFilter);
    final route = '${item.from.name} → ${item.to.name}';
    return _TileLayout(
      leading: const CategoryAvatar.icon(
        icon: Icons.swap_horiz_rounded,
        color: AppColors.transfer,
      ),
      title: item.title,
      subtitle: [route, if (showDate) formatShortDate(item.date)].join(' · '),
      amount: signed == 0
          ? formatMoney(item.amountCents)
          : formatSignedMoney(signed, isIncome: signed > 0),
      amountColor: AppColors.transfer,
      onTap: onTap,
    );
  }
}

class _TileLayout extends StatelessWidget {
  const _TileLayout({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              amount,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
