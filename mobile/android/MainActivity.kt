package dev.rimbakawal.rimbakawal

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createRondaanReminderChannel()
    }

    private fun createRondaanReminderChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val soundUri = Uri.parse(
            "${ContentResolver.SCHEME_ANDROID_RESOURCE}://$packageName/${R.raw.rondaan_reminder}"
        )
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
            .build()
        val channel = NotificationChannel(
            "rondaan_reminder_v1",
            "Peringatan Rondaan",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Peringatan sesi rondaan dan rondaan yang belum selesai"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 700, 350, 700, 350, 700)
            setSound(soundUri, attributes)
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }
}
