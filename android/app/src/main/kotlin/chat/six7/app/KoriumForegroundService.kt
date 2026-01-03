package chat.six7.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Foreground service to keep Korium P2P node running in the background.
 *
 * SECURITY (per AGENTS.md):
 * - Uses WAKE_LOCK with bounded timeout to prevent battery drain
 * - Notification clearly indicates network activity to user
 * - Service is stoppable via notification action
 *
 * ARCHITECTURE:
 * - Started by KoriumBridge when node is created
 * - Stopped when node is shutdown
 * - Shows persistent notification while active
 */
class KoriumForegroundService : Service() {

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "six7_foreground_service"
        private const val CHANNEL_NAME = "Six7 Connection"

        // Actions
        const val ACTION_START = "chat.six7.app.action.START_FOREGROUND"
        const val ACTION_STOP = "chat.six7.app.action.STOP_FOREGROUND"

        // Wake lock tag
        private const val WAKE_LOCK_TAG = "six7:KoriumService"

        // Maximum wake lock hold time (4 hours) to prevent runaway battery drain
        private const val MAX_WAKE_LOCK_MS = 4 * 60 * 60 * 1000L

        /**
         * Starts the foreground service.
         */
        fun start(context: Context) {
            val intent = Intent(context, KoriumForegroundService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /**
         * Stops the foreground service.
         */
        fun stop(context: Context) {
            val intent = Intent(context, KoriumForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundWithNotification()
                acquireWakeLock()
            }
            ACTION_STOP -> {
                stopForegroundService()
            }
        }
        // If killed, restart with the last intent
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW // Low importance = no sound, shows in status bar
            ).apply {
                description = "Keeps Six7 connected for receiving messages"
                setShowBadge(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundWithNotification() {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(): Notification {
        // Intent to open the app when notification is tapped
        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent to stop the service
        val stopIntent = Intent(this, KoriumForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Six7")
            .setContentText("Connected and receiving messages")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // TODO: Use proper app icon
            .setContentIntent(openAppPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Disconnect",
                stopPendingIntent
            )
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG
            ).apply {
                // SECURITY: Bounded timeout prevents runaway battery drain
                acquire(MAX_WAKE_LOCK_MS)
            }
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }

    private fun stopForegroundService() {
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
}
