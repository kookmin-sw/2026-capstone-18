import 'package:flutter/material.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';

class CategoriesApi {
  final ApiClient _apiClient;

  const CategoriesApi({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<TriggerCategoryDto>> listCategories() async {
    final response = await _apiClient.get('/api/v1/categories');
    final items = response is Map<String, dynamic>
        ? response['items']
        : response;
    if (items is List) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(TriggerCategoryDto.fromJson)
          .toList();
    }
    throw const ApiException(message: '스트레스 요인 응답을 확인하지 못했어요.');
  }

  Future<TriggerCategoryDto> createCategory({
    required String name,
    required Color color,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{'name': name, 'color': _toHex(color)};
    if (sortOrder != null) body['sort_order'] = sortOrder;

    final response = await _apiClient.post('/api/v1/categories', body: body);
    return TriggerCategoryDto.fromJson(_map(response));
  }

  Future<TriggerCategoryDto> updateCategory(
    String id, {
    String? name,
    Color? color,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (color != null) body['color'] = _toHex(color);
    if (sortOrder != null) body['sort_order'] = sortOrder;

    final response = await _apiClient.patch(
      '/api/v1/categories/$id',
      body: body,
    );
    return TriggerCategoryDto.fromJson(_map(response));
  }

  Future<void> deleteCategory(String id) async {
    await _apiClient.delete('/api/v1/categories/$id');
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiException(message: '스트레스 요인 응답을 확인하지 못했어요.');
  }

  static String _toHex(Color color) {
    final argb = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${argb.substring(2).toUpperCase()}';
  }
}

class TriggerCategoryDto {
  final String id;
  final String name;
  final Color color;
  final int eventCount;

  const TriggerCategoryDto({
    required this.id,
    required this.name,
    required this.color,
    required this.eventCount,
  });

  factory TriggerCategoryDto.fromJson(Map<String, dynamic> json) {
    final name = '${json['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      throw const ApiException(message: '스트레스 요인 응답을 확인하지 못했어요.');
    }

    return TriggerCategoryDto(
      id: '${json['id'] ?? ''}',
      name: name,
      color: _parseColor('${json['color'] ?? ''}'),
      eventCount: (json['event_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Color _parseColor(String value) {
    final normalized = value
        .trim()
        .replaceFirst('#', '')
        .replaceFirst('0x', '')
        .replaceFirst('0X', '');
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return const Color(0xFFB87888);
    return Color(parsed);
  }
}
