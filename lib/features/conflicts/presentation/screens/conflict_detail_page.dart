import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/models/conflict_record.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/services/conflict_coordinator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';

typedef KeepLocalConflict =
    Future<ConflictResolutionOutcome> Function(String id);
typedef UseRemoteConflict = Future<void> Function(String id);
typedef LoadLatestConflict = Future<ConflictRecord?> Function(String id);
typedef LoadNextConflict = Future<ConflictRecord?> Function();

class ConflictDetailPage extends ConsumerStatefulWidget {
  const ConflictDetailPage({
    super.key,
    required this.record,
    this.keepLocal,
    this.useRemote,
    this.loadLatest,
    this.loadNext,
  });

  final ConflictRecord record;
  final KeepLocalConflict? keepLocal;
  final UseRemoteConflict? useRemote;
  final LoadLatestConflict? loadLatest;
  final LoadNextConflict? loadNext;

  @override
  ConsumerState<ConflictDetailPage> createState() => _ConflictDetailPageState();
}

class _ConflictDetailPageState extends ConsumerState<ConflictDetailPage> {
  late ConflictRecord _record;
  bool _showIdentical = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
  }

  @override
  void didUpdateWidget(covariant ConflictDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.record, widget.record)) {
      _record = widget.record;
      _showIdentical = false;
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(cachedPeopleProvider).value ?? const [];
    final identityLabels = <String, String>{};
    for (final person in people) {
      if (person.isDeleted) continue;
      final label = '${person.avatar} ${person.name}'.trim();
      identityLabels[person.uuid] = label;
      identityLabels[person.remoteSyncUuid] = label;
      final linkedUserUuid = person.linkedUserUuid?.trim();
      if (linkedUserUuid != null && linkedUserUuid.isNotEmpty) {
        identityLabels[linkedUserUuid] = label;
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text('${_entityLabel(_record.entityType)}冲突')),
      body: ConflictDetailContent(
        record: _record,
        identityLabels: identityLabels,
        showIdentical: _showIdentical,
        onToggleIdentical: () {
          setState(() => _showIdentical = !_showIdentical);
        },
      ),
      bottomNavigationBar: ConflictResolutionActions(
        busy: _busy,
        onUseRemote: _useRemote,
        onKeepLocal: _keepLocal,
      ),
    );
  }

  Future<void> _useRemote() async {
    if (_busy) return;
    if (_record.remoteDeleted) {
      final confirmed = await _confirmDestructive(
        title: '使用云端删除结果？',
        message: '本机中的这条数据也会标记为已删除，之后不再参与记账和统计。',
        actionLabel: '使用云端删除结果',
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final action =
          widget.useRemote ?? ref.read(conflictCoordinatorProvider).useRemote;
      await action(_record.id);
      _invalidateConflictState();
      if (!mounted) return;
      AppNotice.success(context, '已使用云端版本');
      await _advanceOrClose();
    } catch (error) {
      if (!mounted) return;
      await _reloadLatest();
      if (!mounted) return;
      AppNotice.error(
        context,
        FriendlyError.message(error, fallback: '暂时无法使用云端版本，请稍后重试。'),
      );
      setState(() => _busy = false);
    }
  }

  Future<void> _keepLocal() async {
    if (_busy) return;
    final confirmation = _keepLocalConfirmation();
    if (confirmation != null) {
      final confirmed = await _confirmDestructive(
        title: confirmation.title,
        message: confirmation.message,
        actionLabel: confirmation.actionLabel,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() => _busy = true);
    final action =
        widget.keepLocal ?? ref.read(conflictCoordinatorProvider).keepLocal;
    final ConflictResolutionOutcome outcome;
    try {
      outcome = await action(_record.id);
    } catch (error) {
      if (!mounted) return;
      AppNotice.error(
        context,
        FriendlyError.message(error, fallback: '暂时无法保留本机版本，请稍后重试。'),
      );
      setState(() => _busy = false);
      return;
    }

    _invalidateConflictState();
    if (!mounted) return;
    switch (outcome) {
      case ConflictResolutionOutcome.resolved:
        AppNotice.success(context, '已保留本机版本');
        await _advanceOrClose();
      case ConflictResolutionOutcome.queued:
        AppNotice.info(context, '已记录本机选择，联网后会自动提交');
        await _advanceOrClose();
      case ConflictResolutionOutcome.requiresReview:
        await _reloadLatest();
        if (!mounted) return;
        setState(() => _busy = false);
        AppNotice.info(context, '云端版本又有变化，请重新确认。');
      case ConflictResolutionOutcome.failed:
        await _reloadLatest();
        if (!mounted) return;
        setState(() => _busy = false);
        AppNotice.error(
          context,
          FriendlyError.message(_record.error, fallback: '暂时无法保留本机版本，请稍后重试。'),
        );
    }
  }

  _DestructiveConfirmation? _keepLocalConfirmation() {
    if (_record.operation == ConflictOperation.delete) {
      return const _DestructiveConfirmation(
        title: '继续删除云端数据？',
        message: '云端已有更新。继续后会以最新云端版本再次提交删除。',
        actionLabel: '确认删除',
      );
    }
    if (_record.remoteDeleted) {
      return const _DestructiveConfirmation(
        title: '恢复云端数据？',
        message: '云端记录已删除。继续后会用本机内容覆盖删除状态并恢复该数据。',
        actionLabel: '覆盖云端并恢复',
      );
    }
    return null;
  }

  Future<bool> _confirmDestructive({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _reloadLatest() async {
    final load =
        widget.loadLatest ??
        (id) async {
          final accountUuid = await ref.read(authAccountUuidProvider.future);
          if (accountUuid == null || accountUuid.isEmpty) return null;
          return ref
              .read(conflictStoreProvider)
              .findById(id, accountUuid: accountUuid);
        };
    final latest = await load(_record.id);
    if (latest != null && mounted) {
      setState(() => _record = latest);
    }
  }

  Future<void> _advanceOrClose() async {
    final next = await (widget.loadNext ?? _loadNextFromStore)();
    if (!mounted) return;
    if (next == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _record = next;
      _showIdentical = false;
      _busy = false;
    });
  }

  Future<ConflictRecord?> _loadNextFromStore() async {
    final accountUuid = await ref.read(tokenStoreProvider).readAccountUuid();
    if (accountUuid == null || accountUuid.isEmpty) return null;
    final records = await ref
        .read(conflictStoreProvider)
        .readAll(accountUuid: accountUuid);
    final candidates =
        records
            .where(
              (record) =>
                  record.id != _record.id &&
                  record.state != ConflictState.queuedLocal &&
                  record.state != ConflictState.resolving,
            )
            .toList()
          ..sort((left, right) => left.detectedAt.compareTo(right.detectedAt));
    return candidates.firstOrNull;
  }

  void _invalidateConflictState() {
    ref.invalidate(conflictRecordsProvider);
    ref.invalidate(syncOverviewProvider);
  }
}

class ConflictDetailContent extends StatelessWidget {
  const ConflictDetailContent({
    super.key,
    required this.record,
    this.identityLabels = const {},
    required this.showIdentical,
    required this.onToggleIdentical,
  });

  final ConflictRecord record;
  final Map<String, String> identityLabels;
  final bool showIdentical;
  final VoidCallback onToggleIdentical;

  @override
  Widget build(BuildContext context) {
    final comparisons = _comparisons(record, identityLabels);
    final changed = comparisons.where((field) => !field.identical).toList();
    final identical = comparisons.where((field) => field.identical).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pagePadding,
        12,
        AppTheme.pagePadding,
        32,
      ),
      children: [
        _ConflictSummary(record: record),
        if (record.state == ConflictState.queuedLocal ||
            record.state == ConflictState.failed) ...[
          const SizedBox(height: 12),
          _ConflictStateNotice(record: record),
        ],
        const SizedBox(height: 18),
        Text(
          changed.isEmpty ? '版本差异' : '不同字段 ${changed.length} 项',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (changed.isEmpty)
          const AppSectionCard(child: Text('业务字段内容相同，但云端版本已经变化。仍需选择要采用的版本。'))
        else
          for (final field in changed) ...[
            _FieldComparisonCard(field: field, changed: true),
            const SizedBox(height: 10),
          ],
        if (identical.isNotEmpty) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onToggleIdentical,
              icon: Icon(
                showIdentical
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                showIdentical ? '收起相同字段' : '查看相同字段 (${identical.length})',
              ),
            ),
          ),
          if (showIdentical) ...[
            const SizedBox(height: 4),
            for (final field in identical) ...[
              _FieldComparisonCard(field: field, changed: false),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ],
    );
  }
}

class ConflictResolutionActions extends StatelessWidget {
  const ConflictResolutionActions({
    super.key,
    required this.busy,
    required this.onUseRemote,
    required this.onKeepLocal,
  });

  final bool busy;
  final VoidCallback onUseRemote;
  final VoidCallback onKeepLocal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppTheme.pagePadding,
          10,
          AppTheme.pagePadding,
          10,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.58),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onUseRemote,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('使用云端版本'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy ? null : onKeepLocal,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.phone_iphone_rounded),
                  label: Text(busy ? '正在处理' : '保留本机版本'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConflictSummary extends StatelessWidget {
  const _ConflictSummary({required this.record});

  final ConflictRecord record;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = record.remoteDeleted
        ? '云端记录已经删除。你可以恢复本机内容，或让本机采用云端删除结果。'
        : record.operation == ConflictOperation.delete
        ? '本机准备删除，但云端已有更新。请确认是继续删除，还是保留云端内容。'
        : '本机和云端都发生了变化。请比较不同字段后，明确选择一个版本。';
    return AppSectionCard(
      color: colorScheme.primaryContainer.withValues(alpha: 0.36),
      borderColor: colorScheme.primary.withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.compare_arrows_rounded,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '需要你的选择',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictStateNotice extends StatelessWidget {
  const _ConflictStateNotice({required this.record});

  final ConflictRecord record;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = record.state == ConflictState.failed;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: failed
            ? colorScheme.errorContainer.withValues(alpha: 0.48)
            : colorScheme.tertiaryContainer.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline_rounded : Icons.cloud_off_outlined,
            color: failed
                ? colorScheme.onErrorContainer
                : colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failed
                  ? FriendlyError.message(
                      record.error,
                      fallback: '上次处理失败，请重新选择或稍后重试。',
                    )
                  : '已选择保留本机版本，等待联网后提交。',
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldComparisonCard extends StatelessWidget {
  const _FieldComparisonCard({required this.field, required this.changed});

  final _FieldComparison field;
  final bool changed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppSectionCard(
      color: changed
          ? colorScheme.primaryContainer.withValues(alpha: 0.26)
          : colorScheme.surfaceContainerLowest,
      borderColor: changed ? colorScheme.primary.withValues(alpha: 0.16) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (changed)
                Text(
                  '有差异',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _VersionValue(label: '本机版本', value: field.localValue),
          const SizedBox(height: 9),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 9),
          _VersionValue(label: '云端版本', value: field.remoteValue),
        ],
      ),
    );
  }
}

class _VersionValue extends StatelessWidget {
  const _VersionValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _FieldDescriptor {
  const _FieldDescriptor(this.key, this.label);

  final String key;
  final String label;
}

class _FieldComparison {
  const _FieldComparison({
    required this.label,
    required this.localValue,
    required this.remoteValue,
    required this.identical,
  });

  final String label;
  final String localValue;
  final String remoteValue;
  final bool identical;
}

class _DestructiveConfirmation {
  const _DestructiveConfirmation({
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  final String title;
  final String message;
  final String actionLabel;
}

List<_FieldComparison> _comparisons(
  ConflictRecord record,
  Map<String, String> identityLabels,
) {
  return [
    for (final descriptor in _descriptors(record.entityType))
      _comparison(record, descriptor, identityLabels),
  ];
}

_FieldComparison _comparison(
  ConflictRecord record,
  _FieldDescriptor descriptor,
  Map<String, String> identityLabels,
) {
  final Object? localRaw;
  final Object? remoteRaw;
  if (descriptor.key == 'deleted') {
    localRaw = record.operation == ConflictOperation.delete;
    remoteRaw = record.remoteDeleted;
  } else {
    localRaw = record.localSnapshot[descriptor.key];
    remoteRaw = record.remoteSnapshot[descriptor.key];
  }
  return _FieldComparison(
    label: descriptor.label,
    localValue: _displayValue(descriptor.key, localRaw, identityLabels),
    remoteValue: _displayValue(descriptor.key, remoteRaw, identityLabels),
    identical: _canonical(localRaw) == _canonical(remoteRaw),
  );
}

List<_FieldDescriptor> _descriptors(ConflictEntityType type) {
  return switch (type) {
    ConflictEntityType.profile => const [
      _FieldDescriptor('nickname', '昵称'),
      _FieldDescriptor('avatar', '头像'),
    ],
    ConflictEntityType.ledger => const [
      _FieldDescriptor('name', '账本名称'),
      _FieldDescriptor('baseCurrencyCode', '本位币'),
      _FieldDescriptor('exchangeRateToCny', '人民币汇率'),
      _FieldDescriptor('deleted', '删除状态'),
    ],
    ConflictEntityType.member => const [
      _FieldDescriptor('nickname', '成员昵称'),
      _FieldDescriptor('role', '角色'),
      _FieldDescriptor('status', '成员状态'),
      _FieldDescriptor('deleted', '删除状态'),
    ],
    ConflictEntityType.person => const [
      _FieldDescriptor('name', '参与人名称'),
      _FieldDescriptor('avatar', '头像'),
      _FieldDescriptor('linkedUserUuid', '关联账号'),
      _FieldDescriptor('deleted', '删除状态'),
    ],
    ConflictEntityType.transaction => const [
      _FieldDescriptor('type', '类型'),
      _FieldDescriptor('amount', '金额'),
      _FieldDescriptor('currencyCode', '币种'),
      _FieldDescriptor('category', '分类'),
      _FieldDescriptor('happenedAt', '发生时间'),
      _FieldDescriptor('payerPersonUuid', '付款人'),
      _FieldDescriptor('personUuids', '分摊对象'),
      _FieldDescriptor('note', '备注'),
      _FieldDescriptor('deleted', '删除状态'),
    ],
  };
}

String _canonical(Object? value) {
  if (value == null) return '';
  if (value is num) return value.toDouble().toString();
  if (value is Iterable<dynamic>) {
    return value.map(_canonical).join('\u001f');
  }
  return value.toString().trim();
}

String _displayValue(
  String key,
  Object? value,
  Map<String, String> identityLabels,
) {
  if (key == 'deleted') return value == true ? '已删除' : '保留';
  if (value == null || value.toString().trim().isEmpty) return '未设置';
  if (key == 'payerPersonUuid' || key == 'linkedUserUuid') {
    return identityLabels[value.toString()] ??
        (key == 'linkedUserUuid' ? '账号信息不可用' : '参与人信息不可用');
  }
  if (key == 'personUuids' && value is Iterable<dynamic>) {
    final labels = value
        .map((item) => identityLabels[item.toString()] ?? '参与人信息不可用')
        .toList();
    return labels.isEmpty ? '无' : labels.join('、');
  }
  if (key == 'type') {
    return switch (value.toString()) {
      '0' => '支出',
      '1' => '收入',
      _ => value.toString(),
    };
  }
  if (key == 'role') {
    return switch (value.toString().trim().toLowerCase()) {
      'owner' => '所有者',
      'admin' => '管理员',
      'editor' => '编辑者',
      'viewer' => '查看者',
      _ => value.toString(),
    };
  }
  if (key == 'status') {
    return switch (value.toString().trim().toLowerCase()) {
      'active' => '正常',
      'invited' => '待加入',
      'disabled' => '已停用',
      _ => value.toString(),
    };
  }
  if (key == 'happenedAt') {
    final parsed = DateTime.tryParse(value.toString());
    if (parsed != null) {
      final local = parsed.toLocal();
      final month = local.month.toString().padLeft(2, '0');
      final day = local.day.toString().padLeft(2, '0');
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      return '${local.year}-$month-$day $hour:$minute';
    }
  }
  if (value is Iterable<dynamic>) {
    final items = value.map((item) => item.toString()).toList();
    return items.isEmpty ? '无' : items.join('、');
  }
  if (value is num && value.toDouble() == value.toInt()) {
    return value.toInt().toString();
  }
  return value.toString();
}

String _entityLabel(ConflictEntityType type) {
  return switch (type) {
    ConflictEntityType.profile => '账户资料',
    ConflictEntityType.ledger => '账本',
    ConflictEntityType.member => '成员',
    ConflictEntityType.person => '参与人',
    ConflictEntityType.transaction => '流水',
  };
}
