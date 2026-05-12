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
import 'watch_connect_screen.dart';

class SleepDataScreen extends StatefulWidget {
  const SleepDataScreen({super.key});

  @override
  State<SleepDataScreen> createState() => _SleepDataScreenState();
}

class _SleepDataScreenState extends State<SleepDataScreen> {
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

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

  Future<void> _openWatchConnect() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const WatchConnectScreen()),
    );

    if (!mounted) return;
    await _loadSelectedRange();
  }

  Future<void> _selectRangeDate({required bool isStart}) async {
    final current = isStart ? _rangeStart : _rangeEnd;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 365)),
      ),
      helpText: isStart ? '시작 날짜 선택' : '종료 날짜 선택',
      cancelText: '취소',
      confirmText: '선택',
    );

    if (selected == null || !mounted) return;

    setState(() {
      final date = DateUtils.dateOnly(selected);
      if (isStart) {
        _rangeStart = date;
        if (_rangeStart.isAfter(_rangeEnd)) _rangeEnd = _rangeStart;
      } else {
        _rangeEnd = date;
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
                                _selectRangeDate(isStart: true),
                            onSelectEnd: () => _selectRangeDate(isStart: false),
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
                                onConnect: _openWatchConnect,
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
  final Future<void> Function() onConnect;

  const _LatestSleepEmptyCard({required this.onConnect});

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
            text: 'Galaxy Watch 연결하기',
            onTap: onConnect,
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
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_rangeTitle(start, end), style: AppTextStyles.cardTitle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RangeDateButton(
                  label: '시작',
                  date: start,
                  onTap: onSelectStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RangeDateButton(
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

class _RangeDateButton extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _RangeDateButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F0F4),
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
                        color: Color(0xFFC0B0C0),
                      ),
                    ),
                    Text(
                      koYearMonthDay(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF201C28),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: Color(0xFFB87888),
              ),
            ],
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
