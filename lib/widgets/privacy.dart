import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/formatters.dart';
import '../providers.dart';

/// Testo mostrato al posto di un importo nascosto.
const kHiddenAmount = '•••• €';

/// Importo sensibile (saldi, patrimonio): con la modalità privacy attiva
/// mostra "•••• €"; toccandolo si scoprono tutti gli importi.
class SensitiveAmount extends ConsumerWidget {
  const SensitiveAmount({
    super.key,
    required this.cents,
    this.style,
    this.format = formatMoney,
    this.builder,
  });

  final int cents;
  final TextStyle? style;
  final String Function(int cents) format;

  /// Per mostrare l'importo visibile con un widget personalizzato
  /// (es. un numero animato). Se nullo si usa un semplice [Text].
  final Widget Function(BuildContext context)? builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balancesHiddenProvider);
    final child = hidden
        ? Text(kHiddenAmount, key: const ValueKey('hidden'), style: style)
        : KeyedSubtree(
            key: const ValueKey('visible'),
            child: builder?.call(context) ?? Text(format(cents), style: style),
          );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hidden
          ? () => ref.read(balancesHiddenProvider.notifier).set(false)
          : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        child: child,
      ),
    );
  }
}

/// Testo che contiene importi sensibili: [hiddenText] quando la privacy è
/// attiva, altrimenti [visibleText].
class SensitiveText extends ConsumerWidget {
  const SensitiveText({
    super.key,
    required this.visibleText,
    required this.hiddenText,
    this.style,
  });

  final String visibleText;
  final String hiddenText;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
        ref.watch(balancesHiddenProvider) ? hiddenText : visibleText,
        style: style,
      );
}

/// Icona a occhio che mostra o nasconde saldi e conti.
class PrivacyToggleButton extends ConsumerWidget {
  const PrivacyToggleButton({super.key, this.color, this.size = 22});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balancesHiddenProvider);
    return IconButton(
      tooltip: hidden ? 'Mostra saldi' : 'Nascondi saldi',
      visualDensity: VisualDensity.compact,
      onPressed: () => ref.read(balancesHiddenProvider.notifier).toggle(),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          key: ValueKey(hidden),
          color: color,
          size: size,
        ),
      ),
    );
  }
}
