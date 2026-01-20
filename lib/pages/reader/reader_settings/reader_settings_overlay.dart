import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../providers/novel_provider.dart';
import '../../../utils/statusBarStyle.dart';

class ReaderSettingsOverlay extends StatefulWidget {
  final VoidCallback onBack;

  const ReaderSettingsOverlay({
    super.key,
    required this.onBack,
  });

  @override
  _ReaderSettingsOverlayState createState() => _ReaderSettingsOverlayState();
}

class _ReaderSettingsOverlayState extends State<ReaderSettingsOverlay> {
  // 当前选中的设置标签页
  int _currentTabIndex = 0;
  
  // 可用字体列表
  final List<String> _availableFonts = [
    'FZZiZhuAYuanTiB',
    'serif',
  ];

  @override
  Widget build(BuildContext context) {
    final novelProvider = Provider.of<NovelProvider>(context);
    final themeColor = novelProvider.themeColor;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 背景遮罩
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onBack,
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
          // 设置弹窗
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).size.height * 0.7,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  
                  // 标签栏
                  Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTabButton(0, '背景', themeColor),
                  _buildTabButton(1, '间距', themeColor),
                  _buildTabButton(2, '字体', themeColor),
                  _buildTabButton(3, '界面', themeColor),
                        ],
                      ),
                    ),
                  ),
                  
                  // 内容区域
                  Expanded(
                    child: _currentTabIndex == 0
                      ? _buildBackgroundSettings(novelProvider)
                      : _currentTabIndex == 1
                          ? _buildPaddingSettings(novelProvider)
                          : _currentTabIndex == 2
                              ? _buildFontSettings(novelProvider)
                              : _buildInterfaceSettings(novelProvider),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建标签按钮
  Widget _buildTabButton(int index, String title, Color themeColor) {
    final isSelected = _currentTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? themeColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? themeColor : Colors.grey[600],
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  /// 构建背景设置页面
  Widget _buildBackgroundSettings(NovelProvider novelProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '背景类型',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showColorPicker(novelProvider),
                icon: const Icon(Icons.color_lens),
                label: const Text('背景颜色'),
              ),
              ElevatedButton.icon(
                onPressed: () => _pickImage(novelProvider),
                icon: const Icon(Icons.image),
                label: const Text('背景图片'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            '当前背景预览',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: novelProvider.readerBackgroundImage == null 
                  ? novelProvider.readerBackgroundColor 
                  : null,
              image: novelProvider.readerBackgroundImage != null
                  ? DecorationImage(
                      image: novelProvider.readerBackgroundImage!.startsWith('assets/')
                          ? AssetImage(novelProvider.readerBackgroundImage!)
                          : FileImage(File(novelProvider.readerBackgroundImage!)),
                      fit: BoxFit.contain,
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              novelProvider.resetBackgroundSettings();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重置背景设置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建间距设置页面
  Widget _buildPaddingSettings(NovelProvider novelProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPaddingSlider(
            '顶部间距',
            novelProvider.readerPaddingTop,
            (value) => novelProvider.setReaderPadding(top: value),
            0, 180,
          ),
          _buildPaddingSlider(
            '底部间距',
            novelProvider.readerPaddingBottom,
            (value) => novelProvider.setReaderPadding(bottom: value),
            0, 180,
          ),
          _buildPaddingSlider(
            '左侧间距',
            novelProvider.readerPaddingLeft,
            (value) => novelProvider.setReaderPadding(left: value),
            0, 180,
          ),
          _buildPaddingSlider(
            '右侧间距',
            novelProvider.readerPaddingRight,
            (value) => novelProvider.setReaderPadding(right: value),
            0, 180,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              novelProvider.resetPaddingSettings();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重置间距设置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建间距滑块
  Widget _buildPaddingSlider(
    String title,
    double currentValue,
    Function(double) onChanged,
    double min,
    double max,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title),
            Text('${currentValue.toInt()}px'),
          ],
        ),
        Slider(
          value: currentValue,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
  
  /// 构建字体设置页面
  Widget _buildFontSettings(NovelProvider novelProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '字体选择',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // 系统字体选项
              ..._availableFonts.map((font) {
                final isSelected = novelProvider.fontFamily == font;
                return GestureDetector(
                  onTap: () => novelProvider.setFontFamily(font),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      font,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontFamily: font,
                      ),
                    ),
                  ),
                );
              }).toList(),
              // 第三方字体选项（如果已选择）
              if (novelProvider.customFontPath != null && 
                  novelProvider.customFontPath!.isNotEmpty)
                GestureDetector(
                  onTap: () => {}, // 点击第三方字体不执行任何操作
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue, // 始终显示为选中状态
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text(
                          // 显示文件名作为字体名称
                          novelProvider.customFontPath!.split(Platform.pathSeparator).last,
                          style: const TextStyle(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 添加第三方字体图标或标识
                        const Icon(
                          Icons.download,
                          size: 16,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                )
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _pickFontFile(novelProvider),
            icon: const Icon(Icons.font_download),
            label: const Text('选择第三方字体'),
          ),
          const SizedBox(height: 24),
          _buildFontWeightSelector(novelProvider),
          _buildFontSlider(
            '字体大小',
            novelProvider.readerFontSize,
            (value) => novelProvider.setReaderFontSize(value),
            12, 36,
            1,
          ),
          _buildFontSlider(
            '字距',
            novelProvider.letterSpacing,
            (value) => novelProvider.setLetterSpacing(value),
            -2, 2,
            0.1,
          ),
          _buildFontSlider(
            '行距',
            novelProvider.lineSpacing,
            (value) => novelProvider.setLineSpacing(value),
            1, 3,
            0.1,
          ),
          _buildFontSlider(
            '段距',
            novelProvider.paragraphSpacing,
            (value) => novelProvider.setParagraphSpacing(value),
            0, 40,
            1,
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              novelProvider.resetFontSettings();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重置字体设置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建字体粗细选择器
  Widget _buildFontWeightSelector(NovelProvider novelProvider) {
    // 定义可用的字体粗细选项
    final List<Map<String, dynamic>> fontWeightOptions = [
      {'label': '细体', 'weight': FontWeight.w300},
      {'label': '常规', 'weight': FontWeight.normal},
      {'label': '粗体', 'weight': FontWeight.bold},
      {'label': '特粗', 'weight': FontWeight.w900},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('字体粗细'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: fontWeightOptions.map((option) {
            final isSelected = novelProvider.fontWeight == option['weight'];
            return GestureDetector(
              onTap: () => novelProvider.setFontWeight(option['weight']),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  option['label'],
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: option['weight'],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 构建字体设置滑块
  Widget _buildFontSlider(
    String title,
    double currentValue,
    Function(double) onChanged,
    double min,
    double max,
    double division,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title),
            Text(currentValue.toStringAsFixed(1)),
          ],
        ),
        Slider(
          value: currentValue,
          min: min,
          max: max,
          divisions: ((max - min) / division).toInt(),
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
  
  /// 显示颜色选择器
  void _showColorPicker(NovelProvider novelProvider) {
    Color selectedColor = novelProvider.readerBackgroundColor;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择背景颜色'),
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
                  onTap: () {
                    if (color != null) {
                      selectedColor = color;
                      novelProvider.setReaderBackgroundColor(color);
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
            ],
          ),
        ),
      ),
    );
  }
  
  /// 选择图片
  Future<void> _pickImage(NovelProvider novelProvider) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      novelProvider.setReaderBackgroundImage(pickedFile.path);
    }
  }
  
  /// 选择字体文件
  Future<void> _pickFontFile(NovelProvider novelProvider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
      );
      
      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.single.path;
        if (filePath != null) {
          // 直接使用文件路径作为字体族名
          novelProvider.setFontFamily(filePath);
        }
      }
    } catch (e) {
      debugPrint('选择字体文件失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('选择字体文件失败')),
      );
    }
  }
  
  /// 构建界面设置页面
  Widget _buildInterfaceSettings(NovelProvider novelProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '翻页动画',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ...['左右翻页', '覆盖翻页','仿真翻页'].map((animation) {
                final isSelected = novelProvider.readerTurnAnimation == animation;
                return GestureDetector(
                  onTap: () => novelProvider.setReaderTurnAnimation(animation),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      animation,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
          const SizedBox(height: 24),
          _buildSwitchItem(
            '音量键翻页',
            novelProvider.volumeKeyPageTurning,
            (value) => novelProvider.setVolumeKeyPageTurning(value),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              novelProvider.resetInterfaceSettings();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重置界面设置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 构建开关项
  Widget _buildSwitchItem(
    String title,
    bool currentValue,
    Function(bool) onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title),
        Switch(
          value: currentValue,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
