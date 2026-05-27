import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/network/friendly_error.dart';
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
  late final TextEditingController _nameController;
  late final TextEditingController _rateController;
  final FocusNode _nameFocus = FocusNode();
  late String _baseCurrencyCode;
  late bool _includeSelf;

  final Set<String> _selectedPersonIds = {};
  final List<Person> _draftPeople = [];
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
    _includeSelf = widget.existingLedger == null;

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
    if (_isDraftPeopleMode) {
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
            .read(personNotifierProvider(ledgerUuid: ledgerUuid).notifier)
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
    if (_isDraftPeopleMode) {
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
            .read(personNotifierProvider(ledgerUuid: ledgerUuid).notifier)
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
        content: Text('确定要删除 ${person.name} 吗？'),
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
      if (_isDraftPeopleMode) {
        setState(() {
          _draftPeople.removeWhere((item) => item.uuid == person.uuid);
          _selectedPersonIds.remove(person.uuid);
        });
        return;
      }

      try {
        await ref
            .read(
              personNotifierProvider(ledgerUuid: _personLedgerUuid).notifier,
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
    final exists = _draftPeople.any(
      (item) => item.uuid != currentUuid && item.name.trim() == name,
    );
    if (!exists) return true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('手动人员名称不能重复')));
    return false;
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(FriendlyError.message(error, fallback: '操作失败，请稍后重试。')),
      ),
    );
  }

  void _showPersonOptions(Person person) {
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
    final localProfile = ref.watch(localProfileProvider).valueOrNull;
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
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.existingLedger == null ? '新建账本' : '编辑账本',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (widget.existingLedger != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.existingLedger!.displayCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
                                setState(() => _baseCurrencyCode = value);
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
                              trailing: TextButton.icon(
                                onPressed: canManagePeople
                                    ? _addNewPerson
                                    : null,
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  size: 18,
                                ),
                                label: const Text('新增'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (widget.existingLedger == null) ...[
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                ),
                                title: Text(
                                  '加入${localProfile?.normalizedNickname ?? '本人'}',
                                ),
                                subtitle: Text(
                                  isCloudMode ? '创建时一次性加入账本' : '创建后自动把本地身份加入账本',
                                ),
                                value: _includeSelf,
                                onChanged: (value) {
                                  setState(() => _includeSelf = value);
                                },
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (isDraftPeopleMode)
                              _DraftPeopleSelector(
                                people: _draftPeople,
                                selectedPersonIds: _selectedPersonIds,
                                onToggle: (person, selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedPersonIds.add(person.uuid);
                                    } else {
                                      _selectedPersonIds.remove(person.uuid);
                                    }
                                  });
                                },
                                onLongPress: _showPersonOptions,
                              )
                            else if (!canManagePeople)
                              const Text('云端账本创建后，可再次编辑账本人员。')
                            else
                              peopleAsyncValue!.when(
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (e, st) => Text(
                                  FriendlyError.message(
                                    e,
                                    fallback: '人员加载失败，请稍后重试。',
                                  ),
                                ),
                                data: (peoplePool) {
                                  if (widget.existingLedger == null &&
                                      _selectedPersonIds.isEmpty &&
                                      !_includeSelf &&
                                      peoplePool.isNotEmpty) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          final self = peoplePool.firstWhere(
                                            (p) => p.name == '自己',
                                            orElse: () => peoplePool.first,
                                          );
                                          setState(
                                            () => _selectedPersonIds.add(
                                              self.uuid,
                                            ),
                                          );
                                        });
                                  }

                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: peoplePool.map((person) {
                                      final isSelected = _selectedPersonIds
                                          .contains(person.uuid);
                                      return GestureDetector(
                                        onLongPress: () =>
                                            _showPersonOptions(person),
                                        child: FilterChip(
                                          avatar: Text(
                                            person.avatar,
                                            style: const TextStyle(
                                              fontSize: 16,
                                            ),
                                          ),
                                          label: Text(person.name),
                                          selected: isSelected,
                                          onSelected: (selected) {
                                            setState(() {
                                              if (selected) {
                                                _selectedPersonIds.add(
                                                  person.uuid,
                                                );
                                              } else {
                                                _selectedPersonIds.remove(
                                                  person.uuid,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  );
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
              FilledButton(
                onPressed: canSubmit && !_submitting ? _submit : null,
                child: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.existingLedger == null ? '创建' : '保存修改'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入大于 0 的有效汇率')));
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
        includeSelf: _includeSelf,
      ),
    );
  }

  Future<List<Person>> _buildCreatePeople() async {
    if (!_isDraftPeopleMode) {
      return const [];
    }

    final selectedPeople = _draftPeople
        .where((person) => _selectedPersonIds.contains(person.uuid))
        .toList();
    if (!_includeSelf) {
      return selectedPeople;
    }

    final profile = await ref.read(localProfileProvider.future);
    final user = await ref.read(currentUserProvider.future);
    if (user == null) {
      throw const FormatException('登录状态已失效，请重新登录');
    }
    return [
      Person()
        ..uuid = 'self-${DateTime.now().microsecondsSinceEpoch}'
        ..name = profile.normalizedNickname
        ..avatar = profile.personAvatar
        ..linkedUserUuid = user.uuid,
      ...selectedPeople,
    ];
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
      return Text(
        '可先新增手动人员，创建账本时会一次保存。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: people.map((person) {
        final isSelected = selectedPersonIds.contains(person.uuid);
        return GestureDetector(
          onLongPress: () => onLongPress(person),
          child: FilterChip(
            avatar: Text(person.avatar, style: const TextStyle(fontSize: 16)),
            label: Text(person.name),
            selected: isSelected,
            onSelected: (selected) => onToggle(person, selected),
          ),
        );
      }).toList(),
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
