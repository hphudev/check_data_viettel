package com.example.check_data_viettel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ViettelDataWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_REFRESH = "com.example.check_data_viettel.action.REFRESH_WIDGET"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == ACTION_REFRESH) {
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val isChecking = prefs.getBoolean("isChecking", false)
            if (isChecking) return // Already checking

            // 1. Set checking state to true and update widget UI to loading
            prefs.edit().putBoolean("isChecking", true).apply()
            updateWidgetUI(context)

            // 2. Send SMS to 191
            try {
                val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    context.getSystemService(SmsManager::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
                smsManager.sendTextMessage("191", null, "KTTK", null, null)
            } catch (e: Exception) {
                e.printStackTrace()
                // If fail, revert loading state
                prefs.edit().putBoolean("isChecking", false).apply()
                updateWidgetUI(context)
                return
            }

            // 3. Set a timeout of 20 seconds to reset the loading state if no SMS is received
            Handler(Looper.getMainLooper()).postDelayed({
                val currentPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                if (currentPrefs.getBoolean("isChecking", false)) {
                    currentPrefs.edit().putBoolean("isChecking", false).apply()
                    updateWidgetUI(context)
                }
            }, 20000)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        updateWidgetUI(context, appWidgetManager, appWidgetIds)
    }

    private fun updateWidgetUI(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, ViettelDataWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        updateWidgetUI(context, appWidgetManager, appWidgetIds)
    }

    private fun updateWidgetUI(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val isChecking = prefs.getBoolean("isChecking", false)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.viettel_data_widget).apply {
                if (isChecking) {
                    // Show Dim overlay and Progress Bar
                    setViewVisibility(R.id.widget_dim_overlay, View.VISIBLE)
                    setViewVisibility(R.id.widget_loading_progress, View.VISIBLE)
                } else {
                    // Hide Dim overlay and Progress Bar
                    setViewVisibility(R.id.widget_dim_overlay, View.GONE)
                    setViewVisibility(R.id.widget_loading_progress, View.GONE)
                }

                // Retrieve and bind data
                val packageName = prefs.getString("packageName", "N/A") ?: "N/A"
                val remainingData = prefs.getString("remainingData", "0 MB") ?: "0 MB"

                // Parse remainingData into value and unit
                val regex = Regex("""^(\d+(?:\.\d+)?)\s*([a-zA-Z]+)$""")
                val match = regex.find(remainingData.trim())
                var value = remainingData
                var unit = ""
                if (match != null) {
                    value = match.groupValues[1]
                    unit = match.groupValues[2].uppercase()
                }

                // Bind views
                setTextViewText(R.id.widget_package_name, packageName)
                setTextViewText(R.id.widget_remaining_value, value)
                setTextViewText(R.id.widget_remaining_unit, unit)

                // Setup click on refresh button to send REFRESH broadcast
                val refreshIntent = Intent(context, ViettelDataWidgetProvider::class.java).apply {
                    action = ACTION_REFRESH
                }
                val pendingRefresh = PendingIntent.getBroadcast(
                    context,
                    0,
                    refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or if (android.os.Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
                )
                setOnClickPendingIntent(R.id.widget_refresh_button, pendingRefresh)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
