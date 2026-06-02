import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/local_profile.dart';
import '../../../../core/models/person.dart';
import '../../../../core/network/friendly_error.dart';
import '../../../../core/repositories/auth_repository.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../people_pool/presentation/widgets/person_edit_dialog.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';

class CreateLedgerResult {
  const CreateLedgerResult({
    required this.name,
    required this.baseCurrencyCode,
    required this.exchangeRateToCNY,
    required this.personIds,
    required this.people,
    required this.includeSelf,
  });

  final String name;
  final String baseCurrencyCode;
  final double exchangeRateToCNY;
  final List<String> personIds;
  final List<Person> people;
  final bool includeSelf;
}

class CreateLedgerSheet extends ConsumerStatefulWidget {
  const CreateLedgerSheet({super.key, this.existingLedger});

  final Ledger? existingLedger;

  @override
  ConsumerState<CreateLedgerSheet> createState() => _CreateLedgerSheetState();
}

class _CreateLedgerSheetState extends ConsumerState<CreateLedgerSheet> {
  static const _draftSelfPersonUuid = '__self__';

  late final TextEditingController _nameController;
  late final TextEditingController _rateController;
  final FocusNode _nameFocus = FocusNode();
  late String _baseCurrencyCode;

  final Set<String> _selectedPersonIds = {};
  final List<Person> _draftPeople = [];
  List<Person> _latestPeoplePool = const [];
  bool _draftSelfDeselected = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingLedger?.name ?? '',
    );
    _baseCurrencyCode = widget.existingLedger?.baseCurrencyCode ?? 'CNY';
    _rateController = TextEditingController(
      text: widget.existingLedger?.exchangeRateToCNY.toString() ?? '1.0',
    );

    if (widget.existingLedger != null) {
      _selectedPersonIds.addAll(widget.existingLedger!.personUuids);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _addNewPerson() async {
    if (_isDraftPeopleMode || widget.existingLedger != null) {
      final result = await showDialog<Person>(
        context: context,
        builder: (context) => const PersonEditDialog(),
      );
      if (result == null || !mounted) return;
      if (!_validateDraftPersonName(result)) return;
      setState(() {
        _draftPeople.add(result);
        _selectedPersonIds.add(result.uuid);
      });
      return;
    }

    final ledgerUuid = _personLedgerUuid;
    final result = await showDialog<Person>(
      context: context,
      builder: (context) => const PersonEditDialog(),
    );

    if (result != null && mounted) {
      try {
        await ref
            .read(
              personNotifierProvider(
                includeDeleted: false,
                ledgerUuid: ledgerUuid,
              ).notifier,
            )
            .addOrUpdatePerson(result);

        setState(() {
          _selectedPersonIds.add(result.uuid);
        });
      } catch (e) {
        _showWriteError(e);
      }
    }
  }

  Future<void> _editPerson(Person person) async {
    if (_isDraftPerson(person)) {
      final result = await showDialog<Person>(
        context: context,
        builder: (context) => PersonEditDialog(person: person),
      );
      if (result == null || !mounted) return;
      if (!_validateDraftPersonName(result, currentUuid: person.uuid)) return;
      setState(() {
        final index = _draftPeople.indexWhere(
          (item) => item.uuid == person.uuid,
        );
        if (index != -1) {
          _draftPeople[index] = result;
        }
      });
      return;
    }

    final ledgerUuid = _personLedgerUuid;
    final result = await showDialog<Person>(
      context: context,
      builder: (context) => PersonEditDialog(person: person),
    );

    if (result != null && mounted) {
      try {
        await ref
            .read(
              personNotifierProvider(
                includeDeleted: false,
                ledgerUuid: ledgerUuid,
              ).notifier,
            )
            .addOrUpdatePerson(result);
      } catch (e) {
        _showWriteError(e);
      }
    }
  }

  Future<void> _deletePerson(Person person) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除人员'),
        content: Text('确定要删除 ${person.name} 吗？\n\n已有流水中的历史记录会保留，但新记账时不再显示该人员。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      if (_isDraftPerson(person)) {
        setState(() {
          _draftPeople.removeWhere((item) => item.uuid == person.uuid);
          _selectedPersonIds.remove(person.uuid);
        });
        return;
      }

      try {
        await ref
            .read(
              personNotifierProvider(
                includeDeleted: false,
                ledgerUuid: _personLedgerUuid,
              ).notifier,
            )
            .deletePerson(person.uuid);
        setState(() {
          _selectedPersonIds.remove(person.uuid);
        });
      } catch (e) {
        _showWriteError(e);
      }
    }
  }

  String? get _personLedgerUuid => widget.existingLedger?.uuid;

  bool get _isDraftPeopleMode {
    final token = ref.read(authTokenProvider).valueOrNull;
    return widget.existingLedger == null && token != null && token.isValid;
  }

  bool _validateDraftPersonName(Person person, {String? currentUuid}) {
    final name = person.name.trim();
    final exists = [
      ..._latestPeoplePool,
      ..._draftPeople,
    ].any((item) => item.uuid != currentUuid && item.name.trim() == name);
    if (!exists) return true;
    AppNotice.error(context, '手动人员名称不能重复');
    return false;
  }

  bool _isDraftPerson(Person person) {
    return _draftPeople.any((item) => item.uuid == person.uuid);
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    AppNotice.error(
      context,
      FriendlyError.message(error, fallback: '操作失败，请稍后重试。'),
    );
  }

  void _showPersonOptions(Person person) {
    if (person.uuid == _draftSelfPersonUuid) {
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                _editPerson(person);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _deletePerson(person);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canSubmit = _nameController.text.trim().isNotEmpty;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    final token = ref.watch(authTokenProvider).valueOrNull;
    final isCloudMode = token != null && token.isValid;
    final personLedgerUuid = isCloudMode ? widget.existingLedger?.uuid : null;
    final isDraftPeopleMode = isCloudMode && widget.existingLedger == null;
    final canManagePeople =
        !isCloudMode || personLedgerUuid != null || isDraftPeopleMode;
    final localProfileAsync = ref.watch(localProfileProvider);
    final localProfile = localProfileAsync.valueOrNull;
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final effectiveSelectedPersonIds = _effectiveSelectedPersonIds(
      isDraftPeopleMode,
    );
    final selectedPeopleCount = effectiveSelectedPersonIds.length;
    final peopleAsyncValue = canManagePeople && !isDraftPeopleMode
        ? ref.watch(
            personNotifierProvider(
              includeDeleted: false,
              ledgerUuid: personLedgerUuid,
            ),
          )
        : null;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: bottomInset + 16,
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetHeader(
                isEditing: widget.existingLedger != null,
                displayCode: widget.existingLedger?.displayCode,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppSectionHeader(
                              title: '基础信息',
                              trailing: Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nameController,
                              focusNode: _nameFocus,
                              autofocus: widget.existingLedger == null,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: '账本名称',
                                prefixIcon: Icon(
                                  Icons.drive_file_rename_outline,
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            _CurrencyRateFields(
                              baseCurrencyCode: _baseCurrencyCode,
                              rateController: _rateController,
                              onCurrencyChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _baseCurrencyCode = value;
                                  if (value == 'CNY') {
                                    _rateController.text = '1.0';
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppSectionHeader(
                              title: '账本人员',
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _CountPill(count: selectedPeopleCount),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    tooltip: '新增人员',
                                    onPressed: canManagePeople
                                        ? _addNewPerson
                                        : null,
                                    icon: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (isDraftPeopleMode)
                              _DraftPeopleSelector(
                                people: [
                                  _buildDraftSelfPerson(
                                    localProfile,
                                    currentUser,
                                  ),
                                  ..._draftPeople,
                                ],
                                selectedPersonIds: effectiveSelectedPersonIds,
                                onToggle: (person, selected) {
                                  setState(() {
                                    _togglePersonSelection(person, selected);
                                  });
                                },
                                onLongPress: _showPersonOptions,
                              )
                            else if (!canManagePeople)
                              _InfoStrip(
                                icon: Icons.cloud_done_outlined,
                                text: '云端账本创建后，可再次编辑账本人员。',
                              )
                            else
                              peopleAsyncValue!.when(
                                loading: () => _draftPeople.isEmpty
                                    ? const _PeopleLoadingState()
                                    : _buildPeopleSelector(_latestPeoplePool),
                                error: (e, st) => _draftPeople.isEmpty
                                    ? _InfoStrip(
                                        icon: Icons.error_outline_rounded,
                                        text: FriendlyError.message(
                                          e,
                                          fallback: '人员加载失败，请稍后重试。',
                                        ),
                                      )
                                    : _buildPeopleSelector(_latestPeoplePool),
                                data: (peoplePool) {
                                  _latestPeoplePool = peoplePool;
                                  _selectDefaultSelfPerson(
                                    peoplePool,
                                    localProfile,
                                    currentUser,
                                  );

                                  return _buildPeopleSelector(peoplePool);
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SubmitButton(
                label: widget.existingLedger == null ? '创建账本' : '保存修改',
                submitting: _submitting,
                onPressed: canSubmit && !_submitting ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final rate = double.tryParse(_rateController.text);
    if (rate == null || rate <= 0) {
      AppNotice.error(context, '请输入大于 0 的有效汇率');
      return;
    }

    setState(() => _submitting = true);
    final List<Person> people;
    try {
      people = await _buildCreatePeople();
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showWriteError(error);
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);

    Navigator.of(context).pop(
      CreateLedgerResult(
        name: name,
        baseCurrencyCode: _baseCurrencyCode,
        exchangeRateToCNY: rate,
        personIds: _selectedPersonIds.toList(),
        people: people,
        includeSelf: _shouldIncludeSelfFallback,
      ),
    );
  }

  Future<List<Person>> _buildCreatePeople() async {
    if (widget.existingLedger != null) {
      return _draftPeople
          .where((person) => _selectedPersonIds.contains(person.uuid))
          .toList();
    }
    if (!_isDraftPeopleMode) {
      return const [];
    }

    final selectedPeople = _draftPeople
        .where((person) => _selectedPersonIds.contains(person.uuid))
        .toList();
    if (_draftSelfDeselected) {
      return selectedPeople;
    }

    final profile = await ref.read(localProfileProvider.future);
    final accountUuid = await ref.read(tokenStoreProvider).readAccountUuid();
    return [
      Person()
        ..uuid = 'self-${DateTime.now().microsecondsSinceEpoch}'
        ..name = profile.normalizedNickname
        ..avatar = profile.personAvatar
        ..linkedUserUuid = accountUuid,
      ...selectedPeople,
    ];
  }

  List<Person> _mergeVisiblePeople(List<Person> peoplePool) {
    return {
      for (final person in peoplePool) person.uuid: person,
      for (final person in _draftPeople) person.uuid: person,
    }.values.toList();
  }

  Widget _buildPeopleSelector(List<Person> peoplePool) {
    return _PeopleSelector(
      people: _mergeVisiblePeople(peoplePool),
      selectedPersonIds: _selectedPersonIds,
      onToggle: (person, selected) {
        setState(() {
          _togglePersonSelection(person, selected);
        });
      },
      onLongPress: _showPersonOptions,
    );
  }

  bool get _shouldIncludeSelfFallback {
    if (widget.existingLedger != null) {
      return false;
    }
    if (_isDraftPeopleMode) {
      return !_draftSelfDeselected;
    }
    return false;
  }

  Set<String> _effectiveSelectedPersonIds(bool isDraftPeopleMode) {
    if (!isDraftPeopleMode || widget.existingLedger != null) {
      return _selectedPersonIds;
    }
    if (_draftSelfDeselected) {
      return _selectedPersonIds;
    }
    return {_draftSelfPersonUuid, ..._selectedPersonIds};
  }

  Person _buildDraftSelfPerson(LocalProfile? profile, AuthUser? user) {
    return Person()
      ..uuid = _draftSelfPersonUuid
      ..name = profile?.normalizedNickname ?? user?.nickname ?? '本人'
      ..avatar = profile?.personAvatar ?? user?.avatar ?? '😎'
      ..linkedUserUuid = user?.uuid;
  }

  void _togglePersonSelection(Person person, bool selected) {
    if (person.uuid == _draftSelfPersonUuid) {
      _draftSelfDeselected = !selected;
      return;
    }
    if (selected) {
      _selectedPersonIds.add(person.uuid);
    } else {
      _selectedPersonIds.remove(person.uuid);
    }
  }

  void _selectDefaultSelfPerson(
    List<Person> peoplePool,
    LocalProfile? localProfile,
    AuthUser? currentUser,
  ) {
    if (widget.existingLedger != null ||
        _isDraftPeopleMode ||
        _selectedPersonIds.isNotEmpty ||
        peoplePool.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedPersonIds.isNotEmpty) return;
      final self = _findSelfPerson(peoplePool, localProfile, currentUser);
      if (self == null) return;
      setState(() => _selectedPersonIds.add(self.uuid));
    });
  }

  Person? _findSelfPerson(
    List<Person> peoplePool,
    LocalProfile? localProfile,
    AuthUser? currentUser,
  ) {
    final nickname = localProfile?.normalizedNickname.trim();
    for (final person in peoplePool) {
      final isSelfUuid = person.uuid == 'self' || person.uuid == 'p1';
      final isLinkedUser =
          currentUser != null && person.linkedUserUuid == currentUser.uuid;
      final isProfileName =
          nickname != null &&
          nickname.isNotEmpty &&
          person.name.trim() == nickname;
      if (isSelfUuid || isLinkedUser || isProfileName || person.name == '自己') {
        return person;
      }
    }
    return peoplePool.firstOrNull;
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.isEditing, this.displayCode});

  final bool isEditing;
  final String? displayCode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isEditing ? Icons.edit_note_rounded : Icons.menu_book_rounded,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isEditing ? '编辑账本' : '新建账本',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEditing ? (displayCode ?? '调整名称、币种和人员') : '设置名称、币种和初始参与人',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count 人',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DraftPeopleSelector extends StatelessWidget {
  const _DraftPeopleSelector({
    required this.people,
    required this.selectedPersonIds,
    required this.onToggle,
    required this.onLongPress,
  });

  final List<Person> people;
  final Set<String> selectedPersonIds;
  final void Function(Person person, bool selected) onToggle;
  final ValueChanged<Person> onLongPress;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const _InfoStrip(
        icon: Icons.touch_app_outlined,
        text: '点击右上角新增手动人员，创建账本时会一起保存。',
      );
    }

    return _PeopleSelector(
      people: people,
      selectedPersonIds: selectedPersonIds,
      onToggle: onToggle,
      onLongPress: onLongPress,
    );
  }
}

class _PeopleSelector extends StatelessWidget {
  const _PeopleSelector({
    required this.people,
    required this.selectedPersonIds,
    required this.onToggle,
    required this.onLongPress,
  });

  final List<Person> people;
  final Set<String> selectedPersonIds;
  final void Function(Person person, bool selected) onToggle;
  final ValueChanged<Person> onLongPress;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const _InfoStrip(
        icon: Icons.group_add_outlined,
        text: '暂无可选人员，点击右上角新增。',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final columns = constraints.maxWidth >= 360 ? 2 : 1;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: people.map((person) {
            final selected = selectedPersonIds.contains(person.uuid);
            return SizedBox(
              width: width,
              child: _PersonSelectTile(
                person: person,
                selected: selected,
                onTap: () => onToggle(person, !selected),
                onLongPress: () => onLongPress(person),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _PersonSelectTile extends StatelessWidget {
  const _PersonSelectTile({
    required this.person,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Person person;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.62)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              width: selected ? 1.4 : 1,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: selected
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : colorScheme.surfaceContainerHigh,
                child: Text(
                  person.avatar,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 21,
                color: selected ? colorScheme.primary : colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _PeopleLoadingState extends StatelessWidget {
  const _PeopleLoadingState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      alignment: Alignment.center,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.3,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.submitting,
    required this.onPressed,
  });

  final String label;
  final bool submitting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: submitting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded),
        label: Text(label),
      ),
    );
  }
}

class _CurrencyRateFields extends StatelessWidget {
  const _CurrencyRateFields({
    required this.baseCurrencyCode,
    required this.rateController,
    required this.onCurrencyChanged,
  });

  final String baseCurrencyCode;
  final TextEditingController rateController;
  final ValueChanged<String?> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final currencyField = DropdownButtonFormField<String>(
          key: ValueKey('ledger-currency-$baseCurrencyCode'),
          initialValue: baseCurrencyCode,
          decoration: const InputDecoration(
            labelText: '默认币种',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'CNY', child: Text('CNY 人民币')),
            DropdownMenuItem(value: 'USD', child: Text('USD 美元')),
            DropdownMenuItem(value: 'EUR', child: Text('EUR 欧元')),
            DropdownMenuItem(value: 'JPY', child: Text('JPY 日元')),
            DropdownMenuItem(value: 'THB', child: Text('THB 泰铢')),
          ],
          onChanged: onCurrencyChanged,
        );

        final rateField = TextField(
          controller: rateController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '对人民币汇率',
            prefixIcon: const Icon(Icons.currency_exchange_rounded),
            helperText: '1 $baseCurrencyCode = ? CNY',
          ),
        );

        if (constraints.maxWidth < 390) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [currencyField, const SizedBox(height: 12), rateField],
          );
        }

        return Row(
          children: [
            Expanded(flex: 4, child: currencyField),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: rateField),
          ],
        );
      },
    );
  }
}
