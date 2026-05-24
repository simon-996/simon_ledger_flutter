import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/models/local_profile.dart';
import '../../../../core/services/cloud_import_service.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../ledgers/presentation/providers/ledger_provider.dart';
import '../../../ledgers/presentation/providers/ledger_stats_provider.dart';
import '../providers/auth_provider.dart';

class AccountTab extends ConsumerWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _AuthPanel(errorText: '$error'),
      data: (user) {
        if (user == null) {
          return const _AuthPanel();
        }
        return _SignedInPanel(
          nickname: user.nickname,
          account: user.email ?? user.phone ?? user.uuid,
          avatar: user.avatar,
        );
      },
    );
  }
}

class _SignedInPanel extends ConsumerWidget {
  const _SignedInPanel({
    required this.nickname,
    required this.account,
    this.avatar,
  });

  final String nickname;
  final String account;
  final String? avatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarText = avatar == null || avatar!.isEmpty
        ? (nickname.isEmpty ? '?' : nickname.characters.first)
        : avatar!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSectionCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  avatarText,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AccountProfileCard(
          nickname: nickname,
          avatar: avatar,
          onSaved: () {
            ref.invalidate(currentUserProvider);
          },
        ),
        const SizedBox(height: 16),
        const _LocalProfileCard(),
        const SizedBox(height: 16),
        const _CloudImportCard(),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            try {
              await ref.read(authRepositoryProvider).logout();
            } catch (_) {
              await ref.read(tokenStoreProvider).clear();
            }
            ref.invalidate(authTokenProvider);
            ref.invalidate(currentUserProvider);
            ref.invalidate(ledgerNotifierProvider);
            ref.invalidate(ledgerStatsProvider);
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}

class _AccountProfileCard extends ConsumerWidget {
  const _AccountProfileCard({
    required this.nickname,
    required this.avatar,
    required this.onSaved,
  });

  final String nickname;
  final String? avatar;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarText = avatar == null || avatar!.isEmpty
        ? (nickname.isEmpty ? '?' : nickname.characters.first)
        : avatar!;

    return AppSectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _editProfile(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSectionHeader(
                title: '账号昵称和头像',
                trailing: TextButton.icon(
                  onPressed: () => _editProfile(context, ref),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('修改'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      avatarText,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_AccountProfileEditResult>(
      context: context,
      builder: (context) =>
          _AccountProfileDialog(nickname: nickname, avatar: avatar),
    );
    if (result == null) return;

    try {
      await ref
          .read(authRepositoryProvider)
          .updateProfile(nickname: result.nickname, avatar: result.avatar);
      onSaved();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败，请重试：$error')));
    }
  }
}

class _AccountProfileEditResult {
  const _AccountProfileEditResult({
    required this.nickname,
    required this.avatar,
  });

  final String nickname;
  final String avatar;
}

class _AccountProfileDialog extends StatefulWidget {
  const _AccountProfileDialog({required this.nickname, this.avatar});

  final String nickname;
  final String? avatar;

  @override
  State<_AccountProfileDialog> createState() => _AccountProfileDialogState();
}

class _AccountProfileDialogState extends State<_AccountProfileDialog> {
  static const _avatars = ['👤', '🙂', '👛', '🏠', '⭐'];

  late final TextEditingController _nicknameController;
  late String _avatar;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.nickname);
    _avatar = widget.avatar == null || widget.avatar!.isEmpty
        ? _avatars.first
        : widget.avatar!;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('账号资料'),
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
              children: _avatars.map((avatar) {
                return ChoiceChip(
                  label: Text(avatar, style: const TextStyle(fontSize: 18)),
                  selected: _avatar == avatar,
                  onSelected: (_) => setState(() => _avatar = avatar),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入昵称')));
      return;
    }

    Navigator.of(
      context,
    ).pop(_AccountProfileEditResult(nickname: nickname, avatar: _avatar));
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
                const Center(child: CircularProgressIndicator())
              else if (snapshot.hasError)
                Text('扫描失败：${snapshot.error}')
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
    ref.invalidate(ledgerStatsProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('本地账本导入完成')));
  }
}

class _LocalProfileCard extends ConsumerWidget {
  const _LocalProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(localProfileProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return AppSectionCard(
      child: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Text('本地资料加载失败：$error'),
        data: (profile) => InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _editProfile(context, ref, profile),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSectionHeader(
                  title: '本地昵称和头像',
                  trailing: TextButton.icon(
                    onPressed: () => _editProfile(context, ref, profile),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('修改'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: colorScheme.secondaryContainer,
                      child: Icon(
                        profile.iconData,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.normalizedNickname,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '未登录时用于创建账本和默认加入本人',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    LocalProfile profile,
  ) async {
    final result = await showDialog<LocalProfile>(
      context: context,
      builder: (context) => _LocalProfileDialog(profile: profile),
    );
    if (result == null) return;

    await ref.read(localProfileStoreProvider).save(result);
    ref.invalidate(localProfileProvider);
  }
}

class _LocalProfileDialog extends StatefulWidget {
  const _LocalProfileDialog({required this.profile});

  final LocalProfile profile;

  @override
  State<_LocalProfileDialog> createState() => _LocalProfileDialogState();
}

class _LocalProfileDialogState extends State<_LocalProfileDialog> {
  static const _avatarIcons = ['person', 'face', 'wallet', 'home', 'star'];

  late final TextEditingController _nicknameController;
  late String _avatarIcon;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.profile.normalizedNickname,
    );
    _avatarIcon = widget.profile.avatarIcon;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('本地身份'),
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
              children: _avatarIcons.map((icon) {
                final profile = LocalProfile(nickname: '', avatarIcon: icon);
                return ChoiceChip(
                  avatar: Icon(profile.iconData, size: 18),
                  label: const SizedBox.shrink(),
                  showCheckmark: false,
                  selected: _avatarIcon == icon,
                  onSelected: (_) => setState(() => _avatarIcon = icon),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入昵称')));
      return;
    }

    Navigator.of(
      context,
    ).pop(LocalProfile(nickname: nickname, avatarIcon: _avatarIcon));
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
                      subtitle: Text('${candidate.transactionCount} 条流水'),
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
          child: _importing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('导入'),
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
        _errorText = '导入失败，请重试：$error';
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
        const _LocalProfileCard(),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isRegister ? Icons.person_add_alt_rounded : Icons.login),
          label: Text(_isRegister ? '注册并登录' : '登录'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
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
            : error.toString();
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
