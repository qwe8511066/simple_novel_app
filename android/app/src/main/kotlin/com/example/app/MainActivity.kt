package com.example.app

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "com.example.app/volume_keys"
  private var channel: MethodChannel? = null
  private var volumeKeysEnabled = false // 控制音量键是否被拦截
  private var volumeKeyInterceptCondition = true // 额外的拦截条件

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
    
    // 添加用于控制音量键拦截的方法
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.app/volume_control").setMethodCallHandler { call, result ->
      when (call.method) {
        "enableVolumeKeys" -> {
          volumeKeysEnabled = call.argument<Boolean>("enabled") ?: false
          result.success(null)
        }
        "updateVolumeKeyStatus" -> {
          volumeKeyInterceptCondition = call.argument<Boolean>("shouldIntercept") ?: true
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  override fun dispatchKeyEvent(event: KeyEvent): Boolean {
    if (event.action == KeyEvent.ACTION_DOWN && volumeKeysEnabled && volumeKeyInterceptCondition) {
      when (event.keyCode) {
        KeyEvent.KEYCODE_VOLUME_UP -> {
          channel?.invokeMethod("volume_up", null)
          return true
        }

        KeyEvent.KEYCODE_VOLUME_DOWN -> {
          channel?.invokeMethod("volume_down", null)
          return true
        }
      }
    }
    return super.dispatchKeyEvent(event)
  }
}
