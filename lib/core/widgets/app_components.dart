import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ledger.dart';
import '../models/person.dart';
import '../network/friendly_error.dart';
import '../theme/app_theme.dart';

class AppMotion {
  static const Duration micro = Duration(milliseconds: 110);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 460);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
  static const Curve spring = Curves.easeOutBack;
}

enum AppNoticeType { success, info, error }

class AppNotice {
  AppNotice._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message,
      type: AppNoticeType.success,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message,
      type: AppNoticeType.info,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    show(
      context,
      message,
      type: AppNoticeType.error,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void show(
    BuildContext context,
    String message, {
    AppNoticeType type = AppNoticeType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
    dismiss();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _AppNoticeOverlay(
          message: message,
          type: type,
          actionLabel: actionLabel,
          onAction: onAction == null
              ? null
              : () {
                  dismiss();
                  onAction();
                },
          onClose: dismiss,
        );
      },
    );

    _currentEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(
      duration ?? _durationFor(type, hasAction: actionLabel != null),
      dismiss,
    );
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  static Duration _durationFor(AppNoticeType type, {required bool hasAction}) {
    if (hasAction) return const Duration(seconds: 4);
    return switch (type) {
      AppNoticeType.success => const Duration(milliseconds: 1400),
      AppNoticeType.info => const Duration(milliseconds: 1800),
      AppNoticeType.error => const Duration(milliseconds: 3200),
    };
  }
}

class _AppNoticeOverlay extends StatelessWidget {
  const _AppNoticeOverlay({
    required this.message,
    required this.type,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final AppNoticeType type;
  final VoidCallback onClose;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final config = _config(colorScheme);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.normal,
              curve: AppMotion.emphasized,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, -10 + 10 * value),
                    child: Transform.scale(
                      scale: 0.98 + value * 0.02,
                      child: child,
                    ),
                  ),
                );
              },
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: config.borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.12),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: config.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              config.icon,
                              size: 18,
                              color: config.color,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (actionLabel != null && onAction != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: onAction,
                              child: Text(actionLabel!),
                            ),
                          ],
                          const SizedBox(width: 2),
                          IconButton(
                            tooltip: '关闭',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: onClose,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _AppNoticeVisualConfig _config(ColorScheme colorScheme) {
    return switch (type) {
      AppNoticeType.success => _AppNoticeVisualConfig(
        icon: Icons.check_rounded,
        color: colorScheme.primary,
        borderColor: colorScheme.primary.withValues(alpha: 0.28),
      ),
      AppNoticeType.info => _AppNoticeVisualConfig(
        icon: Icons.info_outline_rounded,
        color: colorScheme.tertiary,
        borderColor: colorScheme.tertiary.withValues(alpha: 0.28),
      ),
      AppNoticeType.error => _AppNoticeVisualConfig(
        icon: Icons.error_outline_rounded,
        color: colorScheme.error,
        borderColor: colorScheme.error.withValues(alpha: 0.3),
      ),
    };
  }
}

class _AppNoticeVisualConfig {
  const _AppNoticeVisualConfig({
    required this.icon,
    required this.color,
    required this.borderColor,
  });

  final IconData icon;
  final Color color;
  final Color borderColor;
}

class AppAnimatedEntry extends StatefulWidget {
  const AppAnimatedEntry({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.slow,
    this.offset = const Offset(0, 0.025),
    this.curve = AppMotion.emphasized,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final Curve curve;

  @override
  State<AppAnimatedEntry> createState() => _AppAnimatedEntryState();
}

class _AppAnimatedEntryState extends State<AppAnimatedEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(curved);
    _scale = Tween<double>(begin: 0.985, end: 1).animate(curved);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}

class AppAnimatedIndexedStack extends StatelessWidget {
  const AppAnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = AppMotion.normal,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: i != index,
              child: ExcludeSemantics(
                excluding: i != index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: duration,
                  curve: AppMotion.standard,
                  child: AnimatedSlide(
                    offset: i == index
                        ? Offset.zero
                        : Offset(i < index ? -0.018 : 0.018, 0),
                    duration: duration,
                    curve: AppMotion.emphasized,
                    child: AnimatedScale(
                      scale: i == index ? 1 : 0.992,
                      duration: duration,
                      curve: AppMotion.emphasized,
                      child: TickerMode(
                        enabled: i == index,
                        child: RepaintBoundary(child: children[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AppAnimatedSwitcher extends StatelessWidget {
  const AppAnimatedSwitcher({
    super.key,
    required this.child,
    this.duration = AppMotion.normal,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.emphasized,
      switchOutCurve: AppMotion.standard,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 0.98, end: 1).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: child,
    );
  }
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({
    super.key,
    this.title = '加载中',
    this.message,
    this.icon = Icons.hourglass_empty_rounded,
  });

  final String title;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: AppAnimatedEntry(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AppSectionCard(
              padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
              child: Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: AppMotion.slow,
                    curve: AppMotion.emphasized,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.96 + value * 0.04,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.42,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: colorScheme.primary,
                              backgroundColor: colorScheme.primary.withValues(
                                alpha: 0.1,
                              ),
                            ),
                          ),
                          Icon(icon, size: 18, color: colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            message!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
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

class AppInlineLoadingCard extends StatelessWidget {
  const AppInlineLoadingCard({super.key, this.message = '加载中'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppSectionCard(
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: AppAnimatedEntry(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(icon, size: 44, color: colorScheme.primary),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 24), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.standard,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color:
              borderColor ?? colorScheme.outlineVariant.withValues(alpha: 0.58),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.07),
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        // ignore: use_null_aware_elements, build_runner's analyzer cannot parse ?element yet.
        if (trailing != null) trailing!,
      ],
    );
  }
}

class AppMetricTile extends StatelessWidget {
  const AppMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppSectionCard(
      padding: const EdgeInsets.all(14),
      color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.82),
      borderColor: Colors.white.withValues(alpha: 0.34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppPersonBalanceCard extends StatelessWidget {
  const AppPersonBalanceCard({
    super.key,
    required this.avatar,
    required this.name,
    required this.balance,
    required this.isPositive,
    this.isSelected = false,
    this.onTap,
  });

  final String avatar;
  final String name;
  final String balance;
  final bool isPositive;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final amountColor = isPositive ? colorScheme.primary : colorScheme.error;

    return _AnimatedTapSurface(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.76)
          : colorScheme.surfaceContainerLowest,
      borderRadius: 18,
      borderSide: BorderSide(
        width: isSelected ? 1.5 : 1,
        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
      ),
      onTap: onTap,
      child: SizedBox(
        width: 92,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(avatar, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  balance,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w800,
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

class AppPersonChoiceItem {
  const AppPersonChoiceItem({
    required this.id,
    required this.name,
    required this.avatar,
  });

  final String id;
  final String name;
  final String avatar;
}

class AppPersonChoiceGrid extends StatelessWidget {
  const AppPersonChoiceGrid({
    super.key,
    required this.items,
    this.selectedIds = const {},
    this.selectedId,
    this.onToggle,
    this.onSelect,
    this.minTileWidth = 148,
  });

  final List<AppPersonChoiceItem> items;
  final Set<String> selectedIds;
  final String? selectedId;
  final void Function(String id, bool selected)? onToggle;
  final ValueChanged<String>? onSelect;
  final double minTileWidth;

  bool get _singleSelection => onSelect != null;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final columns = constraints.maxWidth >= minTileWidth * 2 + spacing
            ? 2
            : 1;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items.map((item) {
            final selected = _singleSelection
                ? selectedId == item.id
                : selectedIds.contains(item.id);
            return SizedBox(
              width: tileWidth,
              child: _PersonChoiceTile(
                item: item,
                selected: selected,
                singleSelection: _singleSelection,
                onTap: () {
                  if (_singleSelection) {
                    onSelect?.call(item.id);
                    return;
                  }
                  onToggle?.call(item.id, !selected);
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class AppLedgerPeopleChips extends StatelessWidget {
  const AppLedgerPeopleChips({
    super.key,
    required this.sharedMembers,
    required this.localManualPeople,
    this.peopleById = const {},
    this.singleLine = false,
  });

  final List<LedgerMemberSummary> sharedMembers;
  final List<Person> localManualPeople;
  final Map<String, Person> peopleById;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final chips = [
      ...sharedMembers.map((member) {
        final localPerson = _localPersonForMember(member);
        final name = _displayNameForMember(member, localPerson);
        final avatar = _displayAvatarForMember(member, localPerson);
        return _LedgerPersonChip(
          avatar: avatar,
          name: name,
          tooltip: '$name${_roleLabel(member.role)} · 共享成员',
          isShared: true,
        );
      }),
      ...localManualPeople.map((person) {
        return _LedgerPersonChip(
          avatar: person.avatar,
          name: person.name,
          tooltip: person.name,
        );
      }),
    ];

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    if (singleLine) {
      return SizedBox(
        height: 38,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          child: Row(
            children: [
              for (var index = 0; index < chips.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                chips[index],
              ],
            ],
          ),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  String _roleLabel(String? role) {
    return switch (role) {
      'owner' => ' · 所有者',
      'admin' => ' · 管理员',
      'editor' => ' · 可记账',
      'viewer' => ' · 查看',
      _ => '',
    };
  }

  Person? _localPersonForMember(LedgerMemberSummary member) {
    final userUuid = member.userUuid;
    if (userUuid != null && userUuid.isNotEmpty) {
      final person = peopleById[userUuid];
      if (person != null && !person.isDeleted) {
        return person;
      }
    }

    final person = peopleById[member.uuid];
    if (person == null || person.isDeleted) {
      return null;
    }
    return person;
  }

  String _displayNameForMember(LedgerMemberSummary member, Person? person) {
    final localName = person?.name.trim();
    if (localName != null && localName.isNotEmpty) {
      return localName;
    }
    return member.displayName;
  }

  String _displayAvatarForMember(LedgerMemberSummary member, Person? person) {
    final localAvatar = person?.avatar.trim();
    if (localAvatar != null && localAvatar.isNotEmpty) {
      return localAvatar;
    }
    return member.displayAvatar;
  }
}

class _LedgerPersonChip extends StatelessWidget {
  const _LedgerPersonChip({
    required this.avatar,
    required this.name,
    required this.tooltip,
    this.isShared = false,
  });

  final String avatar;
  final String name;
  final String tooltip;
  final bool isShared;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 156),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isShared
              ? AppTheme.successColor.withValues(alpha: 0.08)
              : colorScheme.surfaceContainerHigh.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isShared
                ? AppTheme.successColor.withValues(alpha: 0.72)
                : colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: colorScheme.surfaceContainerHighest,
              child: Text(avatar, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSettlementTile extends StatelessWidget {
  const AppSettlementTile({
    super.key,
    required this.fromAvatar,
    required this.fromName,
    required this.toAvatar,
    required this.toName,
    required this.amount,
  });

  final String fromAvatar;
  final String fromName;
  final String toAvatar;
  final String toName;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SettlementPerson(
                    avatar: fromAvatar,
                    name: fromName,
                    alignment: CrossAxisAlignment.start,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: _SettlementPerson(
                    avatar: toAvatar,
                    name: toName,
                    alignment: CrossAxisAlignment.end,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(
                    '应付金额',
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        amount,
                        maxLines: 1,
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
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

class _SettlementPerson extends StatelessWidget {
  const _SettlementPerson({
    required this.avatar,
    required this.name,
    required this.alignment,
    this.textAlign = TextAlign.left,
  });

  final String avatar;
  final String name;
  final CrossAxisAlignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: colorScheme.surfaceContainerHigh,
          child: Text(avatar, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _PersonChoiceTile extends StatelessWidget {
  const _PersonChoiceTile({
    required this.item,
    required this.selected,
    required this.singleSelection,
    required this.onTap,
  });

  final AppPersonChoiceItem item;
  final bool selected;
  final bool singleSelection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.52);

    return _AnimatedTapSurface(
      key: ValueKey('person-choice-tile-${item.id}'),
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.12)
          : colorScheme.surfaceContainerHigh.withValues(alpha: 0.52),
      borderRadius: 16,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: selected
                  ? colorScheme.primary.withValues(alpha: 0.13)
                  : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
              child: Text(
                item.avatar,
                style: TextStyle(
                  fontSize: 17,
                  color: selected ? null : mutedColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? colorScheme.primary : mutedColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              child: selected
                  ? Icon(
                      singleSelection
                          ? Icons.radio_button_checked_rounded
                          : Icons.check_rounded,
                      size: 15,
                      color: colorScheme.onPrimary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class AppTransactionTile extends StatelessWidget {
  const AppTransactionTile({
    super.key,
    required this.category,
    required this.date,
    required this.people,
    required this.amount,
    required this.isExpense,
    this.convertedAmount,
    this.note,
    this.createdByText,
    this.createdByAvatar,
    this.leading,
    this.selected = false,
    this.syncStatus,
    this.syncError,
    this.compactSyncStatus = false,
    this.onTap,
    this.onLongPress,
  });

  final String category;
  final String date;
  final String people;
  final String amount;
  final bool isExpense;
  final String? convertedAmount;
  final String? note;
  final String? createdByText;
  final String? createdByAvatar;
  final Widget? leading;
  final bool selected;
  final TransactionSyncStatus? syncStatus;
  final String? syncError;
  final bool compactSyncStatus;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final amountColor = isExpense ? colorScheme.error : colorScheme.primary;
    final hasNote = note != null && note!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _AnimatedTapSurface(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.58)
            : colorScheme.surfaceContainerLowest,
        borderRadius: 18,
        borderSide: BorderSide(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              leading ?? _TypeBadge(isExpense: isExpense, color: amountColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        if (people.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              people,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            date,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        if (syncStatus != null) ...[
                          const SizedBox(width: 8),
                          _TransactionSyncChip(
                            status: syncStatus!,
                            errorText: syncError,
                            compact: compactSyncStatus,
                          ),
                        ],
                      ],
                    ),
                    if (hasNote) ...[
                      const SizedBox(height: 4),
                      Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (createdByText != null && createdByText!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (createdByAvatar != null &&
                              createdByAvatar!.isNotEmpty) ...[
                            Text(
                              createdByAvatar!,
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(width: 4),
                          ] else ...[
                            Icon(
                              Icons.person_outline_rounded,
                              size: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              '由 $createdByText 添加',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        amount,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (convertedAmount != null &&
                        convertedAmount!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        convertedAmount!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum TransactionSyncStatus { pending, failed }

class _TransactionSyncChip extends StatelessWidget {
  const _TransactionSyncChip({
    required this.status,
    this.errorText,
    this.compact = false,
  });

  final TransactionSyncStatus status;
  final String? errorText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = status == TransactionSyncStatus.failed;
    final color = failed ? colorScheme.error : colorScheme.tertiary;

    return Tooltip(
      message: failed
          ? '同步失败，${FriendlyError.syncMessage(errorText)}'
          : '待同步，联网后会自动上传',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed ? Icons.error_outline_rounded : Icons.cloud_sync_outlined,
              size: 12,
              color: color,
            ),
            if (!compact) ...[
              const SizedBox(width: 3),
              Text(
                failed ? '失败' : '待同步',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimatedTapSurface extends StatefulWidget {
  const _AnimatedTapSurface({
    super.key,
    required this.child,
    required this.color,
    required this.borderRadius,
    this.borderSide,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final Color color;
  final double borderRadius;
  final BorderSide? borderSide;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_AnimatedTapSurface> createState() => _AnimatedTapSurfaceState();
}

class _AnimatedTapSurfaceState extends State<_AnimatedTapSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      child: AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: radius,
          border: widget.borderSide == null
              ? null
              : Border.all(
                  color: widget.borderSide!.color,
                  width: widget.borderSide!.width,
                ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (pressed) {
              if (_pressed != pressed) setState(() => _pressed = pressed);
            },
            borderRadius: radius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.isExpense, required this.color});

  final bool isExpense;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.standard,
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Icon(
        isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        size: 20,
        color: color,
      ),
    );
  }
}
