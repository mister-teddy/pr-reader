package de.reonic.pr_reader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pr_reader/widgets").setMethodCallHandler { call, result ->
            when (call.method) {
                "pin" -> result.success(PrWidget.pin(this, call.argument<String>("key")!!))
                "pinned" -> result.success(PrWidget.pinned(this))
                "refresh" -> {
                    PrWidget.refreshAll(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
