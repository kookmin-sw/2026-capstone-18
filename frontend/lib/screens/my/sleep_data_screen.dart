import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../core/widgets/soft_primary_button.dart';
import '../../features/sleep/models/sleep_log.dart';
import '../../features/sleep/services/sleep_insight_service.dart';
import '../../features/sleep/sleep_provider.dart';

class SleepDataScreen extends StatefulWidget {
  const SleepDataScreen({super.key});

  @override
  State<SleepDataScreen> createState() => _SleepDataScreenState();
}

class _SleepDataScreenState extends State<SleepDataScreen> {
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  bool _syncingSleep = false;

  @override
  void initState() {
    super.initState();

    final today = DateUtils.dateOnly(DateTime.now());
    _rangeStart = today.subtract(const Duration(days: 6));
    _rangeEnd = today;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSelectedRange();
    });
  }

  Future<void> _loadSelectedRange() {
    return context.read<SleepProvider>().load(
      start: _rangeStart,
      end: _rangeEnd,
    );
  }

  Future<void> _syncSleepFromHealthData() async {
    if (_syncingSleep) return;

    final sleepProvider = context.read<SleepProvider>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _syncingSleep = true;
    });

    try {
      final synced = await sleepProvider.syncSleepFromGalaxyWatch();
      if (!mounted) return;

      if (synced) {
        await _loadSelectedRange();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('건강 데이터에서 수면 기록을 불러왔어요.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              sleepProvider.errorMessage ?? '수면 데이터를 동기화하지 못했어요. 다시 시도해 주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncingSleep = false;
        });
      }
    }
  }

  Future<DateTime?> _pickDate({
    required DateTime initialDate,
    required String title,
  }) async {
    final today = _dateOnly(DateTime.now());
    final firstDate = DateTime(2020);
    var selectedDate = _dateOnly(initialDate);
    var visibleMonth = DateTime(selectedDate.year, selectedDate.month);

    if (selectedDate.isBefore(firstDate)) {
      selectedDate = firstDate;
      visibleMonth = DateTime(selectedDate.year, selectedDate.month);
    } else if (selectedDate.isAfter(today)) {
      selectedDate = today;
      visibleMonth = DateTime(selectedDate.year, selectedDate.month);
    }

    return showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          backgroundColor: const Color(0xFFFFF9FB),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF201C28),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF9888A0),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _SleepCalendar(
                      selectedDate: selectedDate,
                      visibleMonth: visibleMonth,
                      firstDate: firstDate,
                      lastDate: today,
                      onMonthChanged: (month) {
                        setDialogState(() {
                          visibleMonth = month;
                        });
                      },
                      onDateChanged: (date) {
                        setDialogState(() {
                          selectedDate = _dateOnly(date);
                          visibleMonth = DateTime(date.year, date.month);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F0F4),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _formatDate(selectedDate),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFB87888),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFF0E1E8)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('취소'),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFB87888),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, selectedDate),
                          child: const Text('확인'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _pickRangeBoundary({required bool isStart}) async {
    final picked = await _pickDate(
      initialDate: isStart ? _rangeStart : _rangeEnd,
      title: isStart ? '시작 날짜' : '종료 날짜',
    );

    if (picked == null || !mounted) return;

    setState(() {
      final selectedDate = _dateOnly(picked);
      if (isStart) {
        _rangeStart = selectedDate;
        if (_rangeStart.isAfter(_rangeEnd)) _rangeEnd = _rangeStart;
      } else {
        _rangeEnd = selectedDate;
        if (_rangeEnd.isBefore(_rangeStart)) _rangeStart = _rangeEnd;
      }
    });

    await _loadSelectedRange();
  }

  @override
  Widget build(BuildContext context) {
    final sleepProvider = context.watch<SleepProvider>();
    final latestInRange = sleepProvider.latestLog;
    final records = sleepProvider.history;
    final sleepInsight = const SleepInsightService().buildInsight(
      records: records,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: RefreshIndicator(
          color: const Color(0xFFB87888),
          onRefresh: _loadSelectedRange,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 20,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Header(title: '수면 데이터'),
                          const SizedBox(height: 18),
                          _SleepRangeSelector(
                            start: _rangeStart,
                            end: _rangeEnd,
                            onSelectStart: () =>
                                _pickRangeBoundary(isStart: true),
                            onSelectEnd: () =>
                                _pickRangeBoundary(isStart: false),
                          ),
                          const SizedBox(height: 16),

                          if (sleepProvider.loading)
                            const Expanded(
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.all(28),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFB87888),
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            if (sleepProvider.errorMessage != null) ...[
                              _GlassCard(
                                child: Text(
                                  sleepProvider.errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFB87888),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            if (latestInRange != null)
                              _LatestSleepCard(sleepLog: latestInRange)
                            else
                              _LatestSleepEmptyCard(
                                isSyncing: _syncingSleep,
                                onSync: _syncSleepFromHealthData,
                              ),
                            if (records.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _SleepSummaryCard(records: records),
                            ],
                            const SizedBox(height: 12),
                            _SleepInsightCard(insight: sleepInsight),
                            const SizedBox(height: 12),
                            _SleepHistoryCard(history: records),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LatestSleepCard extends StatelessWidget {
  final SleepLog sleepLog;

  const _LatestSleepCard({required this.sleepLog});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '선택 기간의 최근 수면'),
          const SizedBox(height: 12),
          const Text(
            '총 수면 시간',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF9888A0),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 3),
          Text(sleepLog.durationLabel, style: AppTextStyles.metricNumber),
          const SizedBox(height: 12),
          _SleepInfoRow(label: '날짜', value: _formatDate(sleepLog.endedOn)),
          _SleepInfoRow(
            label: '잠든 시간',
            value: _formatTime(sleepLog.fellAsleepAt),
          ),
          _SleepInfoRow(label: '일어난 시간', value: _formatTime(sleepLog.wokeUpAt)),
        ],
      ),
    );
  }
}

class _LatestSleepEmptyCard extends StatelessWidget {
  final bool isSyncing;
  final Future<void> Function() onSync;

  const _LatestSleepEmptyCard({required this.isSyncing, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '선택 기간의 최근 수면'),
          const SizedBox(height: 12),
          const Text(
            '선택한 기간의 수면 기록이 아직 없어요.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF9888A0),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          SoftPrimaryButton(
            text: '건강 데이터에서 불러오기',
            onTap: isSyncing ? null : onSync,
            isLoading: isSyncing,
            height: 38,
            fullWidth: false,
          ),
        ],
      ),
    );
  }
}

class _SleepInsightCard extends StatelessWidget {
  final String insight;

  const _SleepInsightCard({required this.insight});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '수면 패턴'),
          const SizedBox(height: 8),
          Text(
            insight,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF9888A0),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepSummaryCard extends StatelessWidget {
  final List<SleepLog> records;

  const _SleepSummaryCard({required this.records});

  @override
  Widget build(BuildContext context) {
    final rangeAverageHours =
        records.fold<double>(0, (sum, record) => sum + record.durationHours) /
        records.length;
    final sortedByDuration = [...records]
      ..sort((a, b) => b.durationHours.compareTo(a.durationHours));
    final longest = sortedByDuration.first;
    final shortest = sortedByDuration.last;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '선택 기간 요약'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SleepMetricItem(
                  label: '평균 수면',
                  value: _durationLabelFromHours(rangeAverageHours),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SleepMetricItem(
                  label: '총 기록 수',
                  value: '${records.length}개',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SleepMetricItem(
                  label: '가장 긴 수면',
                  value: longest.durationLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SleepMetricItem(
                  label: '가장 짧은 수면',
                  value: shortest.durationLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SleepMetricItem extends StatelessWidget {
  final String label;
  final String value;

  const _SleepMetricItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F0F4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF9888A0)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF201C28),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _SleepInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9888A0),
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF201C28),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepHistoryCard extends StatelessWidget {
  final List<SleepLog> history;

  const _SleepHistoryCard({required this.history});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '최근 수면 기록'),
          const SizedBox(height: 6),
          const Text(
            '선택한 기간의 수면 기록을 모두 보여줍니다.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF9888A0),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),

          if (history.isEmpty)
            const Text(
              '선택한 기간의 수면 기록이 아직 없어요.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF9888A0),
                height: 1.5,
              ),
            )
          else ...[
            ...history.map((sleepLog) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_formatDate(sleepLog.endedOn)}\n${_formatTime(sleepLog.fellAsleepAt)} - ${_formatTime(sleepLog.wokeUpAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9888A0),
                          height: 1.45,
                        ),
                      ),
                    ),
                    Text(
                      sleepLog.durationLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF201C28),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _SleepRangeSelector extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final VoidCallback onSelectStart;
  final VoidCallback onSelectEnd;

  const _SleepRangeSelector({
    required this.start,
    required this.end,
    required this.onSelectStart,
    required this.onSelectEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_rangeTitle(start, end), style: AppTextStyles.cardTitle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RangeDateField(
                  label: '시작',
                  date: start,
                  onTap: onSelectStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RangeDateField(
                  label: '종료',
                  date: end,
                  onTap: onSelectEnd,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RangeDateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _RangeDateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryLight.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textL,
                      ),
                    ),
                    Text(
                      koYearMonthDay(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textH,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepCalendar extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime visibleMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime> onMonthChanged;

  const _SleepCalendar({
    required this.selectedDate,
    required this.visibleMonth,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
    required this.onMonthChanged,
  });

  @override
  State<_SleepCalendar> createState() => _SleepCalendarState();
}

class _SleepCalendarState extends State<_SleepCalendar> {
  _CalendarPanel _panel = _CalendarPanel.days;

  static const List<String> _monthNames = [
    '1월',
    '2월',
    '3월',
    '4월',
    '5월',
    '6월',
    '7월',
    '8월',
    '9월',
    '10월',
    '11월',
    '12월',
  ];

  static const List<String> _weekDays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    final month = DateTime(widget.visibleMonth.year, widget.visibleMonth.month);
    final previousMonth = DateTime(month.year, month.month - 1);
    final nextMonth = DateTime(month.year, month.month + 1);

    final canGoBack = !previousMonth.isBefore(
      DateTime(widget.firstDate.year, widget.firstDate.month),
    );
    final canGoForward = !nextMonth.isAfter(
      DateTime(widget.lastDate.year, widget.lastDate.month),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              _MonthButton(
                icon: Icons.chevron_left,
                enabled: _panel == _CalendarPanel.days && canGoBack,
                onTap: () => widget.onMonthChanged(previousMonth),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PickerChip(
                      label: _monthNames[month.month - 1],
                      selected: _panel == _CalendarPanel.months,
                      onTap: () => _togglePanel(_CalendarPanel.months),
                    ),
                    const SizedBox(width: 8),
                    _PickerChip(
                      label: '${month.year}',
                      selected: _panel == _CalendarPanel.years,
                      onTap: () => _togglePanel(_CalendarPanel.years),
                    ),
                  ],
                ),
              ),
              _MonthButton(
                icon: Icons.chevron_right,
                enabled: _panel == _CalendarPanel.days && canGoForward,
                onTap: () => widget.onMonthChanged(nextMonth),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_panel) {
            _CalendarPanel.months => _MonthGrid(
              key: const ValueKey('months'),
              selectedMonth: month.month,
              minMonth: month.year == widget.firstDate.year
                  ? widget.firstDate.month
                  : 1,
              maxMonth: month.year == widget.lastDate.year
                  ? widget.lastDate.month
                  : 12,
              monthNames: _monthNames,
              onMonthSelected: (selectedMonth) {
                widget.onMonthChanged(DateTime(month.year, selectedMonth));
                setState(() {
                  _panel = _CalendarPanel.days;
                });
              },
            ),
            _CalendarPanel.years => _YearGrid(
              key: const ValueKey('years'),
              selectedYear: month.year,
              firstYear: widget.firstDate.year,
              lastYear: widget.lastDate.year,
              onYearSelected: (year) {
                widget.onMonthChanged(_monthForYear(month, year));
                setState(() {
                  _panel = _CalendarPanel.days;
                });
              },
            ),
            _CalendarPanel.days => Column(
              key: const ValueKey('days'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: _weekDays.map((day) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFC0B0C0),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  children: _buildDayTiles(month),
                ),
              ],
            ),
          },
        ),
      ],
    );
  }

  void _togglePanel(_CalendarPanel panel) {
    setState(() {
      _panel = _panel == panel ? _CalendarPanel.days : panel;
    });
  }

  List<Widget> _buildDayTiles(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmptyDays = firstDayOfMonth.weekday % 7;
    final totalCells = ((leadingEmptyDays + daysInMonth + 6) ~/ 7) * 7;

    return List.generate(totalCells, (index) {
      final dayNumber = index - leadingEmptyDays + 1;

      if (dayNumber < 1 || dayNumber > daysInMonth) {
        return const SizedBox.shrink();
      }

      final date = DateTime(month.year, month.month, dayNumber);
      final isDisabled =
          date.isBefore(_dateOnly(widget.firstDate)) ||
          date.isAfter(_dateOnly(widget.lastDate));
      final isSelected = _isSameDay(date, widget.selectedDate);
      final isToday = _isSameDay(date, DateTime.now());

      return _DayTile(
        key: ValueKey(
          'sleep-calendar-day-${date.year}-${date.month}-${date.day}',
        ),
        day: dayNumber,
        isSelected: isSelected,
        isToday: isToday,
        isDisabled: isDisabled,
        onTap: isDisabled ? null : () => widget.onDateChanged(date),
      );
    });
  }

  DateTime _monthForYear(DateTime month, int year) {
    final changedMonth = DateTime(year, month.month);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);

    if (changedMonth.isBefore(firstMonth)) return firstMonth;
    if (changedMonth.isAfter(lastMonth)) return lastMonth;

    return changedMonth;
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

enum _CalendarPanel { days, months, years }

class _PickerChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PickerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFB87888) : const Color(0xFFF8F0F4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFB87888) : const Color(0xFFF0E1E8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: selected ? Colors.white : const Color(0xFF201C28),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              selected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: selected ? Colors.white : const Color(0xFFB87888),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final int selectedMonth;
  final int minMonth;
  final int maxMonth;
  final List<String> monthNames;
  final ValueChanged<int> onMonthSelected;

  const _MonthGrid({
    super.key,
    required this.selectedMonth,
    required this.minMonth,
    required this.maxMonth,
    required this.monthNames,
    required this.onMonthSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        itemCount: 12,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.25,
        ),
        itemBuilder: (context, index) {
          final month = index + 1;
          final isSelected = month == selectedMonth;
          final isDisabled = month < minMonth || month > maxMonth;

          return _PickerGridTile(
            label: monthNames[index].substring(0, 3),
            selected: isSelected,
            disabled: isDisabled,
            onTap: isDisabled ? null : () => onMonthSelected(month),
          );
        },
      ),
    );
  }
}

class _YearGrid extends StatelessWidget {
  final int selectedYear;
  final int firstYear;
  final int lastYear;
  final ValueChanged<int> onYearSelected;

  const _YearGrid({
    super.key,
    required this.selectedYear,
    required this.firstYear,
    required this.lastYear,
    required this.onYearSelected,
  });

  @override
  Widget build(BuildContext context) {
    final years = List<int>.generate(
      lastYear - firstYear + 1,
      (index) => firstYear + index,
    );

    return SizedBox(
      height: 242,
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        itemCount: years.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.25,
        ),
        itemBuilder: (context, index) {
          final year = years[index];
          final isSelected = year == selectedYear;

          return _PickerGridTile(
            label: '$year',
            selected: isSelected,
            onTap: () => onYearSelected(year),
          );
        },
      ),
    );
  }
}

class _PickerGridTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _PickerGridTile({
    required this.label,
    required this.selected,
    this.disabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFB87888) : const Color(0xFFF8F0F4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFB87888) : const Color(0xFFF0E1E8),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: disabled
                  ? const Color(0xFFD8CCD3)
                  : selected
                  ? Colors.white
                  : const Color(0xFF201C28),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _MonthButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: 22,
        color: enabled ? const Color(0xFFB87888) : const Color(0xFFE2D5DC),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  final int day;
  final bool isSelected;
  final bool isToday;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _DayTile({
    super.key,
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDisabled
        ? const Color(0xFFD8CCD3)
        : isSelected
        ? Colors.white
        : const Color(0xFF201C28);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFB87888) : Colors.transparent,
          shape: BoxShape.circle,
          border: isToday && !isSelected
              ? Border.all(color: const Color(0xFFB87888), width: 1)
              : null,
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight: isSelected || isToday
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;

  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back, color: Color(0xFF201C28)),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: Color(0xFF201C28),
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;

  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(padding: const EdgeInsets.all(16), child: child);
  }
}

String _formatDate(DateTime date) {
  return koFullDate(date);
}

String _formatTime(DateTime date) {
  return koTime(date);
}

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String _rangeTitle(DateTime start, DateTime end) {
  final today = DateUtils.dateOnly(DateTime.now());
  final defaultStart = today.subtract(const Duration(days: 6));
  if (DateUtils.isSameDay(start, defaultStart) &&
      DateUtils.isSameDay(end, today)) {
    return '최근 7일';
  }
  if (DateUtils.isSameDay(start, end)) {
    return koFullDate(start);
  }
  return '${koYearMonthDay(start)} ~ ${koYearMonthDay(end)}';
}

String _durationLabelFromHours(double hours) {
  final minutes = (hours * 60).round().clamp(0, 1440).toInt();
  final hourPart = minutes ~/ 60;
  final minutePart = minutes % 60;
  if (hourPart == 0) return '$minutePart분';
  if (minutePart == 0) return '$hourPart시간';
  return '$hourPart시간 $minutePart분';
}
