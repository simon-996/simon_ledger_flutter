import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/models/conflict_record.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_components.dart';

class ConflictCenterPage extends ConsumerWidget {
  const ConflictCenterPage({super.key, this.onRecordTap});

  final ValueChanged<ConflictRecord>? onRecordTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(conflictRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('数据冲突')),
      body: recordsAsync.when(
        loading: () => const AppLoadingState(
          title: '正在读取冲突数据',
          message: '整理需要逐项确认的本地和云端版本',
          icon: Icons.compare_arrows_rounded,
        ),
        error: (error, stackTrace) => AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: '暂时无法读取冲突数据',
          message: FriendlyError.message(error, fallback: '本地数据仍然安全，请稍后重试。'),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(conflictRecordsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新读取'),
          ),
        ),
        data: (records) {
          if (records.isEmpty) {
            return const AppEmptyState(
              icon: Icons.cloud_done_outlined,
              title: '没有待确认的数据',
              message: '检测到版本差异时，会在这里逐项确认。',
            );
          }

          final names = ref
              .watch(conflictLedgerNamesProvider)
              .maybeWhen(
                data: (value) => value,
                orElse: () => const <String, String>{},
              );
          return ConflictCenterContent(
            records: records,
            ledgerNames: names,
            onRecordTap: onRecordTap,
          );
        },
      ),
    );
  }
}

class ConflictCenterContent extends StatelessWidget {
  const ConflictCenterContent({
    super.key,
    required this.records,
    required this.ledgerNames,
    this.onRecordTap,
  });

  final List<ConflictRecord> records;
  final Map<String, String> ledgerNames;
  final ValueChanged<ConflictRecord>? onRecordTap;

  @override
  Widget build(BuildContext context) {
    final sorted = [...records]
      ..sort((left, right) => left.detectedAt.compareTo(right.detectedAt));
    final accountRecords = sorted
        .where((record) => record.entityType == ConflictEntityType.profile)
        .toList();
    final ledgerGroups = <String, List<ConflictRecord>>{};
    for (final record in sorted) {
      if (record.entityType == ConflictEntityType.profile) continue;
      final ledgerUuid = record.ledgerUuid?.trim();
      final key = ledgerUuid == null || ledgerUuid.isEmpty
          ? _ungroupedLedgerKey
          : ledgerUuid;
      ledgerGroups.putIfAbsent(key, () => []).add(record);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pagePadding,
        12,
        AppTheme.pagePadding,
        32,
      ),
      children: [
        Text(
          '逐项选择保留云端版本或本地版本。处理前不会覆盖你的本地数据。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (accountRecords.isNotEmpty) ...[
          const SizedBox(height: 18),
          _ConflictGroupCard(
            title: '账户资料',
            records: accountRecords,
            onRecordTap: onRecordTap,
          ),
        ],
        for (final entry in ledgerGroups.entries) ...[
          const SizedBox(height: 18),
          _ConflictGroupCard(
            title: entry.key == _ungroupedLedgerKey
                ? '其他数据'
                : ledgerNames[entry.key] ?? '已移除的账本',
            records: entry.value,
            onRecordTap: onRecordTap,
          ),
        ],
      ],
    );
  }
}

class _ConflictGroupCard extends StatelessWidget {
  const _ConflictGroupCard({
    required this.title,
    required this.records,
    required this.onRecordTap,
  });

  final String title;
  final List<ConflictRecord> records;
  final ValueChanged<ConflictRecord>? onRecordTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppAnimatedEntry(
      child: AppSectionCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${records.length} 项',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            for (var index = 0; index < records.length; index++) ...[
              _ConflictRecordTile(
                record: records[index],
                onTap: onRecordTap == null
                    ? null
                    : () => onRecordTap!(records[index]),
              ),
              if (index < records.length - 1)
                Divider(
                  height: 1,
                  indent: 58,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.64),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConflictRecordTile extends StatelessWidget {
  const _ConflictRecordTile({required this.record, this.onTap});

  final ConflictRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          _entityIcon(record.entityType),
          size: 20,
          color: colorScheme.onTertiaryContainer,
        ),
      ),
      title: Text(
        _recordTitle(record),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${_operationLabel(record.operation)} · ${_detectedAtLabel(record.detectedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _stateLabel(record.state),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: record.state == ConflictState.failed
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.54),
          ),
        ],
      ),
    );
  }
}

const _ungroupedLedgerKey = '__ungrouped__';

String _recordTitle(ConflictRecord record) {
  final label = switch (record.entityType) {
    ConflictEntityType.profile => '账户资料',
    ConflictEntityType.ledger => '账本设置',
    ConflictEntityType.member => '成员权限',
    ConflictEntityType.person => '参与人',
    ConflictEntityType.transaction => '流水',
  };
  final detail = switch (record.entityType) {
    ConflictEntityType.profile => null,
    ConflictEntityType.ledger => _firstText(record.localSnapshot, const [
      'name',
    ]),
    ConflictEntityType.member => _firstText(record.localSnapshot, const [
      'nickname',
      'name',
      'role',
    ]),
    ConflictEntityType.person => _firstText(record.localSnapshot, const [
      'name',
      'nickname',
    ]),
    ConflictEntityType.transaction => _firstText(record.localSnapshot, const [
      'category',
      'description',
    ]),
  };
  return detail == null ? label : '$label · $detail';
}

String? _firstText(Map<String, Object?> snapshot, List<String> keys) {
  for (final key in keys) {
    final value = snapshot[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

IconData _entityIcon(ConflictEntityType type) {
  return switch (type) {
    ConflictEntityType.profile => Icons.account_circle_outlined,
    ConflictEntityType.ledger => Icons.book_outlined,
    ConflictEntityType.member => Icons.manage_accounts_outlined,
    ConflictEntityType.person => Icons.person_outline_rounded,
    ConflictEntityType.transaction => Icons.receipt_long_outlined,
  };
}

String _operationLabel(ConflictOperation operation) {
  return switch (operation) {
    ConflictOperation.update => '编辑冲突',
    ConflictOperation.delete => '删除冲突',
    ConflictOperation.restore => '恢复冲突',
  };
}

String _stateLabel(ConflictState state) {
  return switch (state) {
    ConflictState.unresolved => '待确认',
    ConflictState.queuedLocal => '等待联网',
    ConflictState.resolving => '处理中',
    ConflictState.failed => '处理失败',
  };
}

String _detectedAtLabel(DateTime detectedAt) {
  final local = detectedAt.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}
