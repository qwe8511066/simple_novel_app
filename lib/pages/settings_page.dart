import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import '../components/web_service_button.dart';
import '../components/novel_import_button.dart';
import '../providers/novel_provider.dart';

/// 设置页面
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 阅读设置
        _buildSectionHeader(context, '阅读设置'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Consumer<NovelProvider>(
            builder: (context, provider, child) {
              // 根据字体大小返回标签
              String fontSizeLabel = switch (provider.fontSize) {
                14 => '小',
                18 => '中等',
                22 => '大',
                _ => '中等',
              };
              
              return Column(
                children: [
                  _buildSettingItem(
                    context: context,
                    icon: Icons.text_fields,
                    title: '字体大小',
                    subtitle: '当前: $fontSizeLabel',
                    onTap: () => _showFontSizeDialog(context),
                  ),
                  _buildSettingItem(
                    context: context,
                    icon: Icons.palette,
                    title: '主题色',
                    subtitle: '点击选择喜欢的颜色',
                    onTap: () => _showColorPickerDialog(context),
                  ),
                  _buildSettingItem(
                    context: context,
                    icon: Icons.wallpaper,
                    title: '书架背景',
                    subtitle: '点击设置书架背景',
                    onTap: () => _showBookshelfBackgroundDialog(context),
                  ),
                  _buildSettingItem(
                     context: context,
                     icon: Icons.brightness_6,
                     title: '夜间模式',
                     subtitle: '当前: ${provider.isDarkMode ? '开启' : '关闭'}',
                     trailing: Switch(
                       value: provider.isDarkMode,
                       onChanged: (value) async {
                         await provider.toggleDarkMode();
                       },
                     ),
                   ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // 偏好设置
        _buildSectionHeader(context, '偏好设置'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Web服务',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const WebServiceButton(),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        // 关于
        _buildSectionHeader(context, '关于'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildSettingItem(
                 context: context,
                 icon: Icons.info,
                 title: '版本信息',
                 subtitle: 'v1.0.0',
                 onTap: () {},
               ),
               _buildSettingItem(
                 context: context,
                 icon: Icons.description,
                 title: '用户协议',
                 onTap: () {},
               ),
               _buildSettingItem(
                 context: context,
                 icon: Icons.privacy_tip,
                 title: '隐私政策',
                 onTap: () {},
               ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        subtitle: subtitle != null ? Text(subtitle, style: Theme.of(context).textTheme.bodySmall) : null,
        trailing: trailing ?? Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).primaryColor),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('选择字体大小', style: Theme.of(context).textTheme.titleMedium),
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
            child: Text('关闭', style: Theme.of(context).textTheme.bodyMedium),
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
    final provider = Provider.of<NovelProvider>(context, listen: false);
    return ListTile(
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      onTap: () async {
        await provider.setFontSize(size);
        Navigator.pop(context);
      },
    );
  }

  void _showColorPickerDialog(BuildContext context) {
    final provider = Provider.of<NovelProvider>(context, listen: false);
    Color selectedColor = provider.themeColor;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('选择主题色', style: Theme.of(context).textTheme.titleMedium),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预定义颜色选项
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Colors.red,
                  Colors.orange,
                  Colors.yellow,
                  Colors.green,
                  Colors.blue,
                  Colors.indigo,
                  Colors.purple,
                  Colors.pink,
                  Colors.brown,
                  Colors.teal,
                  Colors.cyan,
                  Colors.deepOrange,
                ].map((color) => GestureDetector(
                  onTap: () async {
                    selectedColor = color;
                    await provider.setThemeColor(color);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedColor == color ? Colors.black : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
              // 自定义颜色选择器
              Text('或自定义颜色:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 200,
                child: ColorPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (color) {
                    selectedColor = color;
                  },
                  showLabel: true,
                  pickerAreaHeightPercent: 0.8,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: Theme.of(context).textTheme.bodyMedium),
          ),
          TextButton(
            onPressed: () async {
              await provider.setThemeColor(selectedColor);
              Navigator.pop(context);
            },
            child: Text('确认', style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
  
  void _showBookshelfBackgroundDialog(BuildContext context) {
    final provider = Provider.of<NovelProvider>(context, listen: false);
    Color selectedColor = provider.bookshelfBackgroundColor;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('书架背景设置', style: Theme.of(context).textTheme.titleMedium),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 选择背景类型
              Text('选择背景类型:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _showBookshelfColorPicker(context),
                    icon: const Icon(Icons.color_lens),
                    label: const Text('背景颜色'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showBookshelfImagePicker(context),
                    icon: const Icon(Icons.image),
                    label: const Text('背景图片'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 当前背景预览
              Text('当前背景:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  color: provider.bookshelfBackgroundImage == null 
                      ? provider.bookshelfBackgroundColor 
                      : null,
                  image: provider.bookshelfBackgroundImage != null
                      ? DecorationImage(
                          image: FileImage(File(provider.bookshelfBackgroundImage!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: provider.bookshelfBackgroundImage == null
                    ? Center(
                        child: Text(
                          '纯色背景',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.5),
                                offset: const Offset(1, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭', style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
  
  void _showBookshelfColorPicker(BuildContext context) {
    final provider = Provider.of<NovelProvider>(context, listen: false);
    Color selectedColor = provider.bookshelfBackgroundColor;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('选择书架背景色', style: Theme.of(context).textTheme.titleMedium),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预定义颜色选项
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Colors.white,
                  Colors.grey[100],
                  Colors.grey[200],
                  Colors.grey[300],
                  Colors.blue[50],
                  Colors.green[50],
                  Colors.yellow[50],
                  Colors.red[50],
                  Colors.purple[50],
                  Colors.teal[50],
                  Colors.cyan[50],
                  Colors.orange[50],
                  Colors.brown[50],
                  Colors.black,
                  Colors.grey[800],
                  Colors.grey[900],
                ].map((color) => GestureDetector(
                  onTap: () async {
                    if (color != null) {
                      selectedColor = color;
                      await provider.setBookshelfBackgroundColor(color);
                      Navigator.pop(context);
                    }
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedColor == color ? Colors.black : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
              // 自定义颜色选择器
              Text('或自定义颜色:', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 200,
                child: ColorPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (color) {
                    selectedColor = color;
                  },
                  showLabel: true,
                  pickerAreaHeightPercent: 0.8,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: Theme.of(context).textTheme.bodyMedium),
          ),
          TextButton(
            onPressed: () async {
              await provider.setBookshelfBackgroundColor(selectedColor);
              Navigator.pop(context);
            },
            child: Text('确认', style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
  
  void _showBookshelfImagePicker(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final provider = Provider.of<NovelProvider>(context, listen: false);
      await provider.setBookshelfBackgroundImage(image.path);
    }
  }
}
