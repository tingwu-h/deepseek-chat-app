import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/utils/app_info.dart';

/// 设置页：API Key（用户自己填，绝不硬编码）、模型、主题、系统提示词。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _promptController;
  late final TextEditingController _customController;

  late String _model;
  late String _themeMode;
  late double _temperature;

  /// 下拉框里「自定义…」那一项的占位值（不是真实模型名）
  static const String _customModelSentinel = '__custom__';

  /// 当前模型是否不在预置列表里
  bool _isCustomModel = false;

  bool _obscureKey = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final AppSettings s = context.read<AppSettingsProvider>().settings;
    _keyController = TextEditingController(text: s.apiKey);
    _baseUrlController = TextEditingController(text: s.baseUrl);
    _promptController = TextEditingController(text: s.systemPrompt);
    _model = s.model;
    _isCustomModel = !AppSettings.availableModels.contains(_model);
    _customController = TextEditingController(
      text: _isCustomModel ? _model : '',
    );
    _themeMode = s.themeMode;
    _temperature = s.temperature;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _promptController.dispose();
    _customController.dispose();
    super.dispose();
  }

  AppSettings _collect() {
    final AppSettingsProvider provider =
        context.read<AppSettingsProvider>();
    // 自定义模型名优先：用户既然填了，就用他填的
    final String custom = _customController.text.trim();
    final String model =
        custom.isNotEmpty && _isCustomModel ? custom : _model;
    return provider.settings.copyWith(
      apiKey: _keyController.text.trim(),
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? AppSettings.defaultBaseUrl
          : _baseUrlController.text.trim(),
      model: model,
      systemPrompt: _promptController.text.trim(),
      temperature: _temperature,
      themeMode: _themeMode,
    );
  }

  Future<void> _save({bool pop = true}) async {
    final AppSettingsProvider provider =
        context.read<AppSettingsProvider>();
    final AppSettings next = _collect();
    await provider.update(
      apiKey: next.apiKey,
      baseUrl: next.baseUrl,
      model: next.model,
      systemPrompt: next.systemPrompt,
      temperature: next.temperature,
      themeMode: next.themeMode,
    );
    if (!mounted) return;
    _toast('设置已保存');
    if (pop) Navigator.of(context).pop();
  }

  Future<void> _testConnection() async {
    final AppSettings candidate = _collect();
    if (!candidate.hasApiKey) {
      _toast('请先填写 API Key');
      return;
    }

    setState(() => _testing = true);
    FocusScope.of(context).unfocus();

    final DeepSeekService service = DeepSeekService();
    try {
      // 先保存，这样测试用的就是当前填写的配置
      await context.read<AppSettingsProvider>().update(
            apiKey: candidate.apiKey,
            baseUrl: candidate.baseUrl,
            model: candidate.model,
            temperature: candidate.temperature,
          );
      final String reply = await service.testConnection(candidate);
      if (!mounted) return;
      _toast('连接成功：${_short(reply)}');
    } on DeepSeekException catch (e) {
      if (!mounted) return;
      _toast(e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      _toast('连接失败：$e', isError: true);
    } finally {
      service.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  String _short(String text) {
    final String oneLine = text.replaceAll('\n', ' ').trim();
    if (oneLine.isEmpty) return '（空回复）';
    return oneLine.length <= 30 ? oneLine : '${oneLine.substring(0, 30)}…';
  }

  void _toast(String message, {bool isError = false}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? scheme.errorContainer : null,
          showCloseIcon: isError,
        ),
      );
  }

  Future<void> _confirmReset() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('恢复默认设置？'),
        content: const Text('将清空已保存的 API Key、系统提示词等全部配置。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 对话框是异步的，这里必须守卫；analyzer 的 use_build_context_synchronously
    // 对这个写法会误报（它先要求 context.mounted，加上后又说“不算数”），故定点忽略。
    if (!context.mounted) return;
    // ignore: use_build_context_synchronously
    final AppSettingsProvider provider = context.read<AppSettingsProvider>();
    await provider.resetToDefaults();
    if (!mounted) return;
    setState(() {
      _keyController.clear();
      _baseUrlController.text = AppSettings.defaultBaseUrl;
      _promptController.clear();
      _model = AppSettings.defaultModel;
      _themeMode = 'system';
      _temperature = 1.0;
    });
    _toast('已恢复默认设置');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ChatProvider chat = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: <Widget>[
          IconButton(
            tooltip: '恢复默认',
            onPressed: _confirmReset,
            icon: const Icon(Icons.restart_alt),
          ),
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          _sectionTitle('API 配置'),
          _card(
            children: <Widget>[
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: 'DeepSeek API Key',
                  hintText: 'sk-xxxxxxxxxxxxxxxx',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: _obscureKey ? '显示' : '隐藏',
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      IconButton(
                        tooltip: '粘贴',
                        onPressed: () async {
                          final ClipboardData? data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          final String? text = data?.text;
                          if (text == null || text.isEmpty) return;
                          _keyController.text = text.trim();
                          _keyController.selection =
                              TextSelection.collapsed(
                            offset: _keyController.text.length,
                          );
                        },
                        icon: const Icon(Icons.content_paste),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Key 申请地址：platform.deepseek.com → API Keys。'
                '它只保存在这台手机的本地存储里，不会上传到任何第三方服务器。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _sectionTitle('模型与接口'),
          _card(
            children: <Widget>[
              DropdownButtonFormField<String>(
                // Flutter 3.32+ 推荐用 initialValue，旧版本仍是 value；
                // 这里用 value 以同时兼容 3.22 ~ 3.35。
                // ignore: deprecated_member_use
                value: _model,
                decoration: const InputDecoration(
                  labelText: '模型',
                  prefixIcon: Icon(Icons.memory_outlined),
                ),
                // 如果当前模型是自定义的（不在预置列表里），临时补一项进去，
                // 否则 DropdownButtonFormField 会因为 value 不在 items 里而断言失败
                items: <DropdownMenuItem<String>>[
                  for (final String m in AppSettings.availableModels)
                    DropdownMenuItem<String>(
                      value: m,
                      child: Text(AppSettings.modelLabel(m)),
                    ),
                  const DropdownMenuItem<String>(
                    value: _customModelSentinel,
                    child: Text('自定义…'),
                  ),
                  if (!AppSettings.availableModels.contains(_model) &&
                      _model != _customModelSentinel)
                    DropdownMenuItem<String>(
                      value: _model,
                      child: Text('自定义：$_model'),
                    ),
                ],
                onChanged: (String? value) {
                  if (value == null) return;
                  setState(() {
                    if (value == _customModelSentinel) {
                      _model = _customController.text.trim().isEmpty
                          ? AppSettings.defaultModel
                          : _customController.text.trim();
                    } else {
                      _model = value;
                    }
                    _isCustomModel =
                        !AppSettings.availableModels.contains(_model);
                    if (_isCustomModel) _customController.text = _model;
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '自定义模型名（可选）',
                  hintText: '例如 deepseek-flash',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                onChanged: (String v) {
                  // 用户在这里输入时，模型名立即跟随（不用再去上面选一次）
                  final String t = v.trim();
                  setState(() {
                    if (t.isNotEmpty) {
                      _model = t;
                      _isCustomModel =
                          !AppSettings.availableModels.contains(t);
                    } else {
                      _isCustomModel = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 4),
              Text(
                '当前使用：$_model'
                '${_isCustomModel ? '（自定义）' : ''}\n'
                '模型名以官方文档为准：api-docs.deepseek.com → 模型 & 价格。'
                '官方若改版，直接在上面的输入框填写新的模型名即可。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API Base URL',
                  hintText: AppSettings.defaultBaseUrl,
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '最终请求地址：${_baseUrlController.text.trim().isEmpty ? AppSettings.defaultBaseUrl : _baseUrlController.text.trim()}/chat/completions',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Icon(Icons.thermostat_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '随机性 temperature：${_temperature.toStringAsFixed(1)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _temperature,
                min: 0,
                max: 2,
                divisions: 20,
                label: _temperature.toStringAsFixed(1),
                onChanged: (double v) => setState(() => _temperature = v),
              ),
              Text(
                '0 最稳定、2 最发散；对话场景一般 0.7 ~ 1.3。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _sectionTitle('外观'),
          _card(
            children: <Widget>[
              for (final String mode in AppSettings.availableThemeModes)
                RadioListTile<String>(
                  value: mode,
                  // ignore: deprecated_member_use
                  groupValue: _themeMode,
                  // ignore: deprecated_member_use
                  onChanged: (String? value) async {
                    if (value == null) return;
                    // 主题属于「选完就想看到效果」的偏好，立即生效并落盘，
                    // 不需要用户再点一次「保存」——之前必须保存才生效，
                    // 选完直接返回就白选了。
                    setState(() => _themeMode = value);
                    await context
                        .read<AppSettingsProvider>()
                        .update(themeMode: value);
                  },
                  contentPadding: EdgeInsets.zero,
                  title: Text(switch (mode) {
                    'light' => '浅色',
                    'dark' => '深色',
                    _ => '跟随系统',
                  }),
                  subtitle: switch (mode) {
                    'light' => const Text('始终使用浅色主题'),
                    'dark' => const Text('始终使用深色主题'),
                    _ => const Text('系统切换深色时自动跟随'),
                  },
                ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '选完立即生效，无需再点保存。',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _sectionTitle('系统提示词（可选）'),
          _card(
            children: <Widget>[
              TextField(
                controller: _promptController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: '例如：你是一位资深 Flutter 工程师，回答尽量给出可运行的代码。',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _sectionTitle('操作'),
          _card(
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_testing ? '正在测试…' : '测试连接'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await chat.clearAllConversations();
                  if (!mounted) return;
                  _toast('已清空全部对话记录');
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('清空全部对话记录'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _save(),
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存设置'),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Center(
            child: Text(
              'DeepSeek 助手 v$kAppVersion',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}
