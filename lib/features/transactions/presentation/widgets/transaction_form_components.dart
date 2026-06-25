import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';

Color transactionAccentColor(ColorScheme _, int transactionType) {
  return transactionType == 1 ? AppTheme.incomeColor : AppTheme.expenseColor;
}

Color transactionOnAccentColor(ColorScheme _, int transactionType) {
  return Colors.white;
}

class TransactionTypeSelector extends StatelessWidget {
  const TransactionTypeSelector({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  final int selectedType;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TransactionTypeButton(
            label: '支出',
            icon: Icons.remove_rounded,
            selected: selectedType == 0,
            value: 0,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TransactionTypeButton(
            label: '收入',
            icon: Icons.add_rounded,
            selected: selectedType == 1,
            value: 1,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TransactionTypeButton extends StatelessWidget {
  const _TransactionTypeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = transactionAccentColor(colorScheme, value);
    final mutedColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.48);

    return AnimatedContainer(
      key: ValueKey('transaction-type-option-$value'),
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      height: 48,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: selected ? null : () => onChanged(value),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: selected ? accent : mutedColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? accent : mutedColor,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentModePanel extends StatelessWidget {
  const PaymentModePanel({
    super.key,
    required this.paidByPerson,
    required this.description,
    required this.onChanged,
  });

  final bool paidByPerson;
  final String description;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _PaymentModeOption(
                selected: !paidByPerson,
                icon: Icons.account_balance_wallet_outlined,
                label: '共同钱包',
                onTap: () {
                  if (paidByPerson) onChanged(false);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PaymentModeOption(
                selected: paidByPerson,
                icon: Icons.person_outline_rounded,
                label: '某人代付',
                onTap: () {
                  if (!paidByPerson) onChanged(true);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: AppMotion.fast,
          child: Text(
            description,
            key: ValueKey(description),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentModeOption extends StatelessWidget {
  const _PaymentModeOption({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return AnimatedContainer(
      key: ValueKey('payment-mode-option-$label'),
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      height: 44,
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? colorScheme.primary : mutedColor,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? colorScheme.primary : mutedColor,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransactionAnimatedVisibility extends StatelessWidget {
  const TransactionAnimatedVisibility({
    super.key,
    required this.visible,
    required this.visibleKey,
    required this.hiddenKey,
    required this.child,
  });

  final bool visible;
  final Object visibleKey;
  final Object hiddenKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.emphasized,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppMotion.fast,
        switchInCurve: AppMotion.emphasized,
        switchOutCurve: AppMotion.standard,
        transitionBuilder: transactionTopFadeSlideTransition,
        child: visible
            ? KeyedSubtree(key: ValueKey(visibleKey), child: child)
            : SizedBox.shrink(key: ValueKey(hiddenKey)),
      ),
    );
  }
}

class CurrencySelector extends StatelessWidget {
  const CurrencySelector({
    super.key,
    required this.currencies,
    required this.selectedCurrency,
    required this.onChanged,
  });

  final List<String> currencies;
  final String selectedCurrency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (currencies.length == 1) {
      final currency = currencies.first;
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: _CurrencyQuickItem(
          currency: currency,
          selected: currency == selectedCurrency,
          fillWidth: true,
          onTap: () {
            if (currency != selectedCurrency) {
              onChanged(currency);
            }
          },
        ),
      );
    }

    if (currencies.length == 2) {
      return SizedBox(
        height: 56,
        child: Row(
          children: [
            for (var index = 0; index < currencies.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(
                child: _CurrencyQuickItem(
                  currency: currencies[index],
                  selected: currencies[index] == selectedCurrency,
                  fillWidth: true,
                  onTap: () {
                    final currency = currencies[index];
                    if (currency != selectedCurrency) {
                      onChanged(currency);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        itemCount: currencies.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final currency = currencies[index];
          return _CurrencyQuickItem(
            currency: currency,
            selected: currency == selectedCurrency,
            fillWidth: false,
            onTap: () {
              if (currency != selectedCurrency) {
                onChanged(currency);
              }
            },
          );
        },
      ),
    );
  }
}

class _CurrencyQuickItem extends StatelessWidget {
  const _CurrencyQuickItem({
    required this.currency,
    required this.selected,
    required this.fillWidth,
    required this.onTap,
  });

  final String currency;
  final bool selected;
  final bool fillWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = currency.trim().toUpperCase();
    final displayName = _currencyDisplayName(label);
    final mutedColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.52);

    return AnimatedContainer(
      key: ValueKey('currency-option-$label'),
      width: fillWidth ? double.infinity : null,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: fillWidth ? 8 : 12,
              vertical: 8,
            ),
            child: Row(
              mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: fillWidth
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected ? colorScheme.primary : mutedColor,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected
                              ? colorScheme.onSurfaceVariant
                              : mutedColor,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _currencyDisplayName(String code) {
    return switch (code) {
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
      _ => code,
    };
  }
}

class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.isIncome,
    required this.onChanged,
    this.onAddCategory,
  });

  final List<String> categories;
  final String selectedCategory;
  final bool isIncome;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAddCategory;

  @override
  Widget build(BuildContext context) {
    final showAddAction = onAddCategory != null;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.hardEdge,
        itemCount: categories.length + (showAddAction ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (showAddAction && index == categories.length) {
            return _AddCategoryQuickItem(
              isIncome: isIncome,
              onTap: onAddCategory!,
            );
          }
          final category = categories[index];
          return _CategoryQuickItem(
            category: category,
            icon: _iconFor(category),
            selected: category == selectedCategory,
            isIncome: isIncome,
            onTap: () {
              if (category != selectedCategory) {
                onChanged(category);
              }
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(String category) {
    return switch (category) {
      '交通' => Icons.directions_bus_filled_outlined,
      '购物' => Icons.shopping_bag_outlined,
      '餐饮' => Icons.restaurant_outlined,
      '杂费' => Icons.widgets_outlined,
      '娱乐' => Icons.sports_esports_outlined,
      '居住' => Icons.home_outlined,
      '工资' => Icons.badge_outlined,
      '兼职' => Icons.work_outline_rounded,
      '理财' => Icons.account_balance_outlined,
      '红包' => Icons.card_giftcard_rounded,
      '其他' => Icons.more_horiz_rounded,
      _ => Icons.category_outlined,
    };
  }
}

Future<String?> showTransactionCategoryCreateSheet({
  required BuildContext context,
  required List<String> categories,
  required bool isIncome,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) =>
        _CategoryCreateSheet(categories: categories, isIncome: isIncome),
  );
}

class _AddCategoryQuickItem extends StatelessWidget {
  const _AddCategoryQuickItem({required this.isIncome, required this.onTap});

  final bool isIncome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = transactionAccentColor(colorScheme, isIncome ? 1 : 0);

    return Tooltip(
      message: '添加自定义分类',
      child: AnimatedContainer(
        key: const ValueKey('category-option-add'),
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    '自定义',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCreateSheet extends StatefulWidget {
  const _CategoryCreateSheet({
    required this.categories,
    required this.isIncome,
  });

  final List<String> categories;
  final bool isIncome;

  @override
  State<_CategoryCreateSheet> createState() => _CategoryCreateSheetState();
}

class _CategoryCreateSheetState extends State<_CategoryCreateSheet> {
  final _controller = TextEditingController();
  String _value = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = transactionAccentColor(colorScheme, widget.isIncome ? 1 : 0);
    final normalized = _value.trim();
    final duplicated = widget.categories.contains(normalized);
    final canSubmit = normalized.isNotEmpty && !duplicated;

    return AnimatedPadding(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '添加${widget.isIncome ? '收入' : '支出'}分类',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('category-create-input'),
                controller: _controller,
                autofocus: true,
                maxLength: 8,
                textInputAction: TextInputAction.done,
                onChanged: (value) => setState(() => _value = value),
                onSubmitted: (_) => _submit(canSubmit, normalized),
                decoration: InputDecoration(
                  labelText: '分类名称',
                  hintText: widget.isIncome ? '例如 奖金' : '例如 咖啡',
                  prefixIcon: Icon(Icons.category_outlined, color: accent),
                  errorText: duplicated ? '这个分类已经存在' : null,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('category-create-submit'),
                onPressed: canSubmit ? () => _submit(true, normalized) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加分类'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit(bool canSubmit, String normalized) {
    if (!canSubmit) return;
    Navigator.of(context).pop(normalized);
  }
}

class _CategoryQuickItem extends StatelessWidget {
  const _CategoryQuickItem({
    required this.category,
    required this.icon,
    required this.selected,
    required this.isIncome,
    required this.onTap,
  });

  final String category;
  final IconData icon;
  final bool selected;
  final bool isIncome;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = transactionAccentColor(colorScheme, isIncome ? 1 : 0);
    final mutedColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return AnimatedContainer(
      key: ValueKey('category-option-$category'),
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? accent : mutedColor),
                const SizedBox(width: 6),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? accent : mutedColor,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TransactionSaveButton extends StatelessWidget {
  const TransactionSaveButton({
    super.key,
    required this.onPressed,
    required this.loading,
    required this.readyLabel,
    required this.loadingLabel,
  });

  final VoidCallback? onPressed;
  final bool loading;
  final String readyLabel;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;

    return AppPressable(
      enabled: enabled,
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            disabledBackgroundColor: colorScheme.surfaceContainerHighest,
            disabledForegroundColor: colorScheme.onSurfaceVariant,
            textStyle: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            child: loading
                ? Row(
                    key: ValueKey('transaction-save-loading-$loadingLabel'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(loadingLabel),
                    ],
                  )
                : Row(
                    key: ValueKey('transaction-save-ready-$readyLabel'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_rounded, size: 22),
                      const SizedBox(width: 8),
                      Text(readyLabel),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class TransactionResponsivePair extends StatelessWidget {
  const TransactionResponsivePair({
    super.key,
    required this.first,
    required this.second,
    this.breakpoint = 420,
  });

  final Widget first;
  final Widget second;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), second],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

Widget transactionTopFadeSlideTransition(
  Widget child,
  Animation<double> animation,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: AppMotion.emphasized,
  );
  final offset = Tween<Offset>(
    begin: const Offset(0, -0.035),
    end: Offset.zero,
  ).animate(curved);

  return FadeTransition(
    opacity: animation,
    child: SlideTransition(position: offset, child: child),
  );
}
