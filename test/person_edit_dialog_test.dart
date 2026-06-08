import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simon_ledger_flutter/core/theme/app_theme.dart';
import 'package:simon_ledger_flutter/features/people_pool/presentation/widgets/person_edit_dialog.dart';

void main() {
  testWidgets('person edit dialog uses preview first tonal avatar choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: PersonEditDialog()),
      ),
    );

    expect(
      find.byKey(const ValueKey('person-dialog-avatar-preview')),
      findsOneWidget,
    );
    expect(find.text('选择头像'), findsOneWidget);
    expect(find.text('确定'), findsNothing);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);

    final avatarChips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(avatarChips, isNotEmpty);
    for (final chip in avatarChips) {
      expect(chip.side, BorderSide.none);
      expect(chip.showCheckmark, isFalse);
    }
  });
}
