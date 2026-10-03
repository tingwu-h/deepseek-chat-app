/// Selection hints, not benchmarks or promises of account access.
class ModelInfo {
  const ModelInfo(this.tags, {this.freeNote, this.detailsUrl});
  final List<String> tags;
  final String? freeNote;
  final String? detailsUrl;
}

const _modelInfo = <String, ModelInfo>{
  'deepseek/deepseek-flash': ModelInfo(['日常问答', '快速回复']),
  'deepseek/deepseek-v4-pro': ModelInfo(['复杂推理', '编程']),
  'deepseek/deepseek-chat': ModelInfo(['日常问答', '写作']),
  'deepseek/deepseek-reasoner': ModelInfo(['复杂推理', '数学']),
  'openai/gpt-4.1': ModelInfo(['编程', '长文', '图片理解']),
  'openai/gpt-4.1-mini': ModelInfo(['日常问答', '编程', '图片理解']),
  'kimi/kimi-k2.5': ModelInfo(['编程', '长文', '图片理解']),
  'kimi/moonshot-v1-8k': ModelInfo(['日常问答', '写作']),
  'qwen/qwen-plus': ModelInfo(['日常问答', '写作', '编程']),
  'qwen/qwen-turbo': ModelInfo(['快速回复', '日常问答']),
  'qwen/qwen-vl-plus': ModelInfo(['图片理解', '图文问答']),
  'anthropic/claude-sonnet-4-5': ModelInfo(['编程', '写作', '图片理解']),
  'anthropic/claude-haiku-4-5': ModelInfo(['快速回复', '编程']),
  'google/gemini-2.5-flash': ModelInfo(['日常问答', '图片理解', '长文']),
  'google/gemini-2.5-pro': ModelInfo(['复杂推理', '编程', '长文']),
  'google/gemini-2.5-flash-lite': ModelInfo(
    ['快速回复', '图片理解', '免费额度'],
    freeNote: '需 Google API Key。免费层有额度和地区限制，付费层按量计费；免费层内容可能用于改进产品。',
    detailsUrl:
        'https://ai.google.dev/gemini-api/docs/pricing#gemini-2.5-flash-lite',
  ),
  'xai/grok-4': ModelInfo(['复杂推理', '日常问答']),
  'xai/grok-3-mini': ModelInfo(['复杂推理', '快速回复']),
  'glm/glm-4.7': ModelInfo(['编程', '复杂推理']),
  'glm/glm-4.6v': ModelInfo(['图片理解', '图文问答']),
  'openrouter/openrouter/free': ModelInfo(
    ['自动选模', '日常问答', '限额免费'],
    freeNote: '需 OpenRouter API Key。自动选择可用的免费模型，能力和可用性可能变化；有请求限额。',
    detailsUrl: 'https://openrouter.ai/openrouter/free',
  ),
  'openrouter/qwen/qwen3.8-27b:free': ModelInfo(
    ['编程', '图片理解', '限额免费'],
    freeNote: '需 OpenRouter API Key。使用免费变体，有请求限额；供应商可用性以平台为准。',
    detailsUrl: 'https://openrouter.ai/qwen/qwen3.8-27b:free',
  ),
};

ModelInfo modelInfo(String provider, String model) =>
    _modelInfo['$provider/$model'] ?? const ModelInfo(['自定义模型', '能力待确认']);
String modelTagSummary(String provider, String model) =>
    modelInfo(provider, model).tags.join(' · ');
String? modelFreeNote(String provider, String model) =>
    modelInfo(provider, model).freeNote;
