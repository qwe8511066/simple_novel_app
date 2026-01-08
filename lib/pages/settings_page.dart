import 'package:flutter/material.dart';
import '../components/web_service_button.dart';

/// 设置页面
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 阅读设置
        _buildSectionHeader('阅读设置'),
        _buildSettingItem(
          icon: Icons.text_fields,
          title: '字体大小',
          subtitle: '当前: 中等',
          onTap: () => _showFontSizeDialog(context),
        ),
        _buildSettingItem(
          icon: Icons.brightness_6,
          title: '夜间模式',
          subtitle: '当前: 关闭',
          trailing: Switch(
            value: false,
            onChanged: (value) {
              // TODO: 实现夜间模式切换
            },
          ),
        ),
        const SizedBox(height: 24),
        // 偏好设置
        _buildSectionHeader('偏好设置'),
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Icon(Icons.wifi, color: Colors.blue),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Web服务'),
                ),
                const WebServiceButton(),
              ],
            ),
          ),
        ),
        _buildSettingItem(
          icon: Icons.auto_stories,
          title: '自动翻页',
          subtitle: '当前: 关闭',
          trailing: Switch(
            value: false,
            onChanged: (value) {
              // TODO: 实现自动翻页
            },
          ),
        ),
        _buildSettingItem(
          icon: Icons.animation,
          title: '翻页动画',
          subtitle: '当前: 滑动',
          onTap: () {},
        ),
        const SizedBox(height: 24),
        // 关于
        _buildSectionHeader('关于'),
        _buildSettingItem(
          icon: Icons.info,
          title: '版本信息',
          subtitle: 'v1.0.0',
          onTap: () {},
        ),
        _buildSettingItem(
          icon: Icons.description,
          title: '用户协议',
          onTap: () {},
        ),
        _buildSettingItem(
          icon: Icons.privacy_tip,
          title: '隐私政策',
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.blue[700],
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择字体大小'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFontSizeOption(context, '小', 14),
            _buildFontSizeOption(context, '中等', 18),
            _buildFontSizeOption(context, '大', 22),
            _buildFontSizeOption(context, '特大', 26),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildFontSizeOption(
    BuildContext context,
    String label,
    double size,
  ) {
    return ListTile(
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
      },
    );
  }
}
