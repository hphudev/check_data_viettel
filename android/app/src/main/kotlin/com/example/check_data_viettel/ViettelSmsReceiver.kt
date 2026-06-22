package com.example.check_data_viettel

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.telephony.SmsMessage
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ViettelSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "android.provider.Telephony.SMS_RECEIVED") {
            val bundle = intent.extras ?: return
            val pdus = bundle.get("pdus") as? Array<*> ?: return
            val format = bundle.getString("format")
            
            var fullBody = ""
            for (pdu in pdus) {
                val message = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    SmsMessage.createFromPdu(pdu as ByteArray, format)
                } else {
                    @Suppress("DEPRECATION")
                    SmsMessage.createFromPdu(pdu as ByteArray)
                }
                
                val sender = message.originatingAddress ?: ""
                if (sender == "191" || sender.contains("191")) {
                    fullBody += message.messageBody ?: ""
                }
            }
            if (fullBody.isNotEmpty() && fullBody.contains("luu luong", ignoreCase = true)) {
                parseAndSaveSms(context, fullBody)
            }
        }
    }

    private fun parseAndSaveSms(context: Context, body: String) {
        var packageName = "Không rõ"
        var data = "0 MB"
        var expiry = "N/A"

        // 1. Parse Remaining Data (take the first match)
        val dataRegex = Regex("""(\d+(?:\.\d+)?\s*(?:GB|MB|KB))""", RegexOption.IGNORE_CASE)
        val dataMatch = dataRegex.find(body)
        if (dataMatch != null) {
            data = dataMatch.groupValues[1]

            // 2. Parse Package Name
            // Check if there is a package name inside parentheses right after the first data
            // e.g. "589MB (ST60N)" -> ST60N
            val dataEnd = dataMatch.range.last + 1
            val afterData = body.substring(dataEnd, (dataEnd + 30).coerceAtMost(body.length))
            val parenPackageRegex = Regex("""^\s*\(([^)]+)\)""")
            val parenMatch = parenPackageRegex.find(afterData)
            if (parenMatch != null) {
                packageName = parenMatch.groupValues[1]
            }
        }

        // Fallback package parsing (for older SMS formats where package name is before data)
        if (packageName == "Không rõ") {
            val packageRegex = Regex("""(?:goi\s+cuoc\s+|goi\s+|\(goi\s+)([A-Z0-9]+)""", RegexOption.IGNORE_CASE)
            val packageRegexFallback = Regex("""\b([A-Z]+[0-9]+[A-Z]*)\b""")

            val packageMatch = packageRegex.find(body)
            if (packageMatch != null) {
                packageName = packageMatch.groupValues[1]
            } else {
                val fallbackMatches = packageRegexFallback.findAll(body)
                for (m in fallbackMatches) {
                    val candidate = m.groupValues[1]
                    if (candidate != "MB" && candidate != "GB" && candidate != "KB" && candidate != "KTTK") {
                        packageName = candidate
                        break
                    }
                }
            }
        }

        // 3. Parse Expiry Date (supporting dd/mm/yyyy and dd-mm-yyyy, plus 24h/00h00 times)
        val expiryRegex = Regex("""(?:su\s+dung\s+den\s+|den\s+)?((?:\d{2}h\d{2}|24h)?\s*(?:ngay\s+)?\d{2}[-/]\d{2}[-/]\d{4})""", RegexOption.IGNORE_CASE)
        val expiryMatch = expiryRegex.find(body)
        if (expiryMatch != null) {
            expiry = expiryMatch.groupValues[1]
        } else {
            val dateRegex = Regex("""\d{2}[-/]\d{2}[-/]\d{4}""")
            val dateMatch = dateRegex.find(body)
            if (dateMatch != null) {
                expiry = dateMatch.value
            }
        }

        val sdf = SimpleDateFormat("HH:mm - dd/MM", Locale.getDefault())
        val timeString = sdf.format(Date())

        // Save to Shared Preferences (HomeWidgetPreferences)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putString("packageName", packageName.uppercase())
            putString("remainingData", data)
            putString("expiryDate", expiry)
            putString("lastChecked", timeString)
            putString("rawSms", body)
            putBoolean("isChecking", false) // Finished checking!
            apply()
        }

        // Trigger Widget Update
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, ViettelDataWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        
        val widgetIntent = Intent(context, ViettelDataWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
        }
        context.sendBroadcast(widgetIntent)
    }
}
