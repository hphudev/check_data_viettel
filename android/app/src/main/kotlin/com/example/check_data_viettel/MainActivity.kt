package com.example.check_data_viettel

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ExistingPeriodicWorkPolicy
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.check_data_viettel/autocheck"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAutoCheck" -> {
                    val intervalMinutes = call.argument<Int>("intervalMinutes") ?: 60
                    startAutoCheck(intervalMinutes.toLong())
                    result.success(true)
                }
                "stopAutoCheck" -> {
                    stopAutoCheck()
                    result.success(true)
                }
                "isAutoCheckRunning" -> {
                    val isRunning = isAutoCheckScheduled()
                    result.success(isRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startAutoCheck(intervalMinutes: Long) {
        val workRequest = PeriodicWorkRequestBuilder<AutoCheckWorker>(
            intervalMinutes, TimeUnit.MINUTES
        ).setInitialDelay(intervalMinutes, TimeUnit.MINUTES)
         .addTag(AutoCheckWorker.WORK_NAME)
         .build()

        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            AutoCheckWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
            workRequest
        )
    }

    private fun stopAutoCheck() {
        WorkManager.getInstance(applicationContext)
            .cancelUniqueWork(AutoCheckWorker.WORK_NAME)
    }

    private fun isAutoCheckScheduled(): Boolean {
        val workInfos = WorkManager.getInstance(applicationContext)
            .getWorkInfosForUniqueWork(AutoCheckWorker.WORK_NAME)
            .get()
        return workInfos.any { !it.state.isFinished }
    }
}
