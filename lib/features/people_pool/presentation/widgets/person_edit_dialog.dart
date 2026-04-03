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
  
  final List<String> _avatars = ['🧑', '😎', '👨‍💻', '👩‍💻', '🐱', '🐶', '🦊', '🐻', '🐼', '🐯', '🦁', '🐷', '🐸', '🐵','🦝','🦐','🦇','🐌','🐜'];

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
    return AlertDialog(
      title: Text(widget.person == null ? '新增人员' : '编辑人员'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择头像:'),
            const SizedBox(height: 8),
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
                      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      ),
                    ),
                    child: Text(avatar, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: widget.person == null,
              decoration: const InputDecoration(
                labelText: '人员名称',
                border: OutlineInputBorder(),
              ),
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
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isNotEmpty) {
              Navigator.of(context).pop(Person()
                ..uuid = widget.person?.uuid ?? DateTime.now().microsecondsSinceEpoch.toString()
                ..name = name
                ..avatar = _selectedAvatar
              );
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
