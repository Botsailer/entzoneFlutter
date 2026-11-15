package com.botsailer.depressedzone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Keeps the process alive while a download runs, and owns its notification.
 *
 * The transfer itself stays in Dart — it already knows the queue, the Referer
 * the CDN demands, and where the partial file is. This service exists for the
 * one thing Dart cannot do: tell Android that the app is doing work the user
 * asked for, so it is not frozen or killed the moment the screen goes off.
 */
class DownloadService : Service() {

    companion object {
        private const val CHANNEL_PROGRESS = "downloads"
        private const val CHANNEL_DONE = "downloads_done"
        private const val ONGOING_ID = 4201
        private var doneId = 4300

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_SUBTITLE = "subtitle"
        private const val EXTRA_PERCENT = "percent"

        private const val ACTION_START = "start"
        private const val ACTION_PROGRESS = "progress"
        private const val ACTION_STOP = "stop"

        fun start(context: Context, title: String, subtitle: String) {
            val i = Intent(context, DownloadService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_SUBTITLE, subtitle)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        }

        fun progress(context: Context, title: String, percent: Int) {
            context.startService(
                Intent(context, DownloadService::class.java)
                    .setAction(ACTION_PROGRESS)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_PERCENT, percent),
            )
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, DownloadService::class.java).setAction(ACTION_STOP),
            )
        }

        /** A finished download gets its own dismissible notification. */
        fun complete(context: Context, title: String, subtitle: String) {
            if (!context.canPost()) return
            ensureChannels(context)
            val n = NotificationCompat.Builder(context, CHANNEL_DONE)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(title)
                .setContentText(subtitle)
                .setContentIntent(openApp(context))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(doneId++, n)
            } catch (_: SecurityException) {
            }
        }

        private fun openApp(context: Context): PendingIntent? {
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?: return null
            launch.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            return PendingIntent.getActivity(
                context,
                0,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        private fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_PROGRESS,
                    "Downloads in progress",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shows a film or episode being saved for offline viewing."
                    setShowBadge(false)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_DONE,
                    "Downloads finished",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Tells you when something is ready to watch offline."
                },
            )
        }

        private fun Context.canPost(): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
    }

    private var running = false
    private var title = ""
    private var subtitle = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannels(this)

        when (intent?.action) {
            ACTION_START -> {
                title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
                subtitle = intent.getStringExtra(EXTRA_SUBTITLE).orEmpty()
                goForeground(build(title, subtitle, -1))
            }

            ACTION_PROGRESS -> {
                val t = intent.getStringExtra(EXTRA_TITLE).orEmpty()
                if (t.isNotEmpty()) title = t
                val percent = intent.getIntExtra(EXTRA_PERCENT, 0)
                if (!running) {
                    goForeground(build(title, subtitle, percent))
                } else {
                    try {
                        NotificationManagerCompat.from(this)
                            .notify(ONGOING_ID, build(title, subtitle, percent))
                    } catch (_: SecurityException) {
                    }
                }
            }

            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        // The queue lives in the app's own state; a service restarted by the
        // system with no intent has nothing to resume on its own.
        return START_NOT_STICKY
    }

    private fun goForeground(notification: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    ONGOING_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(ONGOING_ID, notification)
            }
            running = true
        } catch (_: Throwable) {
            // Without the notification permission the service cannot be
            // foreground; the download still runs while the app is open.
            running = false
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        running = false
    }

    private fun build(title: String, subtitle: String, percent: Int): Notification {
        val b = NotificationCompat.Builder(this, CHANNEL_PROGRESS)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title.ifEmpty { "Downloading" })
            .setContentText(subtitle)
            .setContentIntent(openApp(this))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)

        if (percent in 0..100) {
            b.setProgress(100, percent, false)
            b.setSubText("$percent%")
        } else {
            b.setProgress(0, 0, true)
        }
        return b.build()
    }

    override fun onDestroy() {
        stopForegroundCompat()
        super.onDestroy()
    }
}
