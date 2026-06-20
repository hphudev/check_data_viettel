# Flutter standard keep rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class androidx.lifecycle.** { *; }

# Keep custom widget provider and broadcast receiver classes
-keep class com.example.check_data_viettel.ViettelDataWidgetProvider { *; }
-keep class com.example.check_data_viettel.ViettelSmsReceiver { *; }

# Keep another_telephony plugin classes
-keep class com.shounakmulay.telephony.** { *; }
