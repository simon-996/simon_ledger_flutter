import 'package:flutter/material.dart';

import '../../../../core/models/ai_draft.dart';
import '../../../../core/models/person.dart';

/// Keep original speech and resolution actions out of input labels.
class AiPersonResolution extends StatelessWidget {
  const AiPersonResolution({
    super.key,
    required this.match,
    required this.people,
    required this.busy,
    required this.onSelected,
    required this.onIgnore,
    this.missingIdentity = false,
  });

  final AiPersonMatch match;
  final List<Person> people;
  final bool busy;
  final ValueChanged<String> onSelected;
  final VoidCallback onIgnore;
  final bool missingIdentity;

  @override
  Widget build(BuildContext context) {
    final suggested = match.candidatePersonUuids.toSet();
    final options = [
      ...people.where((person) => suggested.contains(person.uuid)),
      ...people.where((person) => !suggested.contains(person.uuid)),
    ];
    final role = match.role == 'payer' ? '付款人' : '承担人';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('“${match.sourceName}”的$role尚未确认，请选择账本人员。'),
          if (missingIdentity) const Text('这位人员当前不在账本中，请重新选择'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: InputDecoration(labelText: '选择$role'),
            items: options
                .map(
                  (person) => DropdownMenuItem(
                    value: person.uuid,
                    child: Text(person.name),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) onSelected(value);
                  },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: busy ? null : onIgnore,
              child: const Text('忽略本次识别'),
            ),
          ),
        ],
      ),
    );
  }
}
