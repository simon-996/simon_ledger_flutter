import 'package:flutter/material.dart';

import '../../../../core/config/avatar_config.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/repositories/invite_repository.dart';

class LedgerInviteShareDialog extends StatelessWidget {
  const LedgerInviteShareDialog({
    super.key,
    required this.invite,
    required this.onCopyCode,
    required this.onCopyText,
  });

  final LedgerInvite invite;
  final Future<void> Function() onCopyCode;
  final Future<void> Function() onCopyText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.group_add_outlined),
      title: const Text('邀请加入账本'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: LedgerInviteOverview(invite: invite, emphasizeCode: true),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        OutlinedButton.icon(
          onPressed: onCopyCode,
          icon: const Icon(Icons.key_rounded),
          label: const Text('复制邀请码'),
        ),
        FilledButton.icon(
          onPressed: onCopyText,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制邀请文本'),
        ),
      ],
    );
  }
}

class LedgerInvitePreviewSheet extends StatefulWidget {
  const LedgerInvitePreviewSheet({
    super.key,
    required this.invite,
    required this.onJoin,
  });

  final LedgerInvite invite;
  final Future<void> Function() onJoin;

  @override
  State<LedgerInvitePreviewSheet> createState() =>
      _LedgerInvitePreviewSheetState();
}

class _LedgerInvitePreviewSheetState extends State<LedgerInvitePreviewSheet> {
  bool _joining = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unavailableReason = widget.invite.unavailableReason;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('确认加入共享账本', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '请核对账本信息，确认后才会加入。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LedgerInviteOverview(invite: widget.invite),
                      if (unavailableReason != null) ...[
                        const SizedBox(height: 14),
                        _InviteMessage(
                          icon: Icons.error_outline_rounded,
                          message: unavailableReason,
                          color: colorScheme.error,
                        ),
                      ],
                      if (_errorText != null) ...[
                        const SizedBox(height: 14),
                        _InviteMessage(
                          icon: Icons.info_outline_rounded,
                          message: _errorText!,
                          color: colorScheme.error,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: !widget.invite.isUsable || _joining ? null : _join,
                icon: _joining
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add_outlined),
                label: Text(_joining ? '正在加入' : '确认加入'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _joining ? null : () => Navigator.of(context).pop(),
                child: const Text('暂不加入'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _errorText = null;
    });
    try {
      await widget.onJoin();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _errorText = FriendlyError.message(error, fallback: '加入账本失败，请稍后重试。');
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
