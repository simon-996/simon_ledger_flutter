import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';

enum OnboardingAction { done, createLedger, account }

Future<OnboardingAction?> showOnboardingFlow(BuildContext context) {
  return showGeneralDialog<OnboardingAction>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '新用户引导',
    barrierColor: Theme.of(context).colorScheme.surface,
    transitionDuration: AppMotion.normal,
    pageBuilder: (context, animation, secondaryAnimation) {
      return const SimonOnboardingFlow();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class SimonOnboardingFlow extends StatefulWidget {
  const SimonOnboardingFlow({super.key});

  @override
  State<SimonOnboardingFlow> createState() => _SimonOnboardingFlowState();
}

class _SimonOnboardingFlowState extends State<SimonOnboardingFlow> {
  final _controller = PageController();
  int _index = 0;

  static const _steps = [
    _OnboardingStep(
      icon: Icons.account_balance_wallet_outlined,
      title: '建立你的第一本账',
      message: '先选一个基础币种，再把常一起消费的人加入进来。',
    ),
    _OnboardingStep(
      icon: Icons.receipt_long_outlined,
      title: '把每笔流水记清楚',
      message: '金额、分类、参与人会留在本地，离线时也能继续记录。',
    ),
    _OnboardingStep(
      icon: Icons.cloud_done_outlined,
      title: '需要共享时再同步',
      message: '登录后可以导入本地账本、生成邀请，并在网络恢复后自动同步。',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLast = _index == _steps.length - 1;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Simon Ledger',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  AppPressable(
                    child: TextButton(
                      onPressed: () => _finish(OnboardingAction.done),
                      child: const Text('跳过'),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    return _OnboardingStepView(
                      step: _steps[index],
                      selected: index == _index,
                    );
                  },
                ),
              ),
              _OnboardingDots(count: _steps.length, index: _index),
              const SizedBox(height: 20),
              AppPressable(
                pressedScale: 0.98,
                child: FilledButton.icon(
                  onPressed: () {
                    if (isLast) {
                      _finish(OnboardingAction.createLedger);
                    } else {
                      _controller.nextPage(
                        duration: AppMotion.normal,
                        curve: AppMotion.emphasized,
                      );
                    }
                  },
                  icon: Icon(isLast ? Icons.add_rounded : Icons.arrow_forward),
                  label: Text(isLast ? '创建账本' : '继续'),
                ),
              ),
              const SizedBox(height: 8),
              AppPressable(
                child: TextButton.icon(
                  onPressed: () => _finish(
                    isLast ? OnboardingAction.account : OnboardingAction.done,
                  ),
                  icon: Icon(
                    isLast ? Icons.login_rounded : Icons.close_rounded,
                  ),
                  label: Text(isLast ? '先登录同步' : '先自己看看'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _finish(OnboardingAction action) {
    Navigator.of(context).pop(action);
  }
}

class _OnboardingStepView extends StatelessWidget {
  const _OnboardingStepView({required this.step, required this.selected});

  final _OnboardingStep step;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedOpacity(
      duration: AppMotion.normal,
      curve: AppMotion.standard,
      opacity: selected ? 1 : 0.58,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppMotion.normal,
                curve: AppMotion.emphasized,
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
                ),
                child: Icon(step.icon, size: 58, color: colorScheme.primary),
              ),
              const SizedBox(height: 30),
              Text(
                step.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                step.message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingDots extends StatelessWidget {
  const _OnboardingDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 7),
        ],
      ],
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;
}
