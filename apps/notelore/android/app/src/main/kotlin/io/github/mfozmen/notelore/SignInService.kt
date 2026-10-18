package io.github.mfozmen.notelore

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * A short foreground service while a sign-in waits in the browser (#409): an app
 * behind the browser is frozen by the system (Samsung within seconds), and a
 * frozen app's loopback server never hears the answer. Held by awake_native.dart
 * through MainActivity's "awake" channel; it stops itself after three minutes.
 */
class SignInService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, getString(R.string.sign_in_channel), NotificationManager.IMPORTANCE_LOW),
            )
        }
        val notification = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        })
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Notelore")
            .setContentText(getString(R.string.sign_in_waiting))
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
        } else {
            startForeground(ID, notification)
        }
        return START_NOT_STICKY
    }

    /** A short service has about three minutes; the sign-in has given up by then. */
    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    companion object {
        private const val CHANNEL = "sign-in"
        private const val ID = 409
    }
}
