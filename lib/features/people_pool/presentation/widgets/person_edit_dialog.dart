import 'package:flutter/material.dart';

import '../../../../core/config/avatar_config.dart';
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person?.name ?? '');
    _selectedAvatar = AvatarConfig.normalizeAvatar(widget.person?.avatar ?? '');
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
      title: Text(widget.person == null ? '新增人员' : '编辑人员'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                key: const ValueKey('person-dialog-avatar-preview'),
                width: 82,
                height: 82,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _selectedAvatar,
                  style: const TextStyle(fontSize: 38),
                ),
              ),
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
            const SizedBox(height: 18),
            Text(
              '选择头像',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AvatarConfig.avatars.map((avatar) {
                return ChoiceChip(
                  label: SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: Text(avatar, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  showCheckmark: false,
                  side: BorderSide.none,
                  selected: avatar == _selectedAvatar,
                  onSelected: (_) => setState(() => _selectedAvatar = avatar),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: canSubmit
                    ? () {
                        final name = _nameController.text.trim();
                        if (name.isNotEmpty) {
                          Navigator.of(context).pop(
                            Person()
                              ..uuid =
                                  widget.person?.uuid ??
                                  DateTime.now().microsecondsSinceEpoch
                                      .toString()
                              ..name = name
                              ..avatar = _selectedAvatar
                              ..linkedUserUuid = widget.person?.linkedUserUuid,
                          );
                        }
                      }
                    : null,
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
