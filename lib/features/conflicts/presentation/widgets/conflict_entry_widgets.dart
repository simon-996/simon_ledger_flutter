import 'package:flutter/material.dart';

import '../../../../core/widgets/app_components.dart';

class ConflictNoticeBanner extends StatelessWidget {
  const ConflictNoticeBanner({super.key, required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(18);
    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.standard,
      child: Material(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.46),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.compare_arrows_rounded,
                    size: 20,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '有 $count 项数据需要确认',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '逐项处理',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colorScheme.onTertiaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LedgerConflictChip extends StatelessWidget {
  const LedgerConflictChip({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '有 $count 项数据需要逐项确认',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colorScheme.tertiary.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          '冲突 $count 项',
          maxLines: 1,
          softWrap: false,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onTertiaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
