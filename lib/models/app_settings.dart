/// 应用设置（保存在 shared_preferences 里，API Key 绝不硬编码）。
class AppSettings {
  AppSettings({
    this.apiKey = '',
    this.baseUrl = defaultBaseUrl,
    this.model = defaultModel,
    this.systemPrompt = '',
    this.temperature = 1.0,
    this.themeMode = 'system',
  });

  /// DeepSeek 官方 API 基地址
  static const String defaultBaseUrl = 'https://api.deepseek.com';

  /// 默认模型。
  ///
  /// 取值依据官方文档 https://api-docs.deepseek.com/zh-cn/quick_start/pricing
  /// （2026 年当前页面只列 deepseek-flash 与 deepseek-v4-pro，
  ///   旧写法 deepseek-chat / deepseek-reasoner 已不在文档中）。
  /// 注意：这是文档值，本机没有有效 API Key，**未做真实调用验证**；
  /// 如果调用报「模型不存在」，用设置页的「自定义模型名」填上你账号可用的模型即可。
  static const String defaultModel = 'deepseek-flash';

  /// 预置模型（列表里可选的）
  static const List<String> availableModels = <String>[
    'deepseek-flash', // DeepSeek-V4.1-Flash，官方文档推荐名
    'deepseek-v4-pro', // DeepSeek-V4-Pro-0813，推理更强
    'deepseek-chat', // 上一代写法，仍被 API 接受（文档未列）
    'deepseek-reasoner', // 上一代推理模型写法
  ];

  /// 每个模型在界面上的显示名
  static String modelLabel(String model) => switch (model) {
        'deepseek-flash' => 'deepseek-flash（快，日常对话）',
        'deepseek-v4-pro' => 'deepseek-v4-pro（强，复杂推理）',
        'deepseek-chat' => 'deepseek-chat（上一代·通用）',
        'deepseek-reasoner' => 'deepseek-reasoner（上一代·推理）',
        _ => model,
      };

  /// 顶栏胶囊里的短名
  static String modelShortName(String model) {
    if (model.startsWith('deepseek-')) {
      final String rest = model.substring('deepseek-'.length);
      return rest.length <= 10 ? rest : '${rest.substring(0, 10)}…';
    }
    return model.length <= 10 ? model : '${model.substring(0, 10)}…';
  }

  /// 主题模式：system / light / dark
  static const List<String> availableThemeModes = <String>[
    'system',
    'light',
    'dark',
  ];

  final String apiKey;
  final String baseUrl;
  final String model;
  final String systemPrompt;
  final double temperature;
  final String themeMode;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// 只用于界面展示，避免完整 Key 出现在截图里
  String get maskedApiKey {
    final String k = apiKey.trim();
    if (k.isEmpty) return '未设置';
    if (k.length <= 10) return '${k.substring(0, 2)}****';
    return '${k.substring(0, 6)}****${k.substring(k.length - 4)}';
  }

  AppSettings copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
    String? systemPrompt,
    double? temperature,
    String? themeMode,
  }) {
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'systemPrompt': systemPrompt,
        'temperature': temperature,
        'themeMode': themeMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      apiKey: (json['apiKey'] as String?) ?? '',
      baseUrl: (json['baseUrl'] as String?) ?? defaultBaseUrl,
      model: (json['model'] as String?) ?? defaultModel,
      systemPrompt: (json['systemPrompt'] as String?) ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 1.0,
      themeMode: (json['themeMode'] as String?) ?? 'system',
    );
  }
}
