import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

String currencyName(String code) => switch (code.trim().toUpperCase()) {
  'CNY' => '人民币',
  'USD' => '美元',
  'EUR' => '欧元',
  'GBP' => '英镑',
  'JPY' => '日元',
  'HKD' => '港币',
  'TWD' => '新台币',
  'MOP' => '澳门元',
  'SGD' => '新加坡元',
  'THB' => '泰铢',
  'MYR' => '马来西亚林吉特',
  'KRW' => '韩元',
  'AUD' => '澳元',
  'CAD' => '加元',
  'NZD' => '新西兰元',
  'CHF' => '瑞士法郎',
  _ => code.trim().toUpperCase(),
};

/// Local image assets avoid platform-dependent emoji rendering.
/// Currency mappings include EU for EUR and regional flags for HKD/MOP/TWD.
class CurrencyFlag extends StatelessWidget {
  const CurrencyFlag({super.key, required this.code, this.width = 24});
  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final normalized = code.trim().toUpperCase();
    final flag = CountryFlag.fromCurrencyCode(
      normalized,
      theme: ImageTheme(
        width: width,
        height: width * 2 / 3,
        shape: const RoundedRectangle(2),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 2 / 3,
        child: flag.flagCode == null
            ? Icon(
                Icons.currency_exchange_rounded,
                size: width,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )
            : flag,
      ),
    );
  }
}

class CurrencyLabel extends StatelessWidget {
  const CurrencyLabel({
    super.key,
    required this.code,
    this.showName = true,
    this.style,
  });
  final String code;
  final bool showName;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final normalized = code.trim().toUpperCase();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CurrencyFlag(code: normalized),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            showName ? '$normalized · ${currencyName(normalized)}' : normalized,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
