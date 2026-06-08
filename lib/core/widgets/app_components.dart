import 'package:flutter/material.dart';

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
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: _softShadow,
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Icon(icon, size: 38, color: colorScheme.primary),
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
    this.radius = AppTheme.radiusLarge,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final bool shadow;

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
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              borderColor ??
              colorScheme.outlineVariant.withValues(alpha: 0.58),
        ),
        boxShadow: shadow ? _softShadow : null,
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
      radius: 20,
      shadow: false,
      color: Colors.white.withValues(alpha: 0.82),
      borderColor: Colors.white.withValues(alpha: 0.58),
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
    final amountColor = AppTheme.semanticAmountColor(context, isPositive);

    return _AnimatedTapSurface(
      color: isSelected ? colorScheme.primaryContainer : Colors.white,
      borderRadius: 22,
      borderSide: BorderSide(
        width: isSelected ? 1.4 : 1,
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.5)
            : colorScheme.outlineVariant.withValues(alpha: 0.66),
      ),
      shadow: !isSelected,
      onTap: onTap,
      child: SizedBox(
        width: 96,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.62,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(avatar, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 5),
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

class AppTransactionTile extends StatelessWidget {
  const AppTransactionTile({
    super.key,
    required this.category,
    required this.date,
    required this.people,
    required this.amount,
    required this.isExpense,
    this.note,
    this.leading,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final String category;
  final String date;
  final String people;
  final String amount;
  final bool isExpense;
  final String? note;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final amountColor = isExpense ? colorScheme.error : AppTheme.successColor;
    final hasNote = note != null && note!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: _AnimatedTapSurface(
        color: selected ? colorScheme.primaryContainer : Colors.white,
        borderRadius: 22,
        borderSide: BorderSide(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.42)
              : colorScheme.outlineVariant.withValues(alpha: 0.54),
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
                    Text(
                      date,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (hasNote) ...[
                      const SizedBox(height: 4),
                      Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: FittedBox(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedTapSurface extends StatefulWidget {
  const _AnimatedTapSurface({
    required this.child,
    required this.color,
    required this.borderRadius,
    required this.borderSide,
    this.shadow = true,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final Color color;
  final double borderRadius;
  final BorderSide borderSide;
  final bool shadow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_AnimatedTapSurface> createState() => _AnimatedTapSurfaceState();
}

class _AnimatedTapSurfaceState extends State<_AnimatedTapSurface> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final scale = _pressed ? 0.982 : (_hovered && interactive ? 1.006 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        scale: scale,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: radius,
            border: Border.all(
              color: widget.borderSide.color,
              width: widget.borderSide.width,
            ),
            boxShadow: widget.shadow ? _softShadow : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onHighlightChanged: (pressed) {
                if (_pressed != pressed) setState(() => _pressed = pressed);
              },
              splashColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.06),
              highlightColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.04),
              borderRadius: radius,
              child: widget.child,
            ),
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

const List<BoxShadow> _softShadow = [
  BoxShadow(
    color: Color(0x12000000),
    blurRadius: 24,
    offset: Offset(0, 10),
  ),
  BoxShadow(color: Color(0x08FFFFFF), blurRadius: 1),
];
