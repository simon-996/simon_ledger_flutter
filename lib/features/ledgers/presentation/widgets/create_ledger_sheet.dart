import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../people_pool/presentation/widgets/person_edit_dialog.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';

class CreateLedgerResult {
  const CreateLedgerResult({
    required this.name,
    required this.baseCurrencyCode,
    required this.exchangeRateToCNY,
    required this.personIds,
  });

  final String name;
  final String baseCurrencyCode;
  final double exchangeRateToCNY;
  final List<String> personIds;
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
  
  final Set<String> _selectedPersonIds = {}; 

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingLedger?.name ?? '');
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
    final result = await showDialog<Person>(
      context: context,
      builder: (context) => const PersonEditDialog(),
    );

    if (result != null && mounted) {
      await ref.read(personNotifierProvider().notifier).addOrUpdatePerson(result);
      
      setState(() {
        _selectedPersonIds.add(result.uuid);
      });
    }
  }

  Future<void> _editPerson(Person person) async {
    final result = await showDialog<Person>(
      context: context,
      builder: (context) => PersonEditDialog(person: person),
    );

    if (result != null && mounted) {
      await ref.read(personNotifierProvider().notifier).addOrUpdatePerson(result);
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
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(personNotifierProvider().notifier).deletePerson(person.uuid);
      setState(() {
        _selectedPersonIds.remove(person.uuid);
      });
    }
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
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
    
    final peopleAsyncValue = ref.watch(personNotifierProvider(includeDeleted: false));

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: bottomInset + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existingLedger == null ? '新建账本' : '编辑账本',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            autofocus: widget.existingLedger == null,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '账本名称',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  value: _baseCurrencyCode,
                  decoration: const InputDecoration(
                    labelText: '默认币种',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'CNY', child: Text('CNY 人民币')),
                    DropdownMenuItem(value: 'USD', child: Text('USD 美元')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR 欧元')),
                    DropdownMenuItem(value: 'JPY', child: Text('JPY 日元')),
                    DropdownMenuItem(value: 'THB', child: Text('THB 泰铢')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _baseCurrencyCode = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '对人民币汇率',
                    border: const OutlineInputBorder(),
                    helperText: '1 $_baseCurrencyCode = ? CNY',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('账本人员', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _addNewPerson,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('新增'),
              ),
            ],
          ),
          peopleAsyncValue.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => Text('Error: $e'),
            data: (peoplePool) {
              // Select default person initially
              if (widget.existingLedger == null && _selectedPersonIds.isEmpty && peoplePool.isNotEmpty) {
                 WidgetsBinding.instance.addPostFrameCallback((_) {
                    final self = peoplePool.firstWhere((p) => p.name == '自己', orElse: () => peoplePool.first);
                    setState(() => _selectedPersonIds.add(self.uuid));
                 });
              }
              return Wrap(
                spacing: 8,
                children: peoplePool.map((person) {
                  final isSelected = _selectedPersonIds.contains(person.uuid);
                  return GestureDetector(
                    onLongPress: () => _showPersonOptions(person),
                    child: FilterChip(
                      avatar: Text(person.avatar, style: const TextStyle(fontSize: 16)),
                      label: Text(person.name),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedPersonIds.add(person.uuid);
                          } else {
                            _selectedPersonIds.remove(person.uuid);
                          }
                        });
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
            child: Text(widget.existingLedger == null ? '创建' : '保存修改'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    
    final rate = double.tryParse(_rateController.text) ?? 1.0;

    Navigator.of(context).pop(
      CreateLedgerResult(
        name: name,
        baseCurrencyCode: _baseCurrencyCode,
        exchangeRateToCNY: rate,
        personIds: _selectedPersonIds.toList(),
      ),
    );
  }
}
