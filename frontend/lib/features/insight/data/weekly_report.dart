class WeeklyTakeaway {
  final String title;
  final String body;
  const WeeklyTakeaway({required this.title, required this.body});

  factory WeeklyTakeaway.fromJson(Map<String, dynamic> json) =>
      WeeklyTakeaway(title: json['title'] as String, body: json['body'] as String);
}

class WeeklyReport {
  final DateTime weekStart;
  final String headline;
  final String bodyMd;
  final List<WeeklyTakeaway> takeaways;
  final DateTime generatedAt;

  const WeeklyReport({
    required this.weekStart,
    required this.headline,
    required this.bodyMd,
    required this.takeaways,
    required this.generatedAt,
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> json) => WeeklyReport(
        weekStart: DateTime.parse(json['week_start'] as String),
        headline: json['headline'] as String,
        bodyMd: json['body_md'] as String,
        takeaways: (json['takeaways'] as List<dynamic>? ?? const [])
            .map((e) => WeeklyTakeaway.fromJson(e as Map<String, dynamic>))
            .toList(),
        generatedAt: DateTime.parse(json['generated_at'] as String),
      );
}
