import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/cycle_phase_ui.dart';
import '../../core/utils/korean_ui_text.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/section_title.dart';
import '../../core/widgets/soft_primary_button.dart';
import '../../features/cycles/cycle_provider.dart';
import '../../features/health/health_connect_exception.dart';
import '../../features/health/health_connect_permission_sheet.dart';
import '../../features/home/home_provider.dart';
import '../../features/insight/insight_provider.dart';

class MyCycleScreen extends StatefulWidget {
  const MyCycleScreen({super.key});

  @override
  State<MyCycleScreen> createState() => _MyCycleScreenState();
}

class _MyCycleScreenState extends State<MyCycleScreen> {
  DateTime periodStart = DateTime.now();
  DateTime? periodEnd;
  bool _periodOngoing = false;
  bool _saving = false;
  bool _syncingCycle = false;
  DateTime? _lastCycleSyncedAt;
  String? _lastCycleSyncSource;
  _CycleSavePayload? _lastSavedPayload;
  _CycleSavePayload? _inFlightSavePayload;

  @override
  void initState() {
    super.initState();

    final currentCycle = context.read<CycleProvider>().currentCycle;
    if (currentCycle != null) {
      periodStart = _dateOnly(currentCycle.lastPeriodStart);
      periodEnd = currentCycle.periodEndDate == null
          ? null
          : _dateOnly(currentCycle.periodEndDate!);
      _periodOngoing =
          currentCycle.periodOngoing && currentCycle.periodEndDate == null;
      _lastSavedPayload = _currentSavePayload();
    }
  }

  Future<DateTime?> _pickDate({
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required String title,
  }) async {
    final today = _dateOnly(DateTime.now());
    var selectedDate = _dateOnly(initialDate);
    var visibleMonth = DateTime(selectedDate.year, selectedDate.month);

    final minDate = _dateOnly(firstDate);
    final maxDate = _dateOnly(lastDate).isAfter(today)
        ? today
        : _dateOnly(lastDate);

    if (selectedDate.isBefore(minDate)) {
      selectedDate = minDate;
      visibleMonth = DateTime(selectedDate.year, selectedDate.month);
    } else if (selectedDate.isAfter(maxDate)) {
      selectedDate = maxDate;
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
                    _CycleCalendar(
                      selectedDate: selectedDate,
                      visibleMonth: visibleMonth,
                      firstDate: minDate,
                      lastDate: maxDate,
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
                        _formatFullDate(selectedDate),
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

  Future<void> _pickPeriodStart() async {
    if (_saving) return;

    final picked = await _pickDate(
      initialDate: periodStart,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      title: '최근 생리 시작일',
    );

    if (picked == null) return;

    final normalizedPicked = _dateOnly(picked);
    if (normalizedPicked == periodStart) return;

    setState(() {
      periodStart = normalizedPicked;
      if (periodEnd != null && periodEnd!.isBefore(periodStart)) {
        periodEnd = null;
        _periodOngoing = false;
      }
    });
    await _saveCycle();
  }

  Future<void> _pickPeriodEnd() async {
    if (_saving) return;

    final picked = await _pickDate(
      initialDate: periodEnd ?? periodStart,
      firstDate: periodStart,
      lastDate: DateTime.now(),
      title: '생리 종료일',
    );

    if (picked == null) return;

    final normalizedPicked = _dateOnly(picked);
    if (normalizedPicked == periodEnd) return;

    setState(() {
      periodEnd = normalizedPicked;
      _periodOngoing = false;
    });
    await _saveCycle();
  }

  Future<void> _clearPeriodEnd() async {
    if (_saving) return;

    final previousEnd = periodEnd;
    final previousOngoing = _periodOngoing;

    setState(() {
      periodEnd = null;
      _periodOngoing = false;
    });

    final saved = await _saveCycle();
    if (!saved && mounted) {
      setState(() {
        periodEnd = previousEnd;
        _periodOngoing = previousOngoing;
      });
    }
  }

  Future<void> _setPeriodOngoing(bool value) async {
    if (_saving) return;

    final previousEnd = periodEnd;
    final previousOngoing = _periodOngoing;

    setState(() {
      _periodOngoing = value;
      if (value) {
        periodEnd = null;
      }
    });

    final saved = await _saveCycle();
    if (!saved && mounted) {
      setState(() {
        periodEnd = previousEnd;
        _periodOngoing = previousOngoing;
      });
    }
  }

  Future<void> _syncCycleFromGalaxyWatch() async {
    if (_syncingCycle || _saving) return;

    final cycleProvider = context.read<CycleProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final previousStart = periodStart;
    final previousEnd = periodEnd;
    final previousOngoing = _periodOngoing;

    setState(() {
      _syncingCycle = true;
    });

    try {
      final data = await cycleProvider.latestGalaxyWatchCycleData();

      if (!mounted) return;

      if (data == null || data.periodEnd == null) {
        setState(() {
          periodStart = previousStart;
          periodEnd = previousEnd;
          _periodOngoing = previousOngoing;
          _syncingCycle = false;
        });
        if (cycleProvider.healthSyncFailureReason ==
            HealthConnectFailureReason.permissionDenied) {
          await _requestCyclePermissionAndRetry();
          return;
        }
        final message =
            cycleProvider.errorMessage ?? '주기 데이터를 동기화하지 못했어요. 다시 시도해 주세요.';
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      setState(() {
        periodStart = _dateOnly(data.periodStart);
        periodEnd = _dateOnly(data.periodEnd!);
        _periodOngoing = false;
        _syncingCycle = false;
      });

      final saved = await _saveCycle(
        successMessage: '건강 데이터에서 주기 기록을 불러왔어요.',
        showSuccessWhenUnchanged: true,
      );
      if (saved && mounted) {
        setState(() {
          _lastCycleSyncedAt = DateTime.now();
          _lastCycleSyncSource = 'Health Connect';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        periodStart = previousStart;
        periodEnd = previousEnd;
        _periodOngoing = previousOngoing;
        _syncingCycle = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('주기 데이터를 동기화하지 못했어요. 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _requestCyclePermissionAndRetry() async {
    final shouldRequest = await showHealthConnectPermissionSheet(context);
    if (!mounted || !shouldRequest) return;

    final cycleProvider = context.read<CycleProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final granted = await cycleProvider.requestHealthConnectPermission();

    if (!mounted) return;

    if (granted) {
      await _syncCycleFromGalaxyWatch();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(cycleProvider.errorMessage ?? '건강 데이터 접근 권한이 필요해요.'),
        ),
      );
    }
  }

  Future<bool> _saveCycle({
    String successMessage = '주기 기록이 저장되었어요.',
    bool showSuccessWhenUnchanged = false,
  }) async {
    final cycleProvider = context.read<CycleProvider>();
    final homeProvider = context.read<HomeProvider>();
    final insightProvider = context.read<InsightProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final payload = _currentSavePayload();

    if (_lastSavedPayload == payload) {
      if (showSuccessWhenUnchanged) _showSnackBar(messenger, successMessage);
      return true;
    }
    if (_saving) return _inFlightSavePayload == payload;

    setState(() {
      _saving = true;
    });
    _inFlightSavePayload = payload;

    try {
      final saved = await cycleProvider.savePeriod(
        lastPeriodStart: payload.periodStart,
        periodEndDate: payload.periodEnd,
        cycleLength: payload.cycleLength,
        periodLength: payload.periodLength,
        periodOngoing: payload.periodOngoing,
      );

      if (!mounted) return false;

      if (!saved) {
        _inFlightSavePayload = null;
        setState(() {
          _saving = false;
        });
        final message = cycleProvider.errorMessage ?? '생리 주기 정보를 저장하지 못했어요.';
        _showSnackBar(messenger, message);
        return false;
      }

      _lastSavedPayload = payload;
      _inFlightSavePayload = null;

      setState(() {
        _saving = false;
      });
      _showSnackBar(messenger, successMessage);
      unawaited(_refreshRelatedProviders(homeProvider, insightProvider));
      return true;
    } catch (_) {
      if (!mounted) return false;

      _inFlightSavePayload = null;
      setState(() {
        _saving = false;
      });
      final message = cycleProvider.errorMessage ?? '생리 주기 정보를 저장하지 못했어요.';
      _showSnackBar(messenger, message);
      return false;
    }
  }

  _CycleSavePayload _currentSavePayload() {
    final cycleLength = context.read<CycleProvider>().calculatedCycleLength;
    return _CycleSavePayload(
      periodStart: _dateOnly(periodStart),
      periodEnd: periodEnd == null ? null : _dateOnly(periodEnd!),
      cycleLength: cycleLength,
      periodLength: periodLengthForCalculation,
      periodOngoing: _periodOngoing && periodEnd == null,
    );
  }

  Future<void> _refreshRelatedProviders(
    HomeProvider homeProvider,
    InsightProvider insightProvider,
  ) async {
    try {
      await Future.wait([homeProvider.refresh(), insightProvider.refresh()]);
    } catch (_) {}
  }

  void _showSnackBar(ScaffoldMessengerState messenger, String message) {
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _formatFullDate(DateTime date) {
    return koFullDate(date);
  }

  String _formatShortDate(DateTime date) {
    return koFullDate(date);
  }

  String get formattedPeriodStartDate => _formatShortDate(periodStart);

  String? get formattedPeriodEndDate {
    if (periodEnd == null) return null;
    return _formatShortDate(periodEnd!);
  }

  int get periodLengthForCalculation {
    if (periodEnd == null) return 7;

    final length =
        _dateOnly(periodEnd!).difference(_dateOnly(periodStart)).inDays + 1;

    return length < 1 ? 1 : length;
  }

  int _cycleDay(int cycleLength) {
    final diff = _dateOnly(
      DateTime.now(),
    ).difference(_dateOnly(periodStart)).inDays;

    if (diff < 0) return 1;

    return (diff % cycleLength) + 1;
  }

  String _currentPhase(int cycleDay, int periodLength) {
    if (_periodOngoing && periodEnd == null) {
      return 'menstrual';
    }

    final effectivePeriodLength = periodEnd == null ? 7 : periodLength;

    if (cycleDay <= effectivePeriodLength) {
      return 'menstrual';
    }
    if (cycleDay <= 13) {
      return 'follicular';
    }
    if (cycleDay <= 16) {
      return 'ovulation';
    }
    return 'luteal';
  }

  int _daysUntilNextPeriod(int cycleDay, int cycleLength) {
    final remaining = cycleLength - cycleDay + 1;
    return remaining == cycleLength ? 0 : remaining;
  }

  @override
  Widget build(BuildContext context) {
    final cycleProvider = context.watch<CycleProvider>();
    final cycleLength = cycleProvider.calculatedCycleLength;

    final periodLength = periodLengthForCalculation;
    final cycleDay = _cycleDay(cycleLength);
    final currentPhase = _currentPhase(cycleDay, periodLength);
    final currentPhaseUi = CyclePhaseUi.of(currentPhase);
    final daysUntilNextPeriod = _daysUntilNextPeriod(cycleDay, cycleLength);
    final progress = (cycleDay / cycleLength).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppGradientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Header(title: '생리 주기 기록'),
                      const SizedBox(height: AppSpacing.lg),

                      const SectionTitle(title: '최근 생리 시작일'),
                      const SizedBox(height: AppSpacing.sm),
                      _DateField(
                        date: formattedPeriodStartDate,
                        onTap: _saving ? null : _pickPeriodStart,
                      ),

                      const SizedBox(height: 18),

                      const SectionTitle(
                        title: '생리 종료일',
                        trailing: _OptionalBadge(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _DateField(
                        date: formattedPeriodEndDate ?? '선택할 수 있어요',
                        isPlaceholder: periodEnd == null,
                        onTap: _saving ? null : _pickPeriodEnd,
                        onClear: _saving || periodEnd == null
                            ? null
                            : () => _clearPeriodEnd(),
                      ),

                      if (periodEnd == null) ...[
                        const SizedBox(height: 10),
                        _OngoingPeriodToggle(
                          value: _periodOngoing,
                          onChanged: _saving ? null : _setPeriodOngoing,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _periodOngoing
                              ? '생리가 이어지는 동안에는 생리기로 표시돼요.'
                              : '종료일을 비워두면 기본 주기 기준으로 단계를 계산해요.',
                          style: AppTextStyles.caption,
                        ),
                      ],

                      const SizedBox(height: 18),

                      _WatchSyncSection(
                        onSync: _syncCycleFromGalaxyWatch,
                        isSyncing: _syncingCycle,
                        isDisabled: _saving,
                        lastSyncedAt: _lastCycleSyncedAt,
                        sourceLabel: _lastCycleSyncSource,
                      ),

                      const SizedBox(height: 24),

                      _PhaseCard(
                        phase: currentPhaseUi.label,
                        phaseContext: currentPhaseUi.description,
                        cycleDay: cycleDay,
                        daysUntilNextPeriod: daysUntilNextPeriod,
                        progress: progress,
                        color: currentPhaseUi.color,
                      ),

                      if (_saving) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '주기 기록을 저장하고 있어요.',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CycleSavePayload {
  final DateTime periodStart;
  final DateTime? periodEnd;
  final int cycleLength;
  final int periodLength;
  final bool periodOngoing;

  const _CycleSavePayload({
    required this.periodStart,
    required this.periodEnd,
    required this.cycleLength,
    required this.periodLength,
    required this.periodOngoing,
  });

  @override
  bool operator ==(Object other) {
    return other is _CycleSavePayload &&
        other.periodStart == periodStart &&
        other.periodEnd == periodEnd &&
        other.cycleLength == cycleLength &&
        other.periodLength == periodLength &&
        other.periodOngoing == periodOngoing;
  }

  @override
  int get hashCode => Object.hash(
    periodStart,
    periodEnd,
    cycleLength,
    periodLength,
    periodOngoing,
  );
}

class _CycleCalendar extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime visibleMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime> onMonthChanged;

  const _CycleCalendar({
    required this.selectedDate,
    required this.visibleMonth,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
    required this.onMonthChanged,
  });

  @override
  State<_CycleCalendar> createState() => _CycleCalendarState();
}

class _CycleCalendarState extends State<_CycleCalendar> {
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
          'cycle-calendar-day-${date.year}-${date.month}-${date.day}',
        ),
        day: dayNumber,
        isSelected: isSelected,
        isToday: isToday,
        isDisabled: isDisabled,
        onTap: isDisabled ? null : () => widget.onDateChanged(date),
      );
    });
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
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
            fontWeight: FontWeight.w600,
            color: Color(0xFF201C28),
          ),
        ),
      ],
    );
  }
}

class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F0F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '선택',
        style: TextStyle(
          fontSize: 10,
          color: Color(0xFFB87888),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String date;
  final bool isPlaceholder;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  const _DateField({
    required this.date,
    this.isPlaceholder = false,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        borderRadius: 22,
        child: Row(
          children: [
            Expanded(
              child: Text(
                date,
                style: TextStyle(
                  fontSize: 15,
                  color: isPlaceholder
                      ? const Color(0xFFC0B0C0)
                      : const Color(0xFF201C28),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null) ...[
              GestureDetector(
                key: const ValueKey('period-end-clear-button'),
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: Color(0xFFC0B0C0)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.calendar_month_outlined,
              size: 20,
              color: Color(0xFFC08A9A),
            ),
          ],
        ),
      ),
    );
  }
}

class _OngoingPeriodToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _OngoingPeriodToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final foregroundColor = value ? AppColors.primary : AppColors.textM;
    final backgroundColor = value
        ? AppColors.primaryLight
        : Colors.white.withValues(alpha: 0.72);

    return GestureDetector(
      key: const ValueKey('period-ongoing-toggle'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.62,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: value
                  ? AppColors.primary.withValues(alpha: 0.24)
                  : const Color(0xFFF0E1E8),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '아직 생리 중이에요',
                  style: AppTextStyles.body.copyWith(
                    color: value ? AppColors.textH : AppColors.textB,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 44,
                height: 26,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? AppColors.primary : const Color(0xFFEDE3EA),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: value
                      ? Icon(Icons.check, size: 14, color: foregroundColor)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchSyncSection extends StatelessWidget {
  final Future<void> Function() onSync;
  final bool isSyncing;
  final bool isDisabled;
  final DateTime? lastSyncedAt;
  final String? sourceLabel;

  const _WatchSyncSection({
    required this.onSync,
    required this.isSyncing,
    required this.isDisabled,
    required this.lastSyncedAt,
    required this.sourceLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE8EB),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              size: 20,
              color: Color(0xFFB87888),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('건강 데이터와 동기화', style: AppTextStyles.cardTitle),
                const SizedBox(height: 5),
                const Text(
                  'Health Connect의 생리 주기 기록을 불러와요.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 8),
                _SyncStatusLine(
                  lastSyncedAt: lastSyncedAt,
                  sourceLabel: sourceLabel,
                ),
                const SizedBox(height: 12),
                SoftPrimaryButton(
                  text: '동기화하기',
                  onTap: isSyncing || isDisabled ? null : onSync,
                  isLoading: isSyncing,
                  fullWidth: false,
                  height: 36,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusLine extends StatelessWidget {
  final DateTime? lastSyncedAt;
  final String? sourceLabel;

  const _SyncStatusLine({
    required this.lastSyncedAt,
    required this.sourceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final syncedAt = lastSyncedAt;
    final source = sourceLabel ?? 'Health Connect';
    final text = syncedAt == null
        ? '$source 기반 데이터'
        : '마지막 동기화: ${_relativeSyncTime(syncedAt)} · $source에서 가져옴';

    return Text(
      text,
      style: AppTextStyles.caption.copyWith(color: AppColors.textM),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  final String phase;
  final String phaseContext;
  final int cycleDay;
  final int daysUntilNextPeriod;
  final double progress;
  final Color color;

  const _PhaseCard({
    required this.phase,
    required this.phaseContext,
    required this.cycleDay,
    required this.daysUntilNextPeriod,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '오늘의 주기 단계',
            style: TextStyle(fontSize: 12, color: Color(0xFF9888A0)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  phase,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF201C28),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            phaseContext,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9888A0),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '오늘의 예상 일차',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9888A0)),
                ),
              ),
              Text(
                '$cycleDay일차',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF201C28),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            daysUntilNextPeriod == 0
                ? '다음 생리 예정일이 오늘이에요'
                : '다음 생리 예정일까지 $daysUntilNextPeriod일',
            style: const TextStyle(fontSize: 12, color: Color(0xFF9888A0)),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: color.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

String _relativeSyncTime(DateTime syncedAt) {
  final elapsed = DateTime.now().difference(syncedAt);
  if (elapsed.inMinutes < 1) return '방금 전';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}분 전';
  if (elapsed.inDays < 1) return '${elapsed.inHours}시간 전';
  return koFullDate(syncedAt);
}
