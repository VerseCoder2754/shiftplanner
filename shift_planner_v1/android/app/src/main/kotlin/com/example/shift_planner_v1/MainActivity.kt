package com.example.shift_planner_v1

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Shift Alerts Channel
            val shiftChannel = NotificationChannel(
                "shift_alerts",
                "Shift Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical shift start/end reminders"
                enableVibration(true)
            }

            // General Channel
            val generalChannel = NotificationChannel(
                "general",
                "General Notifications",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "App updates and non-critical info"
            }

            notificationManager.createNotificationChannel(shiftChannel)
            notificationManager.createNotificationChannel(generalChannel)
        }
    }
}
