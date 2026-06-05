import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/avatar_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/repositories/invite_repository.dart';
import '../../../../core/services/invite_link_service.dart';
import '../../../../core/widgets/app_components.dart';
import '../../presentation/providers/ledger_provider.dart';
import '../../presentation/providers/ledger_stats_provider.dart';

Future<void> showLedgerInviteShareSheet({
  required BuildContext context,
  required String ledgerUuid,
  LedgerInvite? initialInvite,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => LedgerInviteShareSheet(
      ledgerUuid: ledgerUuid,
      initialInvite: initialInvite,
    ),
  );
}

class LedgerInviteShareSheet extends ConsumerStatefulWidget {
  const LedgerInviteShareSheet({
    super.key,
    required this.ledgerUuid,
    this.initialInvite,
    this.onRegenerate,
  });

  final String ledgerUuid;
  final LedgerInvite? initialInvite;
  final Future<LedgerInvite> Function(int days, int maxUses)? onRegenerate;

  @override
  ConsumerState<LedgerInviteShareSheet> createState() =>
      _LedgerInviteShareSheetState();
}

class _LedgerInviteShareSheetState
    extends ConsumerState<LedgerInviteShareSheet> {
  static const _dayOptions = [1, 3, 5, 7];
  static const _maxUseLimit = 99;

  late LedgerInvite? _invite;
  late bool _configuring;
  int _days = 1;
  int _maxUses = 5;
  bool _generating = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _invite = widget.initialInvite;
    _configuring = widget.initialInvite == null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _configuring
                    ? _buildConfigView(context, colorScheme)
                    : _buildShareView(context, colorScheme, _invite!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildShareView(
    BuildContext context,
    ColorScheme colorScheme,
    LedgerInvite invite,
  ) {
    final text = InviteLinks.shareText(
      ledgerName: invite.ledgerName,
      code: invite.code,
    );
    return [
      _SheetHeader(
        icon: Icons.ios_share_rounded,
        title: '邀请好友加入',
        subtitle: invite.ledgerName,
        trailing: TextButton(
          onPressed: _generating
              ? null
              : () => setState(() {
                  _configuring = true;
                  _errorText = null;
                }),
          child: const Text('重新生成'),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '邀请码',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              invite.code,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _inviteStatusText(invite),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        onPressed: () => _copy(
          context,
          invite.code,
          InviteLinks.urlForCode(invite.code),
          '邀请链接已复制',
        ),
        icon: const Icon(Icons.link_rounded),
        label: const Text('复制邀请链接'),
      ),
      const SizedBox(height: 8),
      _InviteCopyActions(
        onCopyCode: () => _copy(context, invite.code, invite.code, '邀请码已复制'),
        onCopyText: () => _copy(context, invite.code, text, '邀请文本已复制'),
      ),
    ];
  }

  List<Widget> _buildConfigView(BuildContext context, ColorScheme colorScheme) {
    final hasExistingInvite = _invite != null;
    return [
      _SheetHeader(
        icon: Icons.autorenew_rounded,
        title: hasExistingInvite ? '重新生成邀请码' : '生成邀请码',
        subtitle: hasExistingInvite ? '新邀请码生成后，旧邀请码会失效。' : '设置有效期和可使用次数。',
      ),
      const SizedBox(height: 16),
      Text(
        '有效期',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      SegmentedButton<int>(
        segments: [
          for (final day in _dayOptions)
            ButtonSegment<int>(value: day, label: Text('$day 天')),
        ],
        selected: {_days},
        onSelectionChanged: _generating
            ? null
            : (values) => setState(() => _days = values.single),
      ),
      const SizedBox(height: 16),
      Text(
        '使用次数',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: _generating || _maxUses <= 1
                  ? null
                  : () => setState(() => _maxUses -= 1),
              icon: const Icon(Icons.remove_rounded),
              tooltip: '减少次数',
            ),
            Expanded(
              child: Text(
                '$_maxUses 次',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton.filledTonal(
              onPressed: _generating || _maxUses >= _maxUseLimit
                  ? null
                  : () => setState(() => _maxUses += 1),
              icon: const Icon(Icons.add_rounded),
              tooltip: '增加次数',
            ),
          ],
        ),
      ),
      if (_errorText != null) ...[
        const SizedBox(height: 12),
        _InviteMessage(
          icon: Icons.info_outline_rounded,
          message: _errorText!,
          color: colorScheme.error,
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          if (hasExistingInvite) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _generating
                    ? null
                    : () => setState(() {
                        _configuring = false;
                        _errorText = null;
                      }),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: hasExistingInvite ? 2 : 1,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: _generating ? null : _regenerate,
              icon: _generating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_generating ? '生成中' : '生成邀请码'),
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _copy(
    BuildContext context,
    String code,
    String text,
    String notice,
  ) async {
    InviteClipboardMemory.ignore(code);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppNotice.success(context, notice);
  }

  Future<void> _regenerate() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _errorText = null;
    });
    try {
      final invite =
          await (widget.onRegenerate?.call(_days, _maxUses) ??
              ref
                  .read(inviteRepositoryProvider)
                  .regenerateInvite(
                    widget.ledgerUuid,
                    days: _days,
                    maxUses: _maxUses,
                  ));
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _configuring = false;
        _generating = false;
      });
      AppNotice.success(context, '邀请码已生成');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _errorText = FriendlyError.message(error, fallback: '生成邀请码失败，请稍后重试。');
      });
    }
  }

  String _inviteStatusText(LedgerInvite invite) {
    final remainingUses = invite.remainingUses;
    final usage = remainingUses == null ? '不限次数' : '剩余 $remainingUses 次';
    final duration = invite.expiresAt.difference(DateTime.now());
    final expires = duration.isNegative
        ? '已过期'
        : duration.inHours < 24
        ? '今天过期'
        : '${(duration.inHours / 24).ceil()} 天后过期';
    return '$usage · $expires';
  }
}

class _InviteCopyActions extends StatelessWidget {
  const _InviteCopyActions({
    required this.onCopyCode,
    required this.onCopyText,
  });

  final VoidCallback onCopyCode;
  final VoidCallback onCopyText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final buttonStyle = OutlinedButton.styleFrom(
      backgroundColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.62),
      side: BorderSide.none,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final codeButton = OutlinedButton.icon(
      style: buttonStyle,
      onPressed: onCopyCode,
      icon: const Icon(Icons.key_rounded, size: 18),
      label: const _NoWrapButtonLabel('复制邀请码'),
    );
    final textButton = OutlinedButton.icon(
      style: buttonStyle,
      onPressed: onCopyText,
      icon: const Icon(Icons.copy_rounded, size: 18),
      label: const _NoWrapButtonLabel('复制全部信息'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [codeButton, const SizedBox(height: 8), textButton],
          );
        }
        return Row(
          children: [
            Expanded(child: codeButton),
            const SizedBox(width: 8),
            Expanded(child: textButton),
          ],
        );
      },
    );
  }
}

class _NoWrapButtonLabel extends StatelessWidget {
  const _NoWrapButtonLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class LedgerInviteJoinPage extends ConsumerStatefulWidget {
  const LedgerInviteJoinPage({
    super.key,
    required this.code,
    this.initialInvite,
    this.onJoin,
  });

  final String code;
  final LedgerInvite? initialInvite;
  final Future<void> Function()? onJoin;

  @override
  ConsumerState<LedgerInviteJoinPage> createState() =>
      _LedgerInviteJoinPageState();
}

class _LedgerInviteJoinPageState extends ConsumerState<LedgerInviteJoinPage> {
  LedgerInvite? _invite;
  String? _loadErrorText;
  bool _loading = false;
  bool _joining = false;
  String? _joinErrorText;

  @override
  void initState() {
    super.initState();
    _invite = widget.initialInvite;
    if (_invite == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;

    return Scaffold(
      appBar: AppBar(title: const Text('账本邀请')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _buildBody(context, invite),
          ),
        ),
      ),
      bottomNavigationBar: invite == null ? null : _buildBottomAction(invite),
    );
  }

  Widget _buildBody(BuildContext context, LedgerInvite? invite) {
    if (_loading || (invite == null && _loadErrorText == null)) {
      return const AppLoadingState(
        title: '正在读取邀请',
        message: '获取共享账本信息',
        icon: Icons.mark_email_read_outlined,
      );
    }
    if (invite == null) {
      return AppEmptyState(
        icon: Icons.link_off_rounded,
        title: '暂时无法读取邀请',
        message: _loadErrorText ?? '请稍后重试。',
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新加载'),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final unavailableReason = invite.unavailableReason;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          '确认加入共享账本',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '请核对账本信息，确认后才会加入。',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        LedgerInviteOverview(invite: invite),
        if (unavailableReason != null) ...[
          const SizedBox(height: 14),
          _InviteMessage(
            icon: Icons.error_outline_rounded,
            message: unavailableReason,
            color: colorScheme.error,
          ),
        ],
        if (_joinErrorText != null) ...[
          const SizedBox(height: 14),
          _InviteMessage(
            icon: Icons.info_outline_rounded,
            message: _joinErrorText!,
            color: colorScheme.error,
          ),
        ],
      ],
    );
  }

  Widget _buildBottomAction(LedgerInvite invite) {
    final token = ref.watch(authTokenProvider).valueOrNull;
    final isSignedIn = token != null && token.isValid;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: !invite.isUsable || _joining
              ? null
              : isSignedIn
              ? _join
              : _openLogin,
          icon: _joining
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isSignedIn ? Icons.group_add_outlined : Icons.login_rounded,
                ),
          label: Text(
            _joining
                ? '正在加入'
                : isSignedIn
                ? '确认加入'
                : '登录后加入',
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadErrorText = null;
    });
    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .preview(widget.code);
      if (!mounted) return;
      setState(() => _invite = invite);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadErrorText = FriendlyError.message(
          error,
          fallback: '读取邀请失败，请检查网络或邀请码后重试。',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openLogin() {
    AppNotice.info(context, '请先登录，完成后返回此页面继续加入');
    Navigator.of(context).pushNamed('/account');
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _joinErrorText = null;
    });
    try {
      await (widget.onJoin?.call() ??
          ref.read(inviteRepositoryProvider).join(widget.code));
      ref.invalidate(ledgerNotifierProvider);
      ref.invalidate(ledgerStatsProvider);
      ref.invalidate(syncOverviewProvider);
      if (!mounted) return;
      AppNotice.success(context, '已加入账本：${_invite?.ledgerName ?? ''}');
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      } else {
        navigator.pushReplacementNamed('/');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joinErrorText = FriendlyError.message(
          error,
          fallback: '加入账本失败，请稍后重试。',
        );
      });
    }
  }
}

class LedgerInviteOverview extends StatelessWidget {
  const LedgerInviteOverview({
    super.key,
    required this.invite,
    this.emphasizeCode = false,
  });

  final LedgerInvite invite;
  final bool emphasizeCode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final members = invite.ledgerMembers.take(8).toList();
    final hiddenMemberCount = invite.ledgerMemberCount - members.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          invite.ledgerName,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          invite.ledgerDisplayCode,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: emphasizeCode ? 16 : 12,
          ),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '邀请码',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                invite.code,
                style:
                    (emphasizeCode
                            ? Theme.of(context).textTheme.headlineMedium
                            : Theme.of(context).textTheme.titleLarge)
                        ?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InviteInfoChip(
              icon: Icons.currency_exchange_rounded,
              label: _currencyLabel(invite.ledgerBaseCurrencyCode),
            ),
            _InviteInfoChip(
              icon: Icons.people_outline_rounded,
              label: '${invite.ledgerMemberCount} 位共享成员',
            ),
            _InviteInfoChip(
              icon: Icons.edit_note_rounded,
              label: _roleLabel(invite.role),
            ),
            _InviteInfoChip(
              icon: Icons.schedule_rounded,
              label: '有效期至 ${_formatDate(invite.expiresAt)}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '当前共享成员',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (members.isEmpty)
          Text(
            '成员信息将在加入后同步',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in members) _InviteMemberChip(member: member),
              if (hiddenMemberCount > 0)
                Chip(label: Text('另有 $hiddenMemberCount 人')),
            ],
          ),
      ],
    );
  }

  String _currencyLabel(String code) {
    final normalized = code.trim().toUpperCase();
    final name = switch (normalized) {
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
      _ => normalized,
    };
    return name == normalized ? normalized : '$normalized $name';
  }

  String _roleLabel(String role) {
    return switch (role.trim().toLowerCase()) {
      'admin' => '可管理账本',
      'editor' => '可共同记账',
      'viewer' => '仅查看',
      _ => '共享账本',
    };
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.month} 月 ${local.day} 日';
  }
}

class _InviteInfoChip extends StatelessWidget {
  const _InviteInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InviteMemberChip extends StatelessWidget {
  const _InviteMemberChip({required this.member});

  final LedgerInviteMember member;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        child: Text(
          AvatarConfig.normalizeAvatar(member.displayAvatar),
          style: const TextStyle(fontSize: 13),
        ),
      ),
      label: Text(member.displayName),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InviteMessage extends StatelessWidget {
  const _InviteMessage({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
