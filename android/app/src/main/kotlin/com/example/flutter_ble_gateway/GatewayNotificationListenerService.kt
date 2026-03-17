package com.example.flutter_ble_gateway

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * Android [NotificationListenerService] that captures status-bar notifications
 * from all apps and forwards them to the Flutter layer through an [EventChannel].
 *
 * ### Enabling the service
 * The user must explicitly grant notification access:
 * **Settings → Apps → Special app access → Notification access → BLE Gateway**
 *
 * The [MainActivity] automatically detects whether this permission is granted
 * and prompts the user to open the settings screen if it is not.
 *
 * ### AndroidManifest.xml
 * ```xml
 * <service
 *     android:name=".GatewayNotificationListenerService"
 *     android:label="BLE Gateway Notification Service"
 *     android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
 *     android:exported="true">
 *     <intent-filter>
 *         <action android:name="android.service.notification.NotificationListenerService" />
 *     </intent-filter>
 * </service>
 * ```
 */
class GatewayNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val NOTIFICATION_CHANNEL =
            "com.example.flutter_ble_gateway/notifications"

        /** Singleton event sink; set by [registerEventChannel]. */
        @Volatile
        private var eventSink: EventChannel.EventSink? = null

        /**
         * Must be called from [MainActivity.configureFlutterEngine] to wire
         * the [EventChannel] into the Flutter engine.
         */
        fun registerEventChannel(engine: FlutterEngine) {
            EventChannel(
                engine.dartExecutor.binaryMessenger,
                NOTIFICATION_CHANNEL
            ).setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    // ── NotificationListenerService callbacks ─────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras ?: return

        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text  = extras.getCharSequence("android.text")?.toString()
            ?: extras.getCharSequence("android.bigText")?.toString()
            ?: ""

        // Skip empty notifications and system UI noise
        if (title.isEmpty() && text.isEmpty()) return
        if (sbn.packageName == "android" || sbn.packageName == "com.android.systemui") return

        val payload = mapOf(
            "package" to sbn.packageName,
            "title"   to title,
            "text"    to text
        )

        // EventChannel.EventSink must be called on the main (platform) thread.
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(payload)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Not needed for this use-case; notifications are forwarded on post.
    }
}
