package com.example.app

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val channelName = "com.example.app/volume_keys"
  private var channel: MethodChannel? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
  }

  override fun dispatchKeyEvent(event: KeyEvent): Boolean {
    if (event.action == KeyEvent.ACTION_DOWN) {
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
