import 'package:flutter/material.dart';

import 'package:deepseek_chat/utils/app_info.dart';
import 'package:deepseek_chat/utils/link_actions.dart';

/// 关于页：版本号、创作者、相关链接。
///
/// 版本号从设置页底部挪到了这里（设置页底部不再显示）。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String routeName = '/about';

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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset('assets/branding/icon.png'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '万象',
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

          // 创作者：点了跳到 GitHub 主页
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('创作者'),
              subtitle: const Text(kAppAuthor),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openGithubProfile(context),
            ),
          ),

          const SizedBox(height: 12),

          // 链接
          const Card(
            child: Column(
              children: <Widget>[
                _LinkTile(
                  icon: Icons.code,
                  title: '项目源码',
                  subtitle: '源码公开，禁止商用',
                  url: _repoUrl,
                ),
                _LinkTile(
                  icon: Icons.description_outlined,
                  title: '使用许可',
                  subtitle: '万象非商业使用许可证',
                  url: '$_repoUrl/blob/main/LICENSE',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 免责说明
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '本应用是个人作品，与各模型服务商无隶属关系。\n'
              'API Key 在本机加密保存；请求时，密钥和聊天内容发送到你为当前服务商设置的接口。',
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
      // 逻辑统一在 link_actions.dart（失败时会把网址显示出来）
      onTap: () => openExternalUrl(context, url),
    );
  }
}
