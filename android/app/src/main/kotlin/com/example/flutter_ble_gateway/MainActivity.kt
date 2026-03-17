package com.example.flutter_ble_gateway

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.provider.Settings
import android.text.TextUtils

/**
 * MainActivity wires up the MethodChannel for notification permission helpers.
 *
 * The EventChannel for forwarding live notifications is registered inside
 * [GatewayNotificationListenerService] itself, which keeps the concerns
 * separated and avoids having to pass the engine reference around.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val PERMISSION_CHANNEL =
            "com.example.flutter_ble_gateway/notification_permission"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the EventChannel so the notification service can push events
        GatewayNotificationListenerService.registerEventChannel(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationPermissionGranted" ->
                    result.success(isNotificationServiceEnabled())

                "openNotificationSettings" -> {
                    startActivity(
                        android.content.Intent(
                            Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS
                        )
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Checks whether this app's [GatewayNotificationListenerService] is
     * listed in the system's enabled notification listener components.
     */
    private fun isNotificationServiceEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        val names = flat.split(":")
        val myComponent = ComponentName(this, GatewayNotificationListenerService::class.java)
        return names.any { name ->
            if (name.isEmpty()) return@any false
            val cn = ComponentName.unflattenFromString(name)
            cn != null && TextUtils.equals(cn.packageName, myComponent.packageName) &&
                    TextUtils.equals(cn.className, myComponent.className)
        }
    }
}
