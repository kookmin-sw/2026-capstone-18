class PatternTip {
  final String patternKey;
  final String tipText;
  final DateTime generatedAt;

  const PatternTip({
    required this.patternKey,
    required this.tipText,
    required this.generatedAt,
  });

  factory PatternTip.fromJson(Map<String, dynamic> json) => PatternTip(
        patternKey: json['pattern_key'] as String,
        tipText: json['tip_text'] as String,
        generatedAt: DateTime.parse(json['generated_at'] as String),
      );
}
