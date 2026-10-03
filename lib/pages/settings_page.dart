import 'package:deepseek_chat/models/model_info.dart';
import 'package:deepseek_chat/models/provider_catalog.dart';
import 'package:deepseek_chat/services/api_protocol.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/pages/about_page.dart';
import 'package:deepseek_chat/utils/app_info.dart';
import 'package:deepseek_chat/widgets/model_tags.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/platform_service.dart';
import 'package:deepseek_chat/utils/link_actions.dart';

/// 分组设置；编辑草稿在折叠和切换分类时保留，保存后才落盘。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.serviceFactory});

  final DeepSeekService Function()? serviceFactory;

  static const String routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _promptController;
  late final TextEditingController _customController;

  late AppSettings _draft;
  late String _model;
  bool? _imageSupport;
  late String _themeMode;
  late double _temperature;

  /// 下拉框里「自定义…」那一项的占位值（不是真实模型名）
  static const String _customModelSentinel = '__custom__';

  /// 当前模型是否不在预置列表里
  bool _isCustomModel = false;

  bool _obscureKey = true;
  bool _testing = false;
  bool _exporting = false;
  bool _saving = false;
  bool _resetting = false;
  bool _clearing = false;
  bool _themeSaving = false;
  bool _dirty = false;
  bool _loading = false;
  bool _allowPop = false;
  bool _leaving = false;
  String? _modelError;
  String? _keyError;
  String? _urlError;
  String? _connectionStatus;
  final Set<String> _expanded = {};
  bool get _busy =>
      _saving || _testing || _resetting || _clearing || _themeSaving;

  void _changed() {
    if (_loading || !mounted) return;
    setState(() {
      _dirty = true;
      _connectionStatus = null;
      _modelError = null;
      _keyError = null;
      _urlError = null;
    });
  }

  bool _validate({bool requireKey = false}) {
    final next = _collect();
    String? urlError;
    try {
      ApiProtocol.endpoint(next);
    } catch (_) {
      urlError = '请填写有效的接口地址';
    }
    setState(() {
      _modelError = next.model.isEmpty ? '请选择或填写模型' : null;
      _keyError = requireKey && !next.hasApiKey ? '请先填写 API Key' : null;
      _urlError = urlError;
      if (_modelError != null || _keyError != null || _urlError != null) {
        _expanded.add('model');
        if (_urlError != null) _expanded.add('advanced');
      }
    });
    if (_modelError != null || _keyError != null || _urlError != null) {
      _toast('请检查「模型与服务」中的提示', isError: true);
      return false;
    }
    return true;
  }

  Future<void> _leave() async {
    if (_busy || _leaving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    _leaving = true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存修改？'),
        content: const Text('还有未保存的设置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存并返回'),
          ),
        ],
      ),
    );
    _leaving = false;
    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'save' && !await _save()) return;
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<bool> _confirmDestination(AppSettings next) async {
    Uri destination;
    try {
      destination = ApiProtocol.endpoint(next);
    } on DeepSeekException catch (e) {
      _toast(e.message, isError: true);
      return false;
    } catch (_) {
      _toast('接口地址格式不正确，请检查后再试。', isError: true);
      return false;
    }
    final previous = context.read<AppSettingsProvider>().settings;
    Uri? old;
    try {
      old = ApiProtocol.endpoint(previous);
    } catch (_) {}
    if (destination.origin != old?.origin && next.hasApiKey) {
      return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('确认接口接收方'),
              content: Text(
                '密钥和聊天内容将发送到 ${destination.origin}。\n\n如果这是其他服务商，请确认填写的是该服务商的密钥。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('返回检查'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确认使用'),
                ),
              ],
            ),
          ) ??
          false;
    }
    return true;
  }

  Future<void> _exportHistory() async {
    setState(() => _exporting = true);
    try {
      final json = await context.read<ChatProvider>().exportHistory();
      final saved = await PlatformService.exportHistory(json);
      if (mounted) _toast(saved ? '聊天文字已导出，图片文件不包含在内。' : '已取消导出');
    } catch (_) {
      if (mounted) _toast('导出失败，请重新选择保存位置。', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final AppSettings s = context.read<AppSettingsProvider>().settings;
    _draft = s;
    _imageSupport = s.imageSupport;
    _keyController = TextEditingController(text: s.apiKey);
    _baseUrlController = TextEditingController(text: s.baseUrl);
    _promptController = TextEditingController(text: s.systemPrompt);
    _model = s.model;
    _isCustomModel = !_draft.preset.models.contains(_model);
    _customController = TextEditingController(
      text: _isCustomModel ? _model : '',
    );
    _themeMode = s.themeMode;
    _temperature = s.temperature;
    for (final c in [
      _keyController,
      _baseUrlController,
      _promptController,
      _customController,
    ]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _promptController.dispose();
    _customController.dispose();
    super.dispose();
  }

  void _switchProvider(String id) {
    final next = _collect().forProvider(id);
    _loading = true;
    setState(() {
      _draft = next;
      _imageSupport = next.imageSupport;
      _keyController.text = next.apiKey;
      _baseUrlController.text = next.baseUrl;
      _model = next.model;
      _temperature = next.temperature;
      _isCustomModel = !next.preset.models.contains(_model);
      _customController.text = _isCustomModel ? _model : '';
      _obscureKey = true;
    });
    _loading = false;
    _changed();
  }

  AppSettings _collect() {
    // 自定义模型名优先：用户既然填了，就用他填的
    final String custom = _customController.text.trim();
    final String model = _isCustomModel ? custom : _model;
    return _draft.copyWith(
      imageSupport: _imageSupport,
      apiKey: _keyController.text.trim(),
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? _draft.preset.url
          : _baseUrlController.text.trim(),
      model: model,
      systemPrompt: _promptController.text.trim(),
      temperature: _temperature,
      themeMode: _themeMode,
    );
  }

  Future<bool> _save() async {
    if (_busy || !_validate()) return false;
    setState(() => _saving = true);
    try {
      final next = _collect();
      if (!await _confirmDestination(next) || !mounted) return false;
      await context.read<AppSettingsProvider>().replace(next);
      if (!mounted) return false;
      setState(() {
        _draft = next;
        _dirty = false;
      });
      _toast('设置已保存');
      return true;
    } catch (_) {
      if (mounted) _toast('保存失败，请重试', isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_busy || !_validate(requireKey: true)) return;
    final candidate = _collect();
    setState(() {
      _testing = true;
      _connectionStatus = '正在测试…';
    });
    final service = widget.serviceFactory?.call() ?? DeepSeekService();
    try {
      if (!await _confirmDestination(candidate) || !mounted) {
        if (mounted) setState(() => _connectionStatus = null);
        return;
      }
      FocusScope.of(context).unfocus();
      final reply = await service.testConnection(candidate);
      if (mounted) setState(() => _connectionStatus = '连接成功：${_short(reply)}');
    } on DeepSeekException catch (e) {
      if (mounted) setState(() => _connectionStatus = e.message);
    } catch (_) {
      if (mounted) setState(() => _connectionStatus = '连接失败，请检查网络和配置');
    } finally {
      service.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _setTheme(String value) async {
    if (_busy) return;
    setState(() => _themeSaving = true);
    try {
      await context.read<AppSettingsProvider>().update(themeMode: value);
      if (mounted) setState(() => _themeMode = value);
    } catch (_) {
      if (mounted) _toast('主题未能保存，请重试', isError: true);
    } finally {
      if (mounted) setState(() => _themeSaving = false);
    }
  }

  String _short(String text) {
    final String oneLine = text.replaceAll('\n', ' ').trim();
    if (oneLine.isEmpty) return '（空回复）';
    return oneLine.length <= 30 ? oneLine : '${oneLine.substring(0, 30)}…';
  }

  /// 打开 DeepSeek 开放平台（申请 API Key）——逻辑统一在 link_actions.dart
  Future<void> _openPlatform() async {
    if (_draft.preset.platform.isNotEmpty) {
      await openExternalUrl(context, _draft.preset.platform);
    }
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
    if (!mounted || _busy) return;
    setState(() => _resetting = true);
    try {
      final provider = context.read<AppSettingsProvider>();
      await provider.resetToDefaults();
      if (!mounted) return;
      _loading = true;
      setState(() {
        _draft = provider.settings;
        _imageSupport = null;
        _customController.clear();
        _isCustomModel = false;
        _keyController.clear();
        _baseUrlController.text = AppSettings.defaultBaseUrl;
        _promptController.clear();
        _model = AppSettings.defaultModel;
        _themeMode = 'system';
        _temperature = 1.0;
        _dirty = false;
        _modelError = _urlError = _keyError = _connectionStatus = null;
      });
      _toast('已恢复默认设置');
    } catch (_) {
      if (mounted) _toast('恢复失败，请重试', isError: true);
    } finally {
      _loading = false;
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部对话？'),
        content: const Text('聊天记录和不再使用的图片将被删除，无法撤销。建议先导出重要内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await context.read<ChatProvider>().clearAllConversations();
      if (mounted) _toast('已清空全部对话');
    } catch (_) {
      if (mounted) _toast('清理失败，请重试', isError: true);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final currentModel = _collect().model;
    return PopScope(
      canPop: _allowPop || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          leading: BackButton(onPressed: _busy ? null : _leave),
          actions: [
            IconButton(
              tooltip: '设置帮助',
              onPressed: () => _help(
                '设置帮助',
                '展开分类进行修改，完成后点击保存。主题选择后立即生效。测试连接会产生真实 API 用量，但不会自动保存配置。',
              ),
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _saving
                        ? '正在保存…'
                        : _dirty
                        ? '有未保存的修改'
                        : '设置已保存',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 48),
                  ),
                  onPressed: _busy || !_dirty ? null : () => _save(),
                  icon: const Icon(Icons.check),
                  label: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (settings.initializationWarning case final String warning)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(warning),
                ),
              _group(
                'model',
                Icons.hub_outlined,
                '模型与服务',
                '${_draft.preset.name} · ${_keyController.text.trim().isEmpty ? '待配置' : '已填写密钥'}',
                [
                  DropdownButtonFormField<String>(
                    key: ValueKey('provider-${_draft.providerId}'),
                    initialValue: _draft.providerId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '服务商'),
                    items: [
                      for (final p in providerCatalog)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (id) {
                      if (id != null) _switchProvider(id);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _chooseFreeModel,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('选择免费模型'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscureKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: '${_draft.preset.name} API Key',
                      errorText: _keyError,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (!mounted || _busy) return;
                              if (data?.text case final String value) {
                                _keyController.text = value.trim();
                              }
                            },
                            icon: const Icon(Icons.content_paste),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_draft.preset.platform.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _openPlatform,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('获取 API Key'),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _help(
                        '如何获取 API Key',
                        _draft.preset.platform.isEmpty
                            ? '向你的接口服务商申请密钥，复制后回到这里粘贴。'
                            : '1. 点击「获取 API Key」，前往官方平台。\n2. 注册或登录，在 API Key 页面创建密钥。\n3. 复制密钥，返回万象粘贴并保存。\n\nChatGPT 等聊天会员不等于 API 额度。请在官方平台确认可用模型和费用。',
                      ),
                      child: const Text('申请步骤'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'model-${_draft.providerId}-$_model-$_isCustomModel',
                    ),
                    initialValue: _isCustomModel
                        ? _customModelSentinel
                        : _model,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '模型'),
                    selectedItemBuilder: (context) => [
                      for (final m in _draft.modelChoices)
                        Text(m, overflow: TextOverflow.ellipsis),
                      const Text('自定义模型'),
                    ],
                    items: [
                      for (final m in _draft.modelChoices)
                        DropdownMenuItem(
                          value: m,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m, overflow: TextOverflow.ellipsis),
                              Text(
                                modelTagSummary(_draft.providerId, m),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      const DropdownMenuItem(
                        value: _customModelSentinel,
                        child: Text('自定义模型'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _isCustomModel = value == _customModelSentinel;
                        _model = _isCustomModel
                            ? _customController.text.trim()
                            : value;
                        _imageSupport = null;
                      });
                      _changed();
                    },
                  ),
                  if (_isCustomModel) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customController,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: '模型 ID',
                        hintText: '填写服务商提供的模型 ID',
                        errorText: _modelError,
                      ),
                    ),
                  ] else if (_modelError != null)
                    Text(_modelError!, style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 12),
                  ModelTags(providerId: _draft.providerId, model: currentModel),
                  if (modelFreeNote(_draft.providerId, currentModel)
                      case final String note)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        note,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (modelInfo(_draft.providerId, currentModel).detailsUrl
                      case final String url)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => openExternalUrl(context, url),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('查看免费额度说明'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _group('advanced', Icons.tune, '高级设置', '接口地址与协议', [
                    TextField(
                      controller: _baseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: '接口地址',
                        hintText: _draft.preset.url,
                        errorText: _urlError,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'protocol-${_draft.providerId}-${_draft.protocol}',
                      ),
                      initialValue: _draft.protocol,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '接口协议'),
                      items: const [
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI 兼容'),
                        ),
                        DropdownMenuItem(
                          value: 'responses',
                          child: Text('OpenAI Responses'),
                        ),
                        DropdownMenuItem(
                          value: 'anthropic',
                          child: Text('Anthropic Messages'),
                        ),
                        DropdownMenuItem(
                          value: 'gemini',
                          child: Text('Google Gemini'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(
                            () => _draft = _draft.copyWith(protocol: value),
                          );
                          _changed();
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _testConnection,
                    icon: const Icon(Icons.wifi_tethering),
                    label: Text(_testing ? '正在测试…' : '测试连接'),
                  ),
                  const Text(
                    '会产生 API 用量；测试不会自动保存。',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (_connectionStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_connectionStatus!),
                    ),
                ],
              ),
              _group('chat', Icons.chat_bubble_outline, '对话设置', '回复风格与图片', [
                TextField(
                  controller: _promptController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '系统提示词',
                    hintText: '例如：回答简洁，优先使用中文',
                  ),
                ),
                const SizedBox(height: 16),
                Text('回答发散度  ${_temperature.toStringAsFixed(1)}'),
                Slider(
                  value: _temperature.clamp(0, 2),
                  min: 0,
                  max: 2,
                  divisions: 20,
                  label: _temperature.toStringAsFixed(1),
                  onChanged: (value) {
                    setState(() => _temperature = value);
                    _changed();
                  },
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('更稳定'), Text('更多变化')],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许发送图片'),
                  subtitle: Text(
                    '当前模型：${AppSettings.modelShortName(currentModel)}',
                  ),
                  value: _imageSupport ?? modelSupportsImages(currentModel),
                  onChanged: (value) {
                    setState(() => _imageSupport = value);
                    _changed();
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        _help('图片能力', '仅对支持图片的模型开启。自定义模型的能力以服务商说明为准。'),
                    child: const Text('如何选择？'),
                  ),
                ),
              ]),
              _group(
                'appearance',
                Icons.palette_outlined,
                '外观设置',
                _themeLabel(_themeMode),
                [
                  for (final mode in AppSettings.availableThemeModes)
                    RadioListTile<String>(
                      value: mode,
                      // ignore: deprecated_member_use
                      groupValue: _themeMode,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        if (value != null) _setTheme(value);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text(_themeLabel(mode)),
                    ),
                  const Text('主题立即生效', style: TextStyle(fontSize: 12)),
                ],
              ),
              _group('data', Icons.folder_outlined, '数据管理', '导出、清理与重置', [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_download_outlined),
                  title: Text(_exporting ? '正在导出…' : '导出聊天文字'),
                  subtitle: const Text('不含密钥和图片文件'),
                  onTap: _exporting ? null : _exportHistory,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: scheme.error),
                  title: const Text('清空全部对话'),
                  onTap: _clearHistory,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('恢复默认设置'),
                  subtitle: const Text('清除配置，保留聊天记录'),
                  onTap: _confirmReset,
                ),
              ]),
              _group('about', Icons.info_outline, '关于万象', 'v$kAppVersion', [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/branding/icon.png',
                      width: 44,
                      height: 44,
                    ),
                  ),
                  title: const Text('万象'),
                  subtitle: const Text('版本 v$kAppVersion'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed(AboutPage.routeName),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('项目主页'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => openExternalUrl(context, kProjectRepoUrl),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('使用许可'),
                  subtitle: const Text('源码公开，禁止商用'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => openExternalUrl(
                    context,
                    '$kProjectRepoUrl/blob/main/LICENSE',
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseFreeModel() async {
    const choices = [
      ('openrouter', 'openrouter/free', '免费模型自动选择'),
      ('openrouter', 'qwen/qwen3.8-27b:free', 'Qwen 3.8 27B · 免费变体'),
      ('google', 'gemini-2.5-flash-lite', 'Gemini Flash-Lite · 免费额度'),
    ];
    final choice = await showModalBottomSheet<(String, String, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('选择免费模型'),
                subtitle: Text('需自己的 API Key，额度以官方平台为准'),
              ),
              for (final item in choices)
                ListTile(
                  title: Text(item.$3),
                  subtitle: Text(presetFor(item.$1).name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, item),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    _switchProvider(choice.$1);
    setState(() {
      _model = choice.$2;
      _isCustomModel = false;
      _imageSupport = null;
      _expanded.add('model');
    });
    _changed();
  }

  String _themeLabel(String mode) => switch (mode) {
    'light' => '浅色',
    'dark' => '深色',
    _ => '跟随系统',
  };

  Future<void> _help(String title, String text) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Widget _group(
    String id,
    IconData icon,
    String title,
    String summary,
    List<Widget> children,
  ) {
    final open = _expanded.contains(id);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: open,
            child: ListTile(
              key: ValueKey('section-$id'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: Icon(icon, color: scheme.primary),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
              onTap: () {
                FocusScope.of(context).unfocus();
                setState(() {
                  if (open) {
                    _expanded.remove(id);
                  } else {
                    _expanded.add(id);
                  }
                });
              },
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
