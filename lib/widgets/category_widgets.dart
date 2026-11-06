import 'package:flutter/material.dart';

import '../core/utils/category_style.dart';
import '../core/utils/formatters.dart';
import '../data/app_database.dart';

/// Icona della categoria su un quadrato arrotondato colorato.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.iconKey,
    required this.color,
    this.size = 44,
  });

  factory CategoryAvatar.of(CategoryEntity c, {double size = 44}) =>
      CategoryAvatar(iconKey: c.iconKey, color: Color(c.color), size: size);

  final String iconKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(categoryIcon(iconKey), color: color, size: size * 0.5),
    );
  }
}

/// Riga "categoria · importo · %" con barra proporzionale.
class CategoryShareRow extends StatelessWidget {
  const CategoryShareRow({
    super.key,
    required this.category,
    required this.totalCents,
    required this.share,
    this.caption,
    this.highlighted = false,
    this.onTap,
  });

  final CategoryEntity category;
  final int totalCents;
  final double share;
  final String? caption;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(category.color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted ? color.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CategoryAvatar.of(category, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatMoney(totalCents),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: ShareBar(value: share, color: color)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 48,
                        child: Text(
                          formatPercent(share),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (caption != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        caption!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra orizzontale animata (0..1).
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}
