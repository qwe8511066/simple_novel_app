import 'package:flutter/services.dart';

class VolumeKeyController {
  static const MethodChannel _controlChannel = 
      MethodChannel('com.example.app/volume_control');

  /// 启用或禁用音量键拦截
  static Future<void> setVolumeKeysEnabled(bool enabled) async {
    try {
      await _controlChannel.invokeMethod('enableVolumeKeys', {'enabled': enabled});
    } catch (e) {
      // 忽略错误，可能在非Android平台运行
    }
  }

  /// 更新音量键拦截的详细状态
  /// [shouldIntercept] 决定是否拦截音量键
  static Future<void> updateVolumeKeyStatus({bool shouldIntercept = true}) async {
    try {
      await _controlChannel.invokeMethod('updateVolumeKeyStatus', {
        'shouldIntercept': shouldIntercept,
      });
    } catch (e) {
      // 忽略错误，可能在非Android平台运行
    }
  }
}