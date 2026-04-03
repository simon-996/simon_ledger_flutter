import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/models/ledger.dart';
import '../../../../core/models/person.dart';
import '../../../../core/models/transaction_record.dart';
import '../../../people_pool/presentation/providers/person_provider.dart';
import '../providers/transaction_provider.dart';

class BookkeepingTab extends ConsumerStatefulWidget {
  const BookkeepingTab({super.key, required this.ledgers});
  final List<Ledger> ledgers;

  @override
  ConsumerState<BookkeepingTab> createState() => _BookkeepingTabState();
}

class _BookkeepingTabState extends ConsumerState<BookkeepingTab> {
  String? _selectedLedgerUuid;
  String? _selectedCategory;
  final Set<String> _selectedPersonIds = {};
  String? _selectedCurrency;
  
  // 0 for expense, 1 for income
  int _transactionType = 0;
  
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  final List<String> _expenseCategories = ['默认', '交通', '购物', '餐饮', '杂费', '娱乐', '居住'];
  final List<String> _incomeCategories = ['默认', '工资', '兼职', '理财', '红包', '其他'];
  
  static const _lastLedgerKey = 'last_selected_ledger_uuid';

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  @override
  void didUpdateWidget(covariant BookkeepingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ledgers != oldWidget.ledgers) {
      if (_selectedLedgerUuid != null) {
        final currentLedgerIndex = widget.ledgers.indexWhere((l) => l.uuid == _selectedLedgerUuid);
        if (currentLedgerIndex == -1) {
          setState(() {
            _selectedLedgerUuid = null;
            _selectedCurrency = null;
            _selectedPersonIds.clear();
          });
        } else {
          // Ledger still exists, but its properties (like people) might have changed
          final updatedLedger = widget.ledgers[currentLedgerIndex];
          setState(() {
            _selectedCurrency = updatedLedger.baseCurrencyCode;
            // Retain only valid person IDs for this ledger
            _selectedPersonIds.retainWhere((id) => updatedLedger.personUuids.contains(id));
            // If empty after retain (and ledger has people), select the first one
            if (_selectedPersonIds.isEmpty && updatedLedger.personUuids.isNotEmpty) {
              _selectedPersonIds.add(updatedLedger.personUuids.first);
            }
          });
        }
      }
    }
  }

  Future<void> _initDefaults() async {
    _selectedCategory ??= _transactionType == 0 ? _expenseCategories.first : _incomeCategories.first;
    
    final prefs = await SharedPreferences.getInstance();
    final lastUuid = prefs.getString(_lastLedgerKey);
    
    if (mounted && widget.ledgers.isNotEmpty) {
      setState(() {
        if (lastUuid != null && widget.ledgers.any((l) => l.uuid == lastUuid)) {
          _updateSelectedLedger(lastUuid);
        } else {
          if (widget.ledgers.length == 1) {
             _updateSelectedLedger(widget.ledgers.first.uuid);
          } else {
             _selectedLedgerUuid = null;
          }
        }
      });
    }
  }

  void _updateSelectedLedger(String ledgerUuid) {
    _selectedLedgerUuid = ledgerUuid;
    final ledger = widget.ledgers.firstWhere((l) => l.uuid == ledgerUuid);
    _selectedCurrency = ledger.baseCurrencyCode;
    
    if (ledger.personUuids.isNotEmpty) {
      if (_selectedPersonIds.isEmpty) {
        _selectedPersonIds.add(ledger.personUuids.first);
      } else {
        _selectedPersonIds.retainWhere((id) => ledger.personUuids.contains(id));
      }
    } else {
      _selectedPersonIds.clear();
    }
    
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_lastLedgerKey, ledgerUuid);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _showSuccessAnimation(double amount, String currency, String category, Iterable<Person> people) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
            child: FadeTransition(
              opacity: animation,
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '记账成功',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$currency $amount',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(category),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 4,
                        alignment: WrapAlignment.center,
                        children: people.map((p) => Text('${p.avatar} ${p.name}')).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _saveTransaction(List<Person> peoplePool) async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入大于 0 的有效金额')),
      );
      return;
    }

    if (_selectedPersonIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个参与人员')),
      );
      return;
    }

    final category = _selectedCategory ?? '默认';
    final currency = _selectedCurrency ?? 'CNY';
    final ledgerId = _selectedLedgerUuid;
    
    if (ledgerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个所属账本')),
      );
      return;
    }

    final selectedPeople = _selectedPersonIds.map((pid) {
      return peoplePool.firstWhere(
        (p) => p.uuid == pid, 
        orElse: () => Person()..uuid = ''..name = '未知'
      );
    });

    final record = TransactionRecord()
      ..uuid = DateTime.now().microsecondsSinceEpoch.toString()
      ..ledgerUuid = ledgerId
      ..type = _transactionType
      ..amount = amount
      ..currencyCode = currency
      ..category = category
      ..personUuids = _selectedPersonIds.toList()
      ..note = _noteController.text.trim()
      ..createdAt = DateTime.now();
      
    await ref.read(transactionNotifierProvider(ledgerId).notifier).addTransaction(record);

    if (mounted) {
      _showSuccessAnimation(amount, currency, category, selectedPeople);
      _amountController.clear();
      _noteController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ledgers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('请先在“账本”页面添加一个账本'),
          ],
        ),
      );
    }
    
    // Watch people pool
    final peopleAsyncValue = ref.watch(personNotifierProvider(includeDeleted: true));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedLedgerUuid,
                  decoration: const InputDecoration(
                    labelText: '所属账本',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.book),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  isExpanded: true,
                  items: widget.ledgers.map((l) => DropdownMenuItem(value: l.uuid, child: Text(l.name))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _updateSelectedLedger(val);
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              SegmentedButton<int>(
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
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _selectedCurrency,
                  decoration: const InputDecoration(
                    labelText: '币种',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'CNY', child: Text('CNY')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                    DropdownMenuItem(value: 'JPY', child: Text('JPY')),
                    DropdownMenuItem(value: 'THB', child: Text('THB')),
                  ],
                  onChanged: (val) => setState(() => _selectedCurrency = val),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: '金额',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                    prefixText: '¥ ',
                  ),
                  onChanged: (val) {
                    if (val.contains('.')) {
                      final parts = val.split('.');
                      if (parts.length > 1 && parts[1].length > 2) {
                        _amountController.text = '${parts[0]}.${parts[1].substring(0, 2)}';
                        _amountController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _amountController.text.length),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 24),
          if (_selectedLedgerUuid != null) ...[
            peopleAsyncValue.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, st) => Text('Error: $e'),
              data: (peoplePool) {
                final selectedLedger = widget.ledgers.firstWhere((l) => l.uuid == _selectedLedgerUuid);
                if (selectedLedger.personUuids.isEmpty) return const SizedBox.shrink();
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('人员 (多选)', style: Theme.of(context).textTheme.titleMedium),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_selectedPersonIds.length == selectedLedger.personUuids.length) {
                                _selectedPersonIds.clear();
                              } else {
                                _selectedPersonIds.addAll(selectedLedger.personUuids);
                              }
                            });
                          },
                          child: Text(
                            _selectedPersonIds.length == selectedLedger.personUuids.length ? '取消全选' : '全选',
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedLedger.personUuids.map((pid) {
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
                    const SizedBox(height: 24),
                  ],
                );
              }
            )
          ],
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: '备注（选填）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
            ),
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: peopleAsyncValue.maybeWhen(
            data: (peoplePool) => FilledButton.icon(
              onPressed: () => _saveTransaction(peoplePool),
              icon: const Icon(Icons.check),
              label: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('保存记账', style: TextStyle(fontSize: 18)),
              ),
            ),
            orElse: () => const FilledButton(onPressed: null, child: Text('Loading...')),
          ),
        ),
      ],
    );
  }
}
