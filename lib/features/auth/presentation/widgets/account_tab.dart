import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
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
                  (avatar == null || avatar!.isEmpty)
                      ? nickname.characters.first
                      : avatar!,
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
        const _CloudImportCard(),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            await ref.read(authRepositoryProvider).logout();
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
      content: SizedBox(
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
                    title: Text(ledger.name),
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
        final email = _emailController.text.trim();
        final phone = _phoneController.text.trim();
        await authRepository.register(
          email: email.isEmpty ? null : email,
          phone: phone.isEmpty ? null : phone,
          password: password,
          nickname: _nicknameController.text.trim(),
        );
        await authRepository.login(
          account: email.isNotEmpty ? email : phone,
          password: password,
        );
      } else {
        await authRepository.login(
          account: _accountController.text.trim(),
          password: password,
        );
      }

      ref.invalidate(authTokenProvider);
      ref.invalidate(currentUserProvider);
      ref.invalidate(ledgerNotifierProvider);
      ref.invalidate(ledgerStatsProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorText = error.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
