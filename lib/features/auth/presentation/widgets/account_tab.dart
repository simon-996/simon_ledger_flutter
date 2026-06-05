import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/avatar_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/local_profile.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/services/cloud_import_service.dart';
import '../../../../core/services/profile_sync_service.dart';
import '../../../../core/services/sync_overview_service.dart';
import '../../../../core/services/invite_link_service.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';
import '../../../ledgers/presentation/widgets/ledger_invite_widgets.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../../../transactions/presentation/providers/transaction_provider.dart';
import '../providers/auth_provider.dart';

class AccountTab extends ConsumerWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenAsync = ref.watch(authTokenProvider);
    final userAsync = ref.watch(currentUserProvider);

    return tokenAsync.when(
      loading: () => const AppLoadingState(
        title: '正在读取账户状态',
        message: '恢复登录信息和本地资料',
        icon: Icons.account_circle_outlined,
      ),
      error: (error, stackTrace) => _AuthPanel(
        errorText: FriendlyError.message(error, fallback: '暂时无法读取登录状态，请稍后重试。'),
      ),
      data: (token) {
        final isSignedIn = token != null && token.isValid;
        if (!isSignedIn) {
          return const _AuthPanel();
        }

        final user = userAsync.valueOrNull;
        return _SignedInPanel(
          account: user?.email ?? user?.phone ?? user?.uuid,
          syncingProfile: userAsync.isLoading,
        );
      },
    );
  }
}

class _SignedInPanel extends ConsumerWidget {
  const _SignedInPanel({this.account, required this.syncingProfile});

  final String? account;
  final bool syncingProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _UnifiedProfileCard(
          isSignedIn: true,
          account: account,
          syncingProfile: syncingProfile,
        ),
        const SizedBox(height: 16),
        const _SyncCenterCard(),
        const SizedBox(height: 16),
        const _JoinInviteCard(),
        const SizedBox(height: 16),
        const _CloudImportCard(),
        const SizedBox(height: 16),
        const _AccountActionsSection(),
      ],
    );
  }
}

class _AccountActionsSection extends ConsumerWidget {
  const _AccountActionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: OutlinedButton.icon(
        onPressed: () => _confirmLogout(context, ref),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.42)),
          backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: const Text('退出登录'),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _LogoutConfirmSheet(),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      await ref.read(tokenStoreProvider).clear();
    }
    ref.invalidate(authTokenProvider);
    ref.invalidate(currentUserProvider);
    ref.invalidate(ledgerNotifierProvider);
    ref.invalidate(ledgerStatsProvider);
  }
}

class _LogoutConfirmSheet extends StatelessWidget {
  const _LogoutConfirmSheet();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '退出登录？',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              '本机数据会保留，未同步内容会在下次登录后继续处理。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                      foregroundColor: colorScheme.onError,
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('退出登录'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncCenterCard extends ConsumerStatefulWidget {
  const _SyncCenterCard();

  @override
  ConsumerState<_SyncCenterCard> createState() => _SyncCenterCardState();
}

class _SyncCenterCardState extends ConsumerState<_SyncCenterCard> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(syncOverviewProvider);
    return AppSectionCard(
      child: overview.when(
        loading: () => const _AccountInlineLoadingRow(message: '正在读取同步状态'),
        error: (error, stackTrace) =>
            Text(FriendlyError.message(error, fallback: '暂时无法读取同步状态。')),
        data: (overview) {
          return AccountSyncCenterContent(
            overview: overview,
            syncing: _syncing,
            onRefresh: _refreshOverview,
            onSync: _retry,
          );
        },
      ),
    );
  }

  Future<void> _retry() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final overviewService = ref.read(syncOverviewServiceProvider);
      final beforeSync = await overviewService.read();
      if (!mounted) return;
      if (beforeSync.pendingCount == 0) {
        AppNotice.info(context, '暂无需要同步的数据');
        return;
      }

      final synced = await ref
          .read(syncCoordinatorProvider)
          .syncAllPendingResult(force: true);
      final afterSync = await overviewService.read();
      if (!mounted) return;
      if (afterSync.failedCount > 0 || synced.hasError) {
        AppNotice.error(context, '部分数据暂时无法同步，已保存在本机，联网后会继续同步');
      } else if (afterSync.pendingCount > 0) {
        AppNotice.info(context, '部分数据仍在等待同步，联网后会自动重试');
      } else {
        AppNotice.success(context, '同步完成');
      }
    } catch (error) {
      if (!mounted) return;
      AppNotice.error(
        context,
        FriendlyError.message(error, fallback: '同步失败，请稍后重试。'),
      );
    } finally {
      ref.invalidate(syncOverviewProvider);
      ref.invalidate(ledgerNotifierProvider);
      ref.invalidate(personNotifierProvider);
      ref.invalidate(transactionNotifierProvider);
      ref.invalidate(ledgerStatsProvider);
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _refreshOverview() {
    ref.invalidate(syncOverviewProvider);
  }
}

class AccountSyncCenterContent extends StatelessWidget {
  const AccountSyncCenterContent({
    super.key,
    required this.overview,
    required this.syncing,
    required this.onRefresh,
    required this.onSync,
  });

  final SyncOverview overview;
  final bool syncing;
  final VoidCallback onRefresh;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPending = overview.pendingCount > 0;
    final hasFailures = overview.failedCount > 0;
    final statusText = hasFailures
        ? '${overview.failedCount} 项同步失败，可点击下方按钮重试'
        : hasPending
        ? '数据已保存在本机，联网后会自动同步'
        : '暂无待同步';
    final statusStyle = hasPending || hasFailures
        ? Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)
        : Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.56),
            fontWeight: FontWeight.w500,
          );
    return _AccountLoadingOverlay(
      loading: syncing,
      message: '正在同步数据',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: '同步中心',
            trailing: Icon(
              hasPending
                  ? Icons.sync_problem_rounded
                  : Icons.cloud_done_outlined,
              color: hasPending ? colorScheme.tertiary : colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SyncCountChip(label: '账本', count: overview.ledgerPendingCount),
              _SyncCountChip(label: '人员', count: overview.personPendingCount),
              _SyncCountChip(
                label: '流水',
                count: overview.transactionPendingCount,
              ),
              _SyncCountChip(
                label: '仅本地账本',
                count: overview.localOnlyLedgerCount,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(statusText, style: statusStyle),
          const SizedBox(height: 4),
          Text(
            _lastSyncText(overview.lastSuccessfulSyncAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: hasPending || hasFailures
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.52),
            ),
          ),
          if (overview.failures.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: syncing
                    ? null
                    : () => _showSyncFailures(context, overview.failures),
                icon: const Icon(Icons.error_outline_rounded),
                label: const Text('查看失败详情'),
              ),
            ),
          ],
          if (hasPending) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: syncing ? null : onSync,
              icon: const Icon(Icons.sync_rounded),
              label: Text(syncing ? '同步中' : '立即同步'),
            ),
          ],
        ],
      ),
    );
  }

  String _lastSyncText(DateTime? time) {
    if (time == null) return '尚无成功同步记录';
    final local = time.toLocal();
    final date =
        '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '上次同步 $date $clock';
  }

  Future<void> _showSyncFailures(
    BuildContext context,
    List<SyncFailureItem> failures,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Text('同步失败详情', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '数据仍保存在本机，联网后可以再次同步。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final failure in failures)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_failureIcon(failure.type)),
                  title: Text(failure.title),
                  subtitle: Text(FriendlyError.syncMessage(failure.errorText)),
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _failureIcon(SyncFailureType type) {
    return switch (type) {
      SyncFailureType.ledger => Icons.account_balance_wallet_outlined,
      SyncFailureType.person => Icons.person_outline_rounded,
      SyncFailureType.transaction => Icons.receipt_long_outlined,
    };
  }
}

class _SyncCountChip extends StatelessWidget {
  const _SyncCountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $count',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _AccountLoadingOverlay extends StatelessWidget {
  const _AccountLoadingOverlay({
    super.key,
    required this.loading,
    required this.message,
    required this.child,
  });

  final bool loading;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        AnimatedOpacity(
          duration: AppMotion.normal,
          curve: AppMotion.standard,
          opacity: loading ? 0.34 : 1,
          child: IgnorePointer(ignoring: loading, child: child),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: AppMotion.normal,
              switchInCurve: AppMotion.emphasized,
              switchOutCurve: AppMotion.standard,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.96,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: loading
                  ? ColoredBox(
                      key: ValueKey(message),
                      color: colorScheme.surface.withValues(alpha: 0.5),
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          label: message,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withValues(
                                    alpha: 0.08,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Text(
                                    message,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: colorScheme.onSurface,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('account-idle')),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountInlineLoadingRow extends StatelessWidget {
  const _AccountInlineLoadingRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
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

class _JoinInviteCard extends ConsumerStatefulWidget {
  const _JoinInviteCard();

  @override
  ConsumerState<_JoinInviteCard> createState() => _JoinInviteCardState();
}

class _JoinInviteCardState extends ConsumerState<_JoinInviteCard> {
  final _codeController = TextEditingController();
  bool _previewing = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: _AccountLoadingOverlay(
        loading: _previewing,
        message: '正在读取邀请信息',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSectionHeader(title: '加入共享账本'),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '邀请码',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              onSubmitted: (_) => _preview(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _previewing ? null : _pasteAndPreview,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('粘贴并查看'),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: _previewing ? null : _preview,
              icon: const Icon(Icons.search_rounded),
              label: Text(_previewing ? '读取中' : '查看邀请'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _preview() async {
    if (_previewing) return;
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      AppNotice.error(context, '请输入邀请码');
      return;
    }

    setState(() => _previewing = true);
    try {
      setState(() => _previewing = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => LedgerInviteJoinPage(code: code),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppNotice.error(
        context,
        FriendlyError.message(error, fallback: '读取邀请失败，请检查邀请码后重试。'),
      );
    } finally {
      if (mounted) {
        setState(() => _previewing = false);
      }
    }
  }

  Future<void> _pasteAndPreview() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final code = InviteLinks.codeFromText(data?.text ?? '');
    if (code == null) {
      AppNotice.info(context, '剪贴板中没有可识别的账本邀请');
      return;
    }
    _codeController.text = code;
    await _preview();
  }
}

class _UnifiedProfileCard extends ConsumerStatefulWidget {
  const _UnifiedProfileCard({
    required this.isSignedIn,
    this.account,
    this.syncingProfile = false,
  });

  final bool isSignedIn;
  final String? account;
  final bool syncingProfile;

  @override
  ConsumerState<_UnifiedProfileCard> createState() =>
      _UnifiedProfileCardState();
}

class _UnifiedProfileCardState extends ConsumerState<_UnifiedProfileCard> {
  int _syncingRequests = 0;
  bool _skipNextSyncedNotice = false;

  bool get _syncing => _syncingRequests > 0;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<LocalProfile>>(localProfileProvider, (
      previous,
      next,
    ) {
      final wasPending = previous?.valueOrNull?.pendingSync ?? false;
      final isPending = next.valueOrNull?.pendingSync ?? false;
      if (!widget.isSignedIn || !wasPending || isPending) {
        return;
      }

      if (_skipNextSyncedNotice) {
        _skipNextSyncedNotice = false;
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppNotice.success(context, '账户资料已同步');
      });
    });

    final profileAsync = ref.watch(localProfileProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return profileAsync.when(
      loading: () => const AppInlineLoadingCard(message: '正在加载账户资料'),
      error: (error, stackTrace) => AppSectionCard(
        child: Text(FriendlyError.message(error, fallback: '账户资料加载失败，请稍后重试。')),
      ),
      data: (profile) {
        final syncing =
            _syncing || (widget.syncingProfile && profile.pendingSync);

        return AppSectionCard(
          child: AppAnimatedSwitcher(
            child: _AccountLoadingOverlay(
              key: ValueKey(
                '${profile.normalizedNickname}-${profile.personAvatar}-${profile.pendingSync}-$syncing',
              ),
              loading: syncing,
              message: '正在同步账户资料',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _editProfile(profile),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              profile.personAvatar,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.normalizedNickname,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.account ??
                                      (widget.isSignedIn ? '已登录' : '未登录本地使用'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.66),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.38,
                            ),
                          ),
                        ],
                      ),
                      if (profile.pendingSync && !syncing) ...[
                        const SizedBox(height: 12),
                        _ProfileSyncBanner(
                          errorText: profile.syncError,
                          onRetry: widget.isSignedIn ? _retrySyncProfile : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editProfile(LocalProfile profile) async {
    final result = await showDialog<LocalProfile>(
      context: context,
      builder: (context) => _ProfileDialog(profile: profile),
    );
    if (result == null) return;

    if (widget.isSignedIn) {
      _beginSync();
    }

    try {
      final syncResult = await ref
          .read(profileSyncServiceProvider)
          .saveProfile(result, onLocalSaved: _refreshProfileDependents);
      if (!mounted) return;
      _showSyncResult(syncResult);
    } catch (error) {
      if (!mounted) return;
      AppNotice.error(
        context,
        FriendlyError.message(error, fallback: '账户资料保存失败，请稍后重试。'),
      );
    } finally {
      if (widget.isSignedIn) {
        _endSync();
      }
    }
  }

  Future<void> _retrySyncProfile() async {
    _beginSync();

    try {
      final syncResult = await ref
          .read(profileSyncServiceProvider)
          .syncPendingProfile();
      if (syncResult.status == ProfileSyncStatus.synced) {
        _skipNextSyncedNotice = true;
      }
      _refreshProfileDependents();
      if (!mounted) return;
      _showSyncResult(syncResult);
    } finally {
      _endSync();
    }
  }

  void _beginSync() {
    if (!mounted) return;
    setState(() => _syncingRequests += 1);
  }

  void _endSync() {
    if (!mounted) return;
    setState(() {
      if (_syncingRequests > 0) {
        _syncingRequests -= 1;
      }
    });
  }

  void _refreshProfileDependents() {
    ref.invalidate(localProfileProvider);
    ref.invalidate(currentUserProvider);
    ref.invalidate(personNotifierProvider);
    ref.invalidate(ledgerNotifierProvider);
    ref.invalidate(ledgerStatsProvider);
  }

  void _showSyncResult(ProfileSyncResult result) {
    switch (result.status) {
      case ProfileSyncStatus.synced:
        AppNotice.success(context, '账户资料已同步');
      case ProfileSyncStatus.queued:
        AppNotice.info(context, '账户资料已保存，联网后会继续同步');
      case ProfileSyncStatus.localOnly:
        AppNotice.success(context, '账户资料已保存');
      case ProfileSyncStatus.skipped:
        AppNotice.info(context, '暂无需要同步的资料');
      case ProfileSyncStatus.stale:
        break;
    }
  }
}

class _ProfileSyncBanner extends StatelessWidget {
  const _ProfileSyncBanner({required this.errorText, required this.onRetry});

  final String? errorText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorText == null || errorText!.isEmpty
                  ? '账户资料已在本地保存，尚未同步到云端。'
                  : '账户资料已在本地保存，尚未同步到云端，${FriendlyError.syncMessage(errorText)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.profile});

  final LocalProfile profile;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _nicknameController;
  late String _avatarIcon;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.profile.normalizedNickname,
    );
    _avatarIcon = AvatarConfig.normalizeKey(widget.profile.avatarIcon);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('账户资料'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nicknameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '昵称',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AvatarConfig.options.map((option) {
                return ChoiceChip(
                  label: Text(
                    option.avatar,
                    style: const TextStyle(fontSize: 18),
                  ),
                  showCheckmark: false,
                  selected: _avatarIcon == option.key,
                  onSelected: (_) => setState(() => _avatarIcon = option.key),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  void _submit() {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      AppNotice.error(context, '请输入昵称');
      return;
    }

    Navigator.of(
      context,
    ).pop(LocalProfile(nickname: nickname, avatarIcon: _avatarIcon));
  }
}

class _CloudImportCard extends ConsumerStatefulWidget {
  const _CloudImportCard();

  @override
  ConsumerState<_CloudImportCard> createState() => _CloudImportCardState();
}

class _CloudImportCardState extends ConsumerState<_CloudImportCard> {
  late Future<List<LocalLedgerImportCandidate>> _scanFuture;

  @override
  void initState() {
    super.initState();
    _scanFuture = _scan();
  }

  Future<List<LocalLedgerImportCandidate>> _scan() {
    return ref.read(cloudImportServiceProvider).scanLocalLedgers();
  }

  void _reload() {
    setState(() {
      _scanFuture = _scan();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: FutureBuilder<List<LocalLedgerImportCandidate>>(
        future: _scanFuture,
        builder: (context, snapshot) {
          final candidates = snapshot.data ?? const [];
          final pendingCount = candidates
              .where((item) => !item.imported)
              .length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionHeader(
                title: '本地数据导入云端',
                trailing: IconButton(
                  tooltip: '刷新',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                const _AccountInlineLoadingRow(message: '正在扫描本地账本')
              else if (snapshot.hasError)
                const Text('扫描失败，请稍后重试。')
              else ...[
                Text(
                  '可导入账本 $pendingCount 个，已导入 ${candidates.length - pendingCount} 个',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: pendingCount == 0
                      ? null
                      : () => _openImportDialog(candidates),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('选择并导入'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openImportDialog(
    List<LocalLedgerImportCandidate> candidates,
  ) async {
    final pending = candidates.where((item) => !item.imported).toList();
    final imported = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CloudImportDialog(candidates: pending),
    );

    if (!mounted || imported != true) return;
    _reload();
    ref.invalidate(ledgerNotifierProvider);
    ref.invalidate(personNotifierProvider);
    ref.invalidate(transactionNotifierProvider);
    ref.invalidate(ledgerStatsProvider);
    ref.invalidate(syncOverviewProvider);
    AppNotice.success(context, '本地账本导入完成');
  }
}

class _CloudImportDialog extends ConsumerStatefulWidget {
  const _CloudImportDialog({required this.candidates});

  final List<LocalLedgerImportCandidate> candidates;

  @override
  ConsumerState<_CloudImportDialog> createState() => _CloudImportDialogState();
}

class _CloudImportDialogState extends ConsumerState<_CloudImportDialog> {
  late final Set<String> _selectedLedgerUuids;
  bool _importing = false;
  CloudImportProgress? _progress;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedLedgerUuids = {
      for (final candidate in widget.candidates) candidate.ledger.uuid,
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入本地账本'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.58,
        ),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.candidates.length,
                  itemBuilder: (context, index) {
                    final candidate = widget.candidates[index];
                    final ledger = candidate.ledger;
                    return CheckboxListTile(
                      value: _selectedLedgerUuids.contains(ledger.uuid),
                      onChanged: _importing
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedLedgerUuids.add(ledger.uuid);
                                } else {
                                  _selectedLedgerUuids.remove(ledger.uuid);
                                }
                              });
                            },
                      title: Text(
                        ledger.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${candidate.transactionCount} 条流水 · ${ledger.displayCode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
              if (_progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _progress!.total == 0
                      ? null
                      : _progress!.done / _progress!.total,
                ),
                const SizedBox(height: 8),
                Text(_progress!.message),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _importing || _selectedLedgerUuids.isEmpty
              ? null
              : _startImport,
          child: Text(_importing ? '导入中' : '导入'),
        ),
      ],
    );
  }

  Future<void> _startImport() async {
    setState(() {
      _importing = true;
      _errorText = null;
    });

    try {
      await ref
          .read(cloudImportServiceProvider)
          .importLedgers(
            _selectedLedgerUuids.toList(),
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = FriendlyError.message(error, fallback: '导入失败，请稍后重试。');
        _importing = false;
      });
    }
  }
}

class _AuthPanel extends ConsumerStatefulWidget {
  const _AuthPanel({this.errorText});

  final String? errorText;

  @override
  ConsumerState<_AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends ConsumerState<_AuthPanel> {
  final _accountController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isRegister = false;
  bool _submitting = false;
  String? _errorText;
  bool _appliedLocalProfile = false;

  @override
  void initState() {
    super.initState();
    _errorText = widget.errorText;
  }

  @override
  void dispose() {
    _accountController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      children: [
        const _UnifiedProfileCard(isSignedIn: false),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('登录')),
            ButtonSegment(value: true, label: Text('注册')),
          ],
          selected: {_isRegister},
          onSelectionChanged: _submitting
              ? null
              : (value) {
                  setState(() {
                    _isRegister = value.first;
                    _errorText = null;
                  });
                  if (_isRegister) {
                    _applyLocalProfileToRegister();
                  }
                },
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          child: _AccountLoadingOverlay(
            loading: _submitting,
            message: _isRegister ? '正在注册账户' : '正在登录账户',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isRegister) ...[
                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ] else
                  TextField(
                    controller: _accountController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '邮箱或手机号',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: '密码',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: Icon(_isRegister ? Icons.person_add_alt_rounded : Icons.login),
          label: Text(
            _submitting
                ? (_isRegister ? '注册中' : '登录中')
                : (_isRegister ? '注册并登录' : '登录'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final authRepository = ref.read(authRepositoryProvider);
      final password = _passwordController.text.trim();
      if (_isRegister) {
        final localProfile = await ref.read(localProfileProvider.future);
        final email = _emailController.text.trim();
        final phone = _phoneController.text.trim();
        final nickname = _nicknameController.text.trim().isEmpty
            ? localProfile.normalizedNickname
            : _nicknameController.text.trim();
        if (nickname.isEmpty) {
          throw const FormatException('请输入昵称');
        }
        if (email.isEmpty && phone.isEmpty) {
          throw const FormatException('邮箱和手机号至少填写一个');
        }
        if (password.isEmpty) {
          throw const FormatException('请输入密码');
        }
        await authRepository.register(
          email: email.isEmpty ? null : email,
          phone: phone.isEmpty ? null : phone,
          password: password,
          nickname: nickname,
          avatar: localProfile.personAvatar,
        );
        await authRepository.login(
          account: email.isNotEmpty ? email : phone,
          password: password,
        );
      } else {
        final account = _accountController.text.trim();
        if (account.isEmpty) {
          throw const FormatException('请输入邮箱或手机号');
        }
        if (password.isEmpty) {
          throw const FormatException('请输入密码');
        }
        await authRepository.login(account: account, password: password);
      }

      ref.invalidate(authTokenProvider);
      ref.invalidate(currentUserProvider);
      ref.invalidate(ledgerNotifierProvider);
      ref.invalidate(ledgerStatsProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error is FormatException
            ? error.message
            : FriendlyError.message(error, fallback: '登录失败，请检查账号和密码。');
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _applyLocalProfileToRegister() async {
    if (_appliedLocalProfile || _nicknameController.text.trim().isNotEmpty) {
      return;
    }
    final profile = await ref.read(localProfileProvider.future);
    if (!mounted || !_isRegister) return;
    _appliedLocalProfile = true;
    _nicknameController.text = profile.normalizedNickname;
  }
}
