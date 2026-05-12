class RangeTakeaway {
  final String title;
  final String body;
  const RangeTakeaway({required this.title, required this.body});

  factory RangeTakeaway.fromJson(Map<String, dynamic> json) =>
      RangeTakeaway(title: json['title'] as String, body: json['body'] as String);
}

class RangeReport {
  final DateTime periodStart;
  final DateTime periodEnd;
  final String headline;
  final String bodyMd;
  final List<RangeTakeaway> takeaways;
  final DateTime generatedAt;

  const RangeReport({
    required this.periodStart,
    required this.periodEnd,
    required this.headline,
    required this.bodyMd,
    required this.takeaways,
    required this.generatedAt,
  });

  factory RangeReport.fromJson(Map<String, dynamic> json) => RangeReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        headline: json['headline'] as String,
        bodyMd: json['body_md'] as String,
        takeaways: (json['takeaways'] as List<dynamic>? ?? const [])
            .map((e) => RangeTakeaway.fromJson(e as Map<String, dynamic>))
            .toList(),
        generatedAt: DateTime.parse(json['generated_at'] as String),
      );
}
