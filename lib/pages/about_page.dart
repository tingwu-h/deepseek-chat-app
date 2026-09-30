import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:deepseek_chat/utils/app_info.dart';

/// 关于页：版本号、创作者、相关链接。
///
/// 版本号从设置页底部挪到了这里（设置页底部不再显示）。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String routeName = '/about';

  static const String _platformUrl = kDeepSeekPlatformUrl;
  static const String _docsUrl = kDeepSeekDocsUrl;
  static const String _repoUrl = kProjectRepoUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: <Widget>[
          // 应用标识 + 版本号
          Center(
            child: Column(
              children: <Widget>[
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.forum_outlined,
                    size: 40,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'DeepSeek 助手',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '版本 v$kAppVersion',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // 创作者
          const Card(
            child: ListTile(
              leading: Icon(Icons.person_outline),
              title: Text('创作者'),
              subtitle: Text(kAppAuthor),
            ),
          ),

          const SizedBox(height: 12),

          // 链接
          const Card(
            child: Column(
              children: <Widget>[
                _LinkTile(
                  icon: Icons.key_outlined,
                  title: 'DeepSeek 开放平台',
                  subtitle: '申请 API Key、查看用量与充值',
                  url: _platformUrl,
                ),
                Divider(height: 1, indent: 56),
                _LinkTile(
                  icon: Icons.menu_book_outlined,
                  title: 'API 文档',
                  subtitle: '模型名、参数与价格说明',
                  url: _docsUrl,
                ),
                Divider(height: 1, indent: 56),
                _LinkTile(
                  icon: Icons.code,
                  title: '项目源码',
                  subtitle: 'GitHub 仓库（MIT 许可）',
                  url: _repoUrl,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 免责说明
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '本应用是个人开源作品，与 DeepSeek 官方无关。\n'
              'API Key 只保存在手机本地，除了 DeepSeek 官方接口外不会发送给任何服务器。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行可点击的链接：点了用系统浏览器打开
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () async {
        final Uri uri = Uri.parse(url);
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        try {
          final bool ok = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!ok) throw Exception('无法打开');
        } catch (_) {
          // 没有浏览器可用时，至少把网址告诉用户，而不是静默失败
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
        }
      },
    );
  }
}
