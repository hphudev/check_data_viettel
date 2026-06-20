package com.example.check_data_viettel

import android.content.Context
import android.telephony.SmsManager
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

class AutoCheckWorker(
    context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {

    companion object {
        const val TAG = "AutoCheckWorker"
        const val WORK_NAME = "auto_check_viettel"
    }

    override fun doWork(): Result {
        return try {
            Log.d(TAG, "AutoCheckWorker triggered - sending KTTK to 191")

            // 1. Set checking state
            val prefs = applicationContext.getSharedPreferences(
                "HomeWidgetPreferences", Context.MODE_PRIVATE
            )
            prefs.edit().putBoolean("isChecking", true).apply()

            // 2. Send SMS "KTTK" to 191
            val smsManager = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                applicationContext.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            smsManager.sendTextMessage("191", null, "KTTK", null, null)

            Log.d(TAG, "SMS KTTK sent successfully")

            // 3. Set a timeout to reset isChecking after 30 seconds
            //    (ViettelSmsReceiver will set it to false when response arrives)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                val currentPrefs = applicationContext.getSharedPreferences(
                    "HomeWidgetPreferences", Context.MODE_PRIVATE
                )
                if (currentPrefs.getBoolean("isChecking", false)) {
                    currentPrefs.edit().putBoolean("isChecking", false).apply()
                    Log.d(TAG, "Timeout: reset isChecking to false")
                }
            }, 30000)

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "AutoCheckWorker failed: ${e.message}", e)

            // Reset checking state on failure
            val prefs = applicationContext.getSharedPreferences(
                "HomeWidgetPreferences", Context.MODE_PRIVATE
            )
            prefs.edit().putBoolean("isChecking", false).apply()

            Result.failure()
        }
    }
}
