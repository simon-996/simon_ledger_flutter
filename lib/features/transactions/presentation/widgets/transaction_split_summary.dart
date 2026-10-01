import 'package:flutter/material.dart';

import '../../../../core/models/ledger.dart';
import '../../../../core/models/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/currency_widgets.dart';

class TransactionSplitSummary extends StatelessWidget {
  const TransactionSplitSummary({
    super.key,
    required this.type,
    required this.amount,
    required this.currency,
    required this.participantCount,
    this.payerName,
    this.ledger,
  });

  final int type;
  final double? amount;
  final String currency;
  final int participantCount;
  final String? payerName;
  final Ledger? ledger;

  double? _totalFor(String target, String source) {
    final value = amount;
    if (value == null || !value.isFinite || value <= 0) return null;
    if (target == source) return value;
    final book = ledger;
    if (book == null || !supportedCurrenciesForLedger(book).contains(source)) {
      return null;
    }
    final rate = book.exchangeRateToCNY;
    if (!rate.isFinite || rate <= 0) return null;
    final converted = source == 'CNY' ? value / rate : value * rate;
    return converted.isFinite && converted > 0 ? converted : null;
  }

  @override
  Widget build(BuildContext context) {
    final source = currency.trim().toUpperCase();
    final currencies = <String>{
      source,
      if (ledger != null) ...supportedCurrenciesForLedger(ledger!),
    };
    final colors = Theme.of(context).colorScheme;
    final payer = type == 1 ? '收入分配' : '${payerName ?? '共同钱包'}付款';
    final valid = amount != null && amount!.isFinite && amount! > 0;
    final missingConversion =
        valid &&
        currencies.any(
          (code) => code != source && _totalFor(code, source) == null,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$payer · $participantCount 人${type == 1 ? '收款' : '承担'}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            for (final code in currencies)
              _SplitCurrencyRow(
                currency: code,
                total: _totalFor(code, source),
                participantCount: participantCount,
                converted: code != source,
              ),
            if (missingConversion)
              Text(
                '当前汇率或金额无法换算，换算金额暂不显示',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _SplitCurrencyRow extends StatelessWidget {
  const _SplitCurrencyRow({
    required this.currency,
    required this.total,
    required this.participantCount,
    required this.converted,
  });

  final String currency;
  final double? total;
  final int participantCount;
  final bool converted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefix = converted ? '≈ ' : '';
    final totalLabel =
        '总额 $prefix$currency ${total?.toStringAsFixed(2) ?? '—'}';
    final splitLabel =
        '每人 $prefix$currency ${total != null && participantCount > 0 ? (total! / participantCount).toStringAsFixed(2) : '—'}';
    return Container(
      key: ValueKey('split-currency-$currency'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CurrencyLabel(
            code: currency,
            showName: false,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          DefaultTextStyle(
            style: theme.textTheme.bodySmall!,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalText = Text(totalLabel);
                final splitText = Text(splitLabel);
                final scaledWidth =
                    constraints.maxWidth /
                    MediaQuery.textScalerOf(context).scale(1);
                if (scaledWidth < 280) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [totalText, const SizedBox(height: 4), splitText],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: totalText),
                    const SizedBox(width: 12),
                    Expanded(child: splitText),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
