import 'package:flutter/material.dart';
import '../../../../core/models/person.dart';

class PersonEditDialog extends StatefulWidget {
  const PersonEditDialog({super.key, this.person});

  final Person? person;

  @override
  State<PersonEditDialog> createState() => _PersonEditDialogState();
}

class _PersonEditDialogState extends State<PersonEditDialog> {
  late final TextEditingController _nameController;
  late String _selectedAvatar;

  final List<String> _avatars = [
    '🧑',
    '😎',
    '👨‍💻',
    '👩‍💻',
    '🐱',
    '🐶',
    '🦊',
    '🐻',
    '🐼',
    '🐯',
    '🦁',
    '🐷',
    '🐸',
    '🐵',
    '🦝',
    '🦐',
    '🦇',
    '🐌',
    '🐜',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person?.name ?? '');
    _selectedAvatar = widget.person?.avatar ?? _avatars.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _nameController.text.trim().isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        widget.person == null
            ? Icons.person_add_alt_1_rounded
            : Icons.manage_accounts_rounded,
        color: colorScheme.primary,
      ),
      title: Text(widget.person == null ? '新增人员' : '编辑人员'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择头像', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _avatars.map((avatar) {
                final isSelected = avatar == _selectedAvatar;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAvatar = avatar),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(avatar, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameController,
              autofocus: widget.person == null,
              decoration: const InputDecoration(
                labelText: '人员名称',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () {
                  final name = _nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.of(context).pop(
                      Person()
                        ..uuid =
                            widget.person?.uuid ??
                            DateTime.now().microsecondsSinceEpoch.toString()
                        ..name = name
                        ..avatar = _selectedAvatar,
                    );
                  }
                }
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
