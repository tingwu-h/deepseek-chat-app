import 'package:flutter/foundation.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/services/storage_service.dart';

/// 应用根状态：设置 + 主题模式 + 初始化状态。
///
/// API Key 只保存在这里（以及 shared_preferences），任何时候都不写死在代码里。
class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider({required StorageService storage}) : _storage = storage;

  final StorageService _storage;

  AppSettings _settings = AppSettings();
  bool _initialized = false;

  AppSettings get settings => _settings;

  /// 是否已经把本地数据读进内存（main() 里会先 await init()）
  bool get initialized => _initialized;

  String get apiKey => _settings.apiKey;
  String get baseUrl => _settings.baseUrl;
  String get model => _settings.model;
  String get systemPrompt => _settings.systemPrompt;
  double get temperature => _settings.temperature;
  bool get hasApiKey => _settings.hasApiKey;

  /// 'system' | 'light' | 'dark'
  String get themeModeName => _settings.themeMode;

  Future<void> init() async {
    _settings = await _storage.loadSettings();
    _initialized = true;
    notifyListeners();
  }

  Future<void> update({
    String? apiKey,
    String? baseUrl,
    String? model,
    String? systemPrompt,
    double? temperature,
    String? themeMode,
  }) async {
    _settings = _settings.copyWith(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      systemPrompt: systemPrompt,
      temperature: temperature,
      themeMode: themeMode,
    );
    notifyListeners();
    await _storage.saveSettings(_settings);
  }

  /// 一键恢复默认（会同时清空 API Key）
  Future<void> resetToDefaults() => update(
        apiKey: '',
        baseUrl: AppSettings.defaultBaseUrl,
        model: AppSettings.defaultModel,
        systemPrompt: '',
        temperature: 1.0,
        themeMode: 'system',
      );
}
