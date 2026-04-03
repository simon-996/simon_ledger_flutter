import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/ledger.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../providers/transaction_provider.dart';

class EditTransactionSheet extends ConsumerStatefulWidget {
  const EditTransactionSheet({
    super.key,
    required this.transaction,
    required this.ledger,
  });

  final TransactionRecord transaction;
  final Ledger ledger;

  @override
  ConsumerState<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends ConsumerState<EditTransactionSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  
  late int _transactionType;
  late String _selectedCategory;
  final Set<String> _selectedPersonIds = {};

  final List<String> _expenseCategories = ['默认', '交通', '购物', '餐饮', '杂费', '娱乐', '居住'];
  final List<String> _incomeCategories = ['默认', '工资', '兼职', '理财', '红包', '其他'];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.transaction.amount.toString());
    _noteController = TextEditingController(text: widget.transaction.note);
    _transactionType = widget.transaction.type;
    _selectedCategory = widget.transaction.category;
    _selectedPersonIds.addAll(widget.transaction.personUuids);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _saveChanges() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效金额')),
      );
      return;
    }

    if (_selectedPersonIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个参与人员')),
      );
      return;
    }

    widget.transaction.amount = amount;
    widget.transaction.type = _transactionType;
    widget.transaction.category = _selectedCategory;
    widget.transaction.note = _noteController.text.trim();
    widget.transaction.personUuids = _selectedPersonIds.toList();

    await ref.read(transactionNotifierProvider(widget.ledger.uuid).notifier).updateTransaction(widget.transaction);

    if (mounted) {
      Navigator.of(context).pop(true); // Return true to indicate success
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final peopleAsyncValue = ref.watch(personNotifierProvider(includeDeleted: true));

    return AnimatedPadding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottomInset + 16,
      ),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('编辑明细', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('支出')),
                        ButtonSegment(value: 1, label: Text('收入')),
                      ],
                      selected: {_transactionType},
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() {
                          _transactionType = newSelection.first;
                          _selectedCategory = _transactionType == 0 ? _expenseCategories.first : _incomeCategories.first;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: '金额',
                      border: const OutlineInputBorder(),
                      prefixText: '${widget.ledger.baseCurrencyCode} ',
                    ),
                  ),
                  const SizedBox(height: 16),
          
          Text('分类', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: (_transactionType == 0 ? _expenseCategories : _incomeCategories).map((cat) {
              final isSelected = _selectedCategory == cat;
              return ChoiceChip(
                label: Text(cat),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedCategory = cat);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          
          peopleAsyncValue.when(
            loading: () => const SizedBox.shrink(),
            error: (err, st) => const SizedBox.shrink(),
            data: (peoplePool) {
              if (widget.ledger.personUuids.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('参与人员', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.ledger.personUuids.map((pid) {
                      final person = peoplePool.firstWhere((p) => p.uuid == pid, orElse: () => Person()..uuid = ''..name = '未知');
                      final isSelected = _selectedPersonIds.contains(pid);
                      return FilterChip(
                        avatar: Text(person.avatar),
                        label: Text(person.name),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedPersonIds.add(pid);
                            } else {
                              _selectedPersonIds.remove(pid);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: '备注（选填）',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          
          FilledButton(
            onPressed: _saveChanges,
            child: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('保存修改', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}