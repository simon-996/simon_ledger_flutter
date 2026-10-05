import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Changing the day keeps the displayed time and finer precision.
DateTime transactionDateOnDay(DateTime day, DateTime previous) {
  final time = previous.toLocal();
  return DateTime(
    day.year,
    day.month,
    day.day,
    time.hour,
    time.minute,
    time.second,
    time.millisecond,
    time.microsecond,
  );
}

DateTime transactionDateAtTime(DateTime previous, TimeOfDay time) {
  final local = previous.toLocal();
  return DateTime(
    local.year,
    local.month,
    local.day,
    time.hour,
    time.minute,
    local.second,
    local.millisecond,
    local.microsecond,
  );
}

String _dayLabel(DateTime date, DateTime today) {
  for (var offset = 0; offset < 3; offset++) {
    if (DateUtils.isSameDay(date, DateUtils.addDaysToDate(today, -offset))) {
      return const ['今天', '昨天', '前天'][offset];
    }
  }
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class TransactionDateControl extends StatelessWidget {
  const TransactionDateControl({
    super.key,
    required this.date,
    required this.onChanged,
    this.enabled = true,
    this.hasTime = true,
    this.onTimePrecisionChanged,
  });

  final DateTime? date;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  final bool hasTime;
  final ValueChanged<bool>? onTimePrecisionChanged;

  Future<void> _open(BuildContext context) async {
    final now = DateTime.now();
    final value = (date ?? now).toLocal();
    Widget picker(BuildContext context) => _TransactionDatePicker(
      initial: value,
      hasTime: hasTime,
      today: now,
      allowDateOnly: onTimePrecisionChanged != null,
    );
    final _DateSelection? selection;
    if (MediaQuery.sizeOf(context).width >= 720) {
      final box = context.findRenderObject()! as RenderBox;
      final anchor = box.localToGlobal(Offset(0, box.size.height));
      selection = await showDialog<_DateSelection>(
        context: context,
        builder: (context) => LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(440.0, constraints.maxWidth - 32);
            final available =
                constraints.maxHeight - MediaQuery.viewInsetsOf(context).bottom;
            final left = anchor.dx.clamp(
              16.0,
              constraints.maxWidth - width - 16,
            );
            final top = (anchor.dy + 8)
                .clamp(16.0, math.max(16.0, available - 540))
                .toDouble();
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: width,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: math.max(0, available - top - 16),
                      ),
                      child: picker(context),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      selection = await showModalBottomSheet<_DateSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(
                0,
                MediaQuery.sizeOf(context).height * .9 -
                    MediaQuery.viewInsetsOf(context).bottom,
              ),
            ),
            child: picker(context),
          ),
        ),
      );
    }
    if (!context.mounted || selection == null) return;
    // Opening and completing without an edit must not freeze "now".
    if (selection.changed) {
      onTimePrecisionChanged?.call(selection.hasTime);
      onChanged(selection.date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = (date ?? DateTime.now()).toLocal();
    final time = !hasTime
        ? '未指定时间'
        : date == null
        ? '现在'
        : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('transaction-date-control'),
        icon: const Icon(Icons.event_outlined, size: 18),
        label: Text('${_dayLabel(value, DateTime.now())} · $time'),
        onPressed: enabled ? () => _open(context) : null,
      ),
    );
  }
}

class _DateSelection {
  const _DateSelection(this.date, this.hasTime, this.changed);
  final DateTime date;
  final bool hasTime;
  final bool changed;
}

class _TransactionDatePicker extends StatefulWidget {
  const _TransactionDatePicker({
    required this.initial,
    required this.hasTime,
    required this.today,
    required this.allowDateOnly,
  });
  final DateTime initial;
  final bool hasTime;
  final DateTime today;
  final bool allowDateOnly;
  @override
  State<_TransactionDatePicker> createState() => _TransactionDatePickerState();
}

class _TransactionDatePickerState extends State<_TransactionDatePicker> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  late bool _hasTime;
  late final TextEditingController _hour;
  late final TextEditingController _minute;
  bool _changed = false;
  bool _calendar = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initial;
    _hasTime = widget.hasTime;
    _hour = TextEditingController(text: _date.hour.toString().padLeft(2, '0'));
    _minute = TextEditingController(
      text: _date.minute.toString().padLeft(2, '0'),
    );
  }

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  void _chooseDay(DateTime day) => setState(() {
    _date = transactionDateOnDay(day, _date);
    _changed = true;
  });

  void _complete() {
    if (_hasTime && !_form.currentState!.validate()) return;
    final selected = _hasTime
        ? transactionDateAtTime(
            _date,
            TimeOfDay(
              hour: int.parse(_hour.text),
              minute: int.parse(_minute.text),
            ),
          )
        : _date;
    Navigator.pop(context, _DateSelection(selected, _hasTime, _changed));
  }

  Widget _timeField(TextEditingController controller, bool hour) => Expanded(
    child: TextFormField(
      key: ValueKey(
        hour ? 'transaction-hour-input' : 'transaction-minute-input',
      ),
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      textInputAction: hour ? TextInputAction.next : TextInputAction.done,
      decoration: InputDecoration(
        labelText: hour ? '小时' : '分钟',
        helperText: hour ? '00–23' : '00–59',
      ),
      onChanged: (_) => _changed = true,
      onFieldSubmitted: hour ? null : (_) => _complete(),
      validator: (value) {
        final number = int.tryParse(value ?? '');
        if (number == null || number < 0 || number > (hour ? 23 : 59)) {
          return hour ? '小时需为 00–23' : '分钟需为 00–59';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(widget.today);
    final firstDate = DateTime(_date.year < 2000 ? _date.year : 2000);
    final initialDay = _date.isAfter(today) ? today : _date;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return SafeArea(
      top: false,
      child: Padding(
        key: const ValueKey('transaction-date-picker'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('记账时间', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var offset = 0; offset < 3; offset++)
                            ChoiceChip(
                              label: Text(const ['今天', '昨天', '前天'][offset]),
                              selected: DateUtils.isSameDay(
                                _date,
                                DateUtils.addDaysToDate(today, -offset),
                              ),
                              onSelected: (_) => _chooseDay(
                                DateUtils.addDaysToDate(today, -offset),
                              ),
                            ),
                        ],
                      ),
                      TextButton.icon(
                        key: const ValueKey('transaction-calendar-toggle'),
                        onPressed: () => setState(() => _calendar = !_calendar),
                        icon: Icon(
                          _calendar
                              ? Icons.expand_less
                              : Icons.calendar_month_outlined,
                        ),
                        label: Text('其他日期 · ${_dayLabel(_date, today)}'),
                      ),
                      if (_calendar)
                        CalendarDatePicker(
                          key: ValueKey(DateUtils.dateOnly(initialDay)),
                          initialDate: initialDay,
                          firstDate: firstDate,
                          lastDate: today,
                          onDateChanged: _chooseDay,
                        ),
                      if (widget.allowDateOnly)
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('指定时间'),
                          subtitle: Text(_hasTime ? '24 小时制' : '仅记录日期'),
                          value: _hasTime,
                          onChanged: (value) => setState(() {
                            _hasTime = value;
                            _changed = true;
                          }),
                        ),
                      if (!widget.allowDateOnly)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('时间 · 24 小时制'),
                        ),
                      if (_hasTime && ios)
                        SizedBox(
                          height: 160,
                          child: CupertinoDatePicker(
                            initialDateTime: _date,
                            mode: CupertinoDatePickerMode.time,
                            use24hFormat: true,
                            onDateTimeChanged: (value) {
                              _date = transactionDateAtTime(
                                _date,
                                TimeOfDay.fromDateTime(value),
                              );
                              _hour.text = value.hour.toString().padLeft(
                                2,
                                '0',
                              );
                              _minute.text = value.minute.toString().padLeft(
                                2,
                                '0',
                              );
                              _changed = true;
                            },
                          ),
                        ),
                      if (_hasTime && !ios)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _timeField(_hour, true),
                              const Padding(
                                padding: EdgeInsets.fromLTRB(12, 16, 12, 0),
                                child: Text(':'),
                              ),
                              _timeField(_minute, false),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _complete,
                    child: const Text('完成'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
