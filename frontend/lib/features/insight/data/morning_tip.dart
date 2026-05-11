class MorningTip {
  final String headline;
  final String body;
  final String? contextLine;
  final String? patternKey;
  final DateTime generatedAt;

  const MorningTip({
    required this.headline,
    required this.body,
    required this.generatedAt,
    this.contextLine,
    this.patternKey,
  });

  factory MorningTip.fromJson(Map<String, dynamic> json) => MorningTip(
        headline: json['headline'] as String,
        body: json['body'] as String,
        contextLine: json['context_line'] as String?,
        patternKey: json['pattern_key'] as String?,
        generatedAt: DateTime.parse(json['generated_at'] as String),
      );
}
