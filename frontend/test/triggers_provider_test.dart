import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_signals/core/network/api_client.dart';
import 'package:little_signals/core/storage/secure_token_storage.dart';
import 'package:little_signals/core/utils/korean_ui_text.dart';
import 'package:little_signals/features/triggers/data/categories_api.dart';
import 'package:little_signals/features/triggers/triggers_provider.dart';

void main() {
  test('merges default triggers with partial backend categories', () async {
    final provider = TriggersProvider(
      categoriesApi: _MemoryCategoriesApi([
        const TriggerCategoryDto(
          id: 'work',
          name: 'Work',
          color: Color(0xFFB87888),
          eventCount: 2,
        ),
        const TriggerCategoryDto(
          id: 'custom-exercise',
          name: '운동',
          color: Color(0xFF94D0BC),
          eventCount: 0,
        ),
      ]),
    );

    await provider.load();

    expect(_labels(provider), ['업무', '대인관계', '가족', '학업', '건강', '운동']);
  });

  test('keeps default triggers after adding a custom trigger', () async {
    final provider = TriggersProvider(
      categoriesApi: _MemoryCategoriesApi(const []),
    );

    await provider.load();
    await provider.addTrigger(name: '운동', color: const Color(0xFF94D0BC));

    expect(_labels(provider), ['업무', '대인관계', '가족', '학업', '건강', '운동']);
  });

  test('treats raw and Korean default labels as duplicates', () async {
    final provider = TriggersProvider(
      categoriesApi: _MemoryCategoriesApi(const []),
    );

    await provider.load();
    await provider.addTrigger(name: ' 업무 ', color: const Color(0xFF94D0BC));

    expect(_labels(provider).where((label) => label == '업무'), hasLength(1));
  });

  test('does not restore an explicitly deleted default trigger', () async {
    final provider = TriggersProvider(
      categoriesApi: _MemoryCategoriesApi(const []),
    );

    await provider.load();
    await provider.removeTrigger(0);
    await provider.load();
    await provider.addTrigger(name: '운동', color: const Color(0xFF94D0BC));

    expect(_labels(provider), ['대인관계', '가족', '학업', '건강', '운동']);
  });

  test('keeps an explicitly edited default trigger override', () async {
    final provider = TriggersProvider(
      categoriesApi: _MemoryCategoriesApi(const []),
    );

    await provider.load();
    await provider.updateTrigger(0, name: '회사', color: const Color(0xFFB87888));
    await provider.load();
    await provider.addTrigger(name: '운동', color: const Color(0xFF94D0BC));
    await provider.addTrigger(name: '업무', color: const Color(0xFF94D0BC));

    expect(_labels(provider), ['회사', '대인관계', '가족', '학업', '건강', '운동']);
    expect(_labels(provider).where((label) => label == '업무'), isEmpty);
  });

  test('resolves backend category id for selected trigger label', () async {
    final provider = TriggersProvider(
      categoriesApi: _MemoryCategoriesApi([
        const TriggerCategoryDto(
          id: 'category-family',
          name: 'Family',
          color: Color(0xFF94D0BC),
          eventCount: 0,
        ),
      ]),
    );

    await provider.load();

    expect(provider.categoryIdForTrigger('Family'), 'category-family');
    expect(provider.categoryIdForTrigger('가족'), 'category-family');
  });

  test('creates a backend category id for fallback default trigger', () async {
    final provider = TriggersProvider(
      categoriesApi: _MemoryCategoriesApi(const []),
    );

    await provider.load();
    final categoryId = await provider.ensureCategoryIdForTrigger('업무');

    expect(categoryId, 'category-1');
    expect(provider.categoryIdForTrigger('Work'), 'category-1');
  });
}

List<String> _labels(TriggersProvider provider) {
  return provider.triggers.map((trigger) => koTrigger(trigger.name)).toList();
}

class _MemoryCategoriesApi extends CategoriesApi {
  final List<TriggerCategoryDto> categories;

  _MemoryCategoriesApi(List<TriggerCategoryDto> categories)
    : categories = [...categories],
      super(apiClient: ApiClient(tokenStorage: SecureTokenStorage()));

  @override
  Future<List<TriggerCategoryDto>> listCategories() async => categories;

  @override
  Future<TriggerCategoryDto> createCategory({
    required String name,
    required Color color,
    int? sortOrder,
  }) async {
    final category = TriggerCategoryDto(
      id: 'category-${categories.length + 1}',
      name: name.trim(),
      color: color,
      eventCount: 0,
    );
    categories.add(category);
    return category;
  }
}
