package com.example.check_data_viettel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class ViettelDataWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_REFRESH = "com.example.check_data_viettel.action.REFRESH_WIDGET"
        const val ACTION_WIFI_CLICK = "com.example.check_data_viettel.action.WIFI_CLICK"
        const val ACTION_DATA_CLICK = "com.example.check_data_viettel.action.DATA_CLICK"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == ACTION_WIFI_CLICK || intent.action == ACTION_DATA_CLICK) {
            try {
                if (android.os.Build.VERSION.SDK_INT >= 29) {
                    val panelIntent = Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(panelIntent)
                } else {
                    val targetIntent = if (intent.action == ACTION_WIFI_CLICK) {
                        Intent(Settings.ACTION_WIFI_SETTINGS)
                    } else {
                        Intent(Settings.ACTION_WIRELESS_SETTINGS)
                    }
                    targetIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(targetIntent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // Schedule multiple updates to reflect changed states during user interaction
            val handler = Handler(Looper.getMainLooper())
            val updateRunnable = Runnable { updateWidgetUI(context) }
            for (delay in arrayOf(500L, 1500L, 3000L, 5000L, 8000L, 12000L, 18000L)) {
                handler.postDelayed(updateRunnable, delay)
            }
        } else if (intent.action == "android.net.wifi.WIFI_STATE_CHANGED" ||
                   intent.action == "android.net.conn.CONNECTIVITY_CHANGE" ||
                   intent.action == Intent.ACTION_USER_PRESENT) {
            updateWidgetUI(context)
        } else if (intent.action == ACTION_REFRESH) {
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

    private fun isWifiEnabled(context: Context): Boolean {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        return try {
            val state = wifiManager.wifiState
            state == WifiManager.WIFI_STATE_ENABLED || state == WifiManager.WIFI_STATE_ENABLING
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun isMobileDataEnabled(context: Context): Boolean {
        val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                return telephonyManager.isDataEnabled
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        // Fallback using Settings.Global
        return try {
            Settings.Global.getInt(context.contentResolver, "mobile_data", 0) == 1
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun updateWidgetUI(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val isChecking = prefs.getBoolean("isChecking", false)

        val isWifiOn = isWifiEnabled(context)
        val isDataOn = isMobileDataEnabled(context)

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
                if (isChecking) {
                    setTextViewText(R.id.widget_remaining_value, "---")
                    setTextViewText(R.id.widget_remaining_unit, "")
                    setTextColor(R.id.widget_remaining_value, Color.parseColor("#475569"))
                } else {
                    setTextViewText(R.id.widget_remaining_value, value)
                    setTextViewText(R.id.widget_remaining_unit, unit)
                    setTextColor(R.id.widget_remaining_value, Color.parseColor("#F8FAFC"))
                }

                // Setup Active / Inactive states for WiFi and 4G Buttons
                setInt(
                    R.id.widget_wifi_button,
                    "setBackgroundResource",
                    if (isWifiOn) R.drawable.widget_button_background_active else R.drawable.widget_button_background
                )
                setInt(
                    R.id.widget_wifi_button,
                    "setColorFilter",
                    if (isWifiOn) Color.WHITE else Color.parseColor("#CBD5E1")
                )

                setInt(
                    R.id.widget_data_button,
                    "setBackgroundResource",
                    if (isDataOn) R.drawable.widget_button_background_active else R.drawable.widget_button_background
                )
                setInt(
                    R.id.widget_data_button,
                    "setColorFilter",
                    if (isDataOn) Color.WHITE else Color.parseColor("#CBD5E1")
                )

                // Setup click on WiFi and 4G buttons to trigger Broadcast intents
                val wifiIntent = Intent(context, ViettelDataWidgetProvider::class.java).apply {
                    action = ACTION_WIFI_CLICK
                }
                val pendingWifi = PendingIntent.getBroadcast(
                    context,
                    1,
                    wifiIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or if (android.os.Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
                )

                val dataIntent = Intent(context, ViettelDataWidgetProvider::class.java).apply {
                    action = ACTION_DATA_CLICK
                }
                val pendingData = PendingIntent.getBroadcast(
                    context,
                    2,
                    dataIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or if (android.os.Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
                )

                setOnClickPendingIntent(R.id.widget_wifi_button, pendingWifi)
                setOnClickPendingIntent(R.id.widget_data_button, pendingData)

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
