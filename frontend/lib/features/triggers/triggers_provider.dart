import 'package:flutter/material.dart';

import '../../core/errors/api_exception.dart';
import '../../core/utils/korean_ui_text.dart';
import 'data/categories_api.dart';

class StressTrigger {
  final String name;
  final Color color;
  final int eventCount;

  const StressTrigger({
    required this.name,
    required this.color,
    required this.eventCount,
  });

  StressTrigger copyWith({String? name, Color? color, int? eventCount}) {
    return StressTrigger(
      name: name ?? this.name,
      color: color ?? this.color,
      eventCount: eventCount ?? this.eventCount,
    );
  }
}

class TriggersProvider extends ChangeNotifier {
  final CategoriesApi categoriesApi;

  static const List<StressTrigger> defaultTriggers = [
    StressTrigger(name: 'Work', color: Color(0xFFB87888), eventCount: 0),
    StressTrigger(name: 'Social', color: Color(0xFFB7A6D8), eventCount: 0),
    StressTrigger(name: 'Family', color: Color(0xFF94D0BC), eventCount: 0),
    StressTrigger(name: 'School', color: Color(0xFFAED3E8), eventCount: 0),
    StressTrigger(name: 'Health', color: Color(0xFFE7C9A9), eventCount: 0),
  ];

  static const List<String> _defaultTriggerKeys = [
    'work',
    'social',
    'family',
    'school',
    'health',
  ];

  List<StressTrigger> _triggers = [];
  List<String> _categoryIds = [];
  List<String?> _defaultKeys = [];
  final Set<String> _deletedDefaultKeys = {};
  final Map<String, StressTrigger> _editedDefaultTriggers = {};
  String? _errorMessage;

  List<StressTrigger> get triggers => List.unmodifiable(_triggers);
  String? get errorMessage => _errorMessage;

  TriggersProvider({required this.categoriesApi});

  Future<void> load() async {
    _errorMessage = null;

    try {
      final categories = await categoriesApi.listCategories();
      final ids = categories.map((category) => category.id).toList();
      _setMergedTriggers(
        categories.map(_triggerFromCategory).toList(),
        ids,
        sourceDefaultKeys: [
          for (final category in categories)
            _defaultKeyForValue(category.id) ??
                _defaultKeyForValue(category.name),
        ],
      );
    } on ApiException catch (error) {
      _errorMessage = error.message;
      _setMergedTriggers(const [], const []);
    } catch (_) {
      _errorMessage = '스트레스 요인을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
      _setMergedTriggers(const [], const []);
    }
    notifyListeners();
  }

  Future<void> addTrigger({required String name, required Color color}) async {
    if (name.trim().isEmpty) return;
    _ensureDefaultTriggers();
    if (_hasDuplicateName(name)) return;

    final restoredDefaultKey = _defaultKeyForValue(name);
    final shouldRestoreDeletedDefault =
        restoredDefaultKey != null &&
        _deletedDefaultKeys.contains(restoredDefaultKey);
    final newTrigger = StressTrigger(
      name: name.trim(),
      color: color,
      eventCount: 0,
    );
    if (shouldRestoreDeletedDefault) {
      _deletedDefaultKeys.remove(restoredDefaultKey);
      _editedDefaultTriggers[restoredDefaultKey] = newTrigger;
    }

    _triggers = [..._triggers, newTrigger];
    _categoryIds = [..._categoryIds, ''];
    _defaultKeys = [
      ..._defaultKeys,
      shouldRestoreDeletedDefault ? restoredDefaultKey : null,
    ];
    notifyListeners();

    try {
      final created = await categoriesApi.createCategory(
        name: name.trim(),
        color: color,
        sortOrder: _triggers.length - 1,
      );
      final createdIndex = _indexOfTriggerName(created.name);
      if (createdIndex == -1) return;
      _triggers = [
        for (var i = 0; i < _triggers.length; i++)
          if (i == createdIndex)
            _triggerFromCategory(created)
          else
            _triggers[i],
      ];
      _categoryIds = [
        for (var i = 0; i < _categoryIds.length; i++)
          if (i == createdIndex) created.id else _categoryIds[i],
      ];
      _errorMessage = null;
      notifyListeners();
    } on ApiException catch (error) {
      _errorMessage = error.message;
      notifyListeners();
    }
  }

  Future<void> updateTrigger(
    int index, {
    required String name,
    required Color color,
  }) async {
    if (index < 0 || index >= _triggers.length) return;
    if (name.trim().isEmpty) return;

    final defaultKey = _defaultKeyAt(index);
    final updatedTrigger = _triggers[index].copyWith(
      name: name.trim(),
      color: color,
    );
    if (defaultKey != null) {
      _deletedDefaultKeys.remove(defaultKey);
      _editedDefaultTriggers[defaultKey] = updatedTrigger;
    }

    _triggers = [
      for (var i = 0; i < _triggers.length; i++)
        if (i == index) updatedTrigger else _triggers[i],
    ];
    _defaultKeys = [
      for (var i = 0; i < _defaultKeys.length; i++)
        if (i == index) defaultKey else _defaultKeys[i],
    ];
    notifyListeners();

    if (index < _categoryIds.length) {
      final id = _categoryIds[index];
      if (id.isEmpty) return;
      try {
        final updated = await categoriesApi.updateCategory(
          id,
          name: name.trim(),
          color: color,
        );
        final updatedTrigger = _triggerFromCategory(updated);
        _triggers = [
          for (var i = 0; i < _triggers.length; i++)
            if (i == index) updatedTrigger else _triggers[i],
        ];
        if (defaultKey != null) {
          _editedDefaultTriggers[defaultKey] = updatedTrigger;
        }
        _errorMessage = null;
        notifyListeners();
      } on ApiException catch (error) {
        _errorMessage = error.message;
        notifyListeners();
      }
    }
  }

  Future<void> removeTrigger(int index) async {
    if (index < 0 || index >= _triggers.length) return;
    final id = index < _categoryIds.length ? _categoryIds[index] : '';
    final defaultKey = _defaultKeyAt(index);
    if (defaultKey != null) {
      _deletedDefaultKeys.add(defaultKey);
      _editedDefaultTriggers.remove(defaultKey);
    }
    _triggers = [
      for (var i = 0; i < _triggers.length; i++)
        if (i != index) _triggers[i],
    ];
    _categoryIds = [
      for (var i = 0; i < _categoryIds.length; i++)
        if (i != index) _categoryIds[i],
    ];
    _defaultKeys = [
      for (var i = 0; i < _defaultKeys.length; i++)
        if (i != index) _defaultKeys[i],
    ];
    notifyListeners();

    if (id.isNotEmpty) {
      try {
        await categoriesApi.deleteCategory(id);
        _errorMessage = null;
      } on ApiException catch (error) {
        _errorMessage = error.message;
      }
      notifyListeners();
    }
  }

  StressTrigger _triggerFromCategory(TriggerCategoryDto category) {
    return StressTrigger(
      name: category.name,
      color: category.color,
      eventCount: category.eventCount,
    );
  }

  void _ensureDefaultTriggers() {
    _setMergedTriggers(
      _triggers,
      _categoryIds,
      sourceDefaultKeys: _defaultKeys,
    );
  }

  void _setMergedTriggers(
    List<StressTrigger> triggers,
    List<String> ids, {
    List<String?>? sourceDefaultKeys,
  }) {
    final sourceByDefaultKey = <String, _TriggerSource>{};
    final customSources = <_TriggerSource>[];

    for (var i = 0; i < triggers.length; i++) {
      final trigger = triggers[i];
      final id = i < ids.length ? ids[i] : '';
      final defaultKey =
          (sourceDefaultKeys != null && i < sourceDefaultKeys.length
              ? sourceDefaultKeys[i]
              : null) ??
          _defaultKeyForValue(id) ??
          _defaultKeyForValue(trigger.name);
      final source = _TriggerSource(
        trigger: trigger,
        id: id,
        defaultKey: defaultKey,
      );
      if (defaultKey == null) {
        customSources.add(source);
      } else {
        sourceByDefaultKey[defaultKey] = source;
      }
    }

    final merged = <StressTrigger>[];
    final mergedIds = <String>[];
    final mergedDefaultKeys = <String?>[];

    for (var i = 0; i < defaultTriggers.length; i++) {
      final defaultKey = _defaultTriggerKeys[i];
      if (_deletedDefaultKeys.contains(defaultKey)) {
        continue;
      }

      final editedTrigger = _editedDefaultTriggers[defaultKey];
      final source = sourceByDefaultKey[defaultKey];
      if (editedTrigger != null) {
        merged.add(editedTrigger);
        mergedIds.add(source?.id ?? _categoryIdForDefaultKey(defaultKey));
      } else if (source != null) {
        merged.add(source.trigger);
        mergedIds.add(source.id);
      } else {
        final trigger = defaultTriggers[i];
        merged.add(trigger);
        mergedIds.add('');
      }
      mergedDefaultKeys.add(defaultKey);
    }

    for (final source in customSources) {
      merged.add(source.trigger);
      mergedIds.add(source.id);
      mergedDefaultKeys.add(null);
    }

    _triggers = merged;
    _categoryIds = mergedIds;
    _defaultKeys = mergedDefaultKeys;
  }

  int _indexOfTriggerName(String name) {
    return _indexOfTriggerNameIn(_triggers, name);
  }

  int _indexOfTriggerNameIn(List<StressTrigger> triggers, String name) {
    final newNameKeys = _triggerNameKeys(name);
    return triggers.indexWhere((trigger) {
      final existingKeys = _triggerNameKeys(trigger.name);
      return existingKeys.any(newNameKeys.contains);
    });
  }

  bool _hasDuplicateName(String name) {
    final defaultKey = _defaultKeyForValue(name);
    if (defaultKey != null && _defaultKeys.contains(defaultKey)) {
      return true;
    }
    return _indexOfTriggerName(name) != -1;
  }

  Set<String> _triggerNameKeys(String value) {
    return {value.trim().toLowerCase(), koTrigger(value).trim().toLowerCase()};
  }

  String? _defaultKeyAt(int index) {
    if (index < _defaultKeys.length && _defaultKeys[index] != null) {
      return _defaultKeys[index];
    }
    return _defaultKeyForValue(_triggers[index].name);
  }

  String _categoryIdForDefaultKey(String defaultKey) {
    for (var i = 0; i < _defaultKeys.length; i++) {
      if (_defaultKeys[i] == defaultKey && i < _categoryIds.length) {
        return _categoryIds[i];
      }
    }
    return '';
  }

  String? _defaultKeyForValue(String value) {
    final normalized = value.trim().toLowerCase();
    if (_defaultTriggerKeys.contains(normalized)) return normalized;

    final keys = _triggerNameKeys(value);
    for (var i = 0; i < defaultTriggers.length; i++) {
      final trigger = defaultTriggers[i];
      final defaultKeys = _triggerNameKeys(trigger.name);
      if (defaultKeys.any(keys.contains)) {
        return _defaultTriggerKeys[i];
      }
    }
    return null;
  }

  void clearSessionData() {
    _triggers = [];
    _categoryIds = [];
    _defaultKeys = [];
    _deletedDefaultKeys.clear();
    _editedDefaultTriggers.clear();
    _errorMessage = null;
    notifyListeners();
  }
}

class _TriggerSource {
  final StressTrigger trigger;
  final String id;
  final String? defaultKey;

  const _TriggerSource({
    required this.trigger,
    required this.id,
    required this.defaultKey,
  });
}
