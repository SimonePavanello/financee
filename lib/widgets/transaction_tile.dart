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
  /// rispetto a quel conto e le spese pagate in parte con i buoni solo la
  /// parte di quel conto.
  final int? accountFilter;

  @override
  Widget build(BuildContext context) => switch (movement) {
        TransactionWithCategory t => TransactionTile(
            item: t,
            onTap: onTap,
            showDate: showDate,
            showAccount: showAccount,
            accountFilter: accountFilter,
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
    this.accountFilter,
  });

  final TransactionWithCategory item;
  final VoidCallback? onTap;
  final bool showDate;
  final bool showAccount;
  final int? accountFilter;

  @override
  Widget build(BuildContext context) {
    final tx = item.tx;
    final hasNote = tx.note.trim().isNotEmpty;
    // Con il filtro su un conto si vede solo la parte di quel conto.
    final cents = item.centsFor(accountFilter);
    final partial = cents != tx.amountCents;
    final String? split;
    if (!item.usesVouchers) {
      split = null;
    } else if (!partial) {
      split = showAccount
          ? item.accountLabel
          : '${formatMoney(item.voucherCents)} in buoni';
    } else if (accountFilter == item.voucherAccount!.id) {
      split = 'in buoni, su ${formatMoney(tx.amountCents)}';
    } else {
      split = '+ ${formatMoney(item.voucherCents)} in buoni';
    }
    final parts = [
      if (hasNote) item.category.name,
      if (!hasNote && !showAccount && split == null)
        item.isIncome ? 'Entrata' : 'Uscita',
      if (showAccount && split == null) item.account.name,
      ?split,
      if (showDate) formatShortDate(tx.date),
    ];
    return _TileLayout(
      leading: CategoryAvatar.of(item.category),
      title: item.title,
      subtitle: parts.join(' · '),
      amount: formatSignedMoney(cents, isIncome: item.isIncome),
      amountColor: AppColors.forIncome(item.isIncome),
      badge: item.usesVouchers ? Icons.confirmation_number_rounded : null,
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
    this.badge,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;

  /// Piccola icona accanto all'importo (es. spesa pagata con i buoni).
  final IconData? badge;
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
            if (badge != null) ...[
              Icon(
                badge,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
                semanticLabel: 'Pagato in parte con i buoni pasto',
              ),
              const SizedBox(width: 6),
            ],
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
