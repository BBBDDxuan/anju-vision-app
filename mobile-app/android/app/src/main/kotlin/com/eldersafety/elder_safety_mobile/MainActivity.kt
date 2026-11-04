package com.eldersafety.elder_safety_mobile

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelId = "elder_safety_alerts_v1"
    private var bridge: MethodChannel? = null
    private var initialEvent: String? = null
    private var initialScope: String? = null
    private var notificationsReady = false
    private var permissionResult: MethodChannel.Result? = null
    private val notificationPermissionRequest = 54103

    private fun clean(value: String?): String? = value?.trim()?.takeIf {
        it.isNotBlank() && it.length <= 256 && it.none { c -> c.code < 32 || c.code == 127 }
    }

    private fun validScope(value: String?): String? {
        val scope = clean(value) ?: return null
        if (!scope.endsWith("|default")) return null
        val origin = scope.removeSuffix("|default")
        if (origin.length > 200) return null
        return try {
            val uri = java.net.URI(origin)
            scope.takeIf {
                uri.scheme in setOf("http", "https") && !uri.host.isNullOrEmpty() &&
                    uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null &&
                    uri.rawPath.isNullOrEmpty()
            }
        } catch (_: Exception) { null }
    }

    private fun unifiedId(value: String?): Boolean = value?.matches(Regex("a_[0-9a-f]{40}")) == true

    private fun clearInitial() {
        initialEvent = null
        initialScope = null
        intent?.removeExtra("safety_event_id")
        intent?.removeExtra("safety_scope")
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(channelId, "居家危险提醒", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "实摄或录像的已复核安全事件提醒"
            channel.enableVibration(true)
            channel.lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
            manager.createNotificationChannel(channel)
        }
    }

    private fun notificationStatus(): Map<String, Boolean> {
        val requiresPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        val granted = !requiresPermission || ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        val channelEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).getNotificationChannel(channelId)
                ?.importance?.let { it != NotificationManager.IMPORTANCE_NONE } ?: false
        } else true
        return mapOf(
            "permission_required" to requiresPermission,
            "permission_granted" to granted,
            "app_enabled" to NotificationManagerCompat.from(this).areNotificationsEnabled(),
            "channel_enabled" to channelEnabled
        )
    }

    private fun openSystemSettings(action: String, result: MethodChannel.Result) {
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null))
        val target = when {
            action == "openChannelSettings" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            action == "openNotificationSettings" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            else -> details
        }
        try {
            try {
                startActivity(target)
            } catch (_: ActivityNotFoundException) {
                startActivity(details)
            }
            result.success(null)
        } catch (_: Exception) {
            result.error("SETTINGS_UNAVAILABLE", "无法打开系统设置，请从手机设置中进入应用通知", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequest) {
            val pending = permissionResult
            permissionResult = null
            pending?.success(notificationStatus())
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory("anju/rtsp-view", RtspViewFactory(flutterEngine.dartExecutor.binaryMessenger))
        // Create the channel even when Firebase is disabled.
        createChannel()
        initialEvent = clean(intent?.getStringExtra("safety_event_id"))
        initialScope = intent?.getStringExtra("safety_scope")
        bridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elder_safety/notifications")
        bridge!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    createChannel()
                    notificationsReady = true
                    result.success(null)
                }
                "initialAlert" -> {
                    val scope = validScope(initialScope)
                    val payload = if (scope != null && unifiedId(initialEvent))
                        mapOf("scope" to scope, "event_id" to initialEvent) else null
                    result.success(payload)
                    // A malformed scoped click must never become a legacy click.
                    if (initialScope != null) clearInitial()
                }
                "initialEvent" -> {
                    result.success(if (initialScope == null) initialEvent else null)
                    clearInitial()
                }
                "status" -> { createChannel(); result.success(notificationStatus()) }
                "requestPermission" -> {
                    createChannel()
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED) {
                        result.success(notificationStatus())
                    } else if (permissionResult != null) {
                        result.error("PERMISSION_PENDING", "通知权限申请正在进行", null)
                    } else {
                        permissionResult = result
                        try {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequest)
                        } catch (_: Exception) {
                            permissionResult = null
                            result.error("PERMISSION_FAILED", "无法申请通知权限，请打开系统设置", null)
                        }
                    }
                }
                "openAppSettings", "openNotificationSettings", "openChannelSettings" -> {
                    createChannel()
                    openSystemSettings(call.method, result)
                }
                "clear" -> {
                    getSystemService(NotificationManager::class.java).cancelAll()
                    result.success(null)
                }
                "show" -> {
                    val eventId = clean(call.argument<String>("event_id"))
                    val rawScope = call.argument<String>("scope")
                    val scope = validScope(rawScope)
                    if (eventId == null || (rawScope != null && (scope == null || !unifiedId(eventId)))) {
                        result.error("INVALID_EVENT", "Invalid event identifier", null)
                    } else {
                        try {
                            createChannel()
                            val status = notificationStatus()
                            if (status["permission_granted"] != true || status["app_enabled"] != true ||
                                status["channel_enabled"] != true) {
                                result.error("NOTIFICATIONS_DISABLED", "系统通知权限或渠道未开启", null)
                                return@setMethodCallHandler
                            }
                            val noticeId = (scope.orEmpty() + eventId).hashCode()
                            val open = Intent(this, MainActivity::class.java)
                                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                .putExtra("safety_event_id", eventId)
                                .putExtra("safety_scope", scope)
                            // An event-specific URI prevents pending-intent identity collisions.
                            open.data = android.net.Uri.Builder().scheme("elder-safety")
                                .authority("notification").appendPath(scope.orEmpty()).appendPath(eventId).build()
                            val pending = PendingIntent.getActivity(this, noticeId, open,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                            val notice = NotificationCompat.Builder(this, channelId)
                                .setSmallIcon(R.drawable.ic_stat_safety)
                                .setContentTitle("居家安全提醒")
                                .setContentText("检测到疑似危险，请打开应用查看并确认。")
                                .setPriority(NotificationCompat.PRIORITY_HIGH)
                                .setCategory(NotificationCompat.CATEGORY_ALARM)
                                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                                .setDefaults(NotificationCompat.DEFAULT_ALL)
                                .setOnlyAlertOnce(true)
                                .setAutoCancel(true)
                                .setContentIntent(pending)
                                .build()
                            getSystemService(NotificationManager::class.java).notify(eventId, 0, notice)
                            result.success(null)
                        } catch (_: SecurityException) {
                            result.error("PERMISSION_DENIED", "Notification permission required", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        notificationsReady = false
        permissionResult?.error("ACTIVITY_DESTROYED", "请返回应用后重新检查通知权限", null)
        permissionResult = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val event = clean(intent.getStringExtra("safety_event_id")) ?: return
        val rawScope = intent.getStringExtra("safety_scope")
        if (rawScope != null && (validScope(rawScope) == null || !unifiedId(event))) {
            clearInitial()
            return
        }
        if (notificationsReady && bridge != null) {
            if (rawScope != null) {
                bridge?.invokeMethod("openAlert", mapOf("scope" to rawScope, "event_id" to event))
            } else {
                bridge?.invokeMethod("openEvent", event)
            }
            clearInitial()
        } else {
            initialEvent = event
            initialScope = rawScope
        }
    }
}
