import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    runApp(const ViettelDataApp());
  }, (error, stackTrace) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack trace: $stackTrace');
  });
}

class ViettelDataApp extends StatelessWidget {
  const ViettelDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Viettel 4G Checker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6246EA),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DataCheckerScreen(),
    );
  }
}

class DataCheckerScreen extends StatefulWidget {
  const DataCheckerScreen({super.key});

  @override
  State<DataCheckerScreen> createState() => _DataCheckerScreenState();
}

class _DataCheckerScreenState extends State<DataCheckerScreen>
    with SingleTickerProviderStateMixin {
  final Telephony telephony = Telephony.instance;
  late AnimationController _pulseController;
  
  static const _autoCheckChannel = MethodChannel('com.example.check_data_viettel/autocheck');
  
  // App state
  bool _hasPermissions = false;
  bool _isChecking = false;
  String _statusText = "Đang khởi tạo...";
  
  // Auto-check settings
  bool _autoCheckEnabled = false;
  int _autoCheckInterval = 60; // default 60 minutes
  
  // Parsed SMS data
  String _packageName = "N/A";
  String _remainingData = "0 MB";
  String _expiryDate = "N/A";
  String _rawSms = "";
  String _lastCheckedTime = "Chưa kiểm tra";
  
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    _loadCachedData();
    _checkPermissionsAndStart();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  // Load cached data from SharedPreferences & Home Widget
  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get values from HomeWidget (which is updated by background receiver)
      final widgetPackage = await HomeWidget.getWidgetData<String>('packageName');
      final widgetData = await HomeWidget.getWidgetData<String>('remainingData');
      final widgetExpiry = await HomeWidget.getWidgetData<String>('expiryDate');
      final widgetTime = await HomeWidget.getWidgetData<String>('lastChecked');
      final widgetRaw = await HomeWidget.getWidgetData<String>('rawSms');
      final widgetIsChecking = await HomeWidget.getWidgetData<bool>('isChecking') ?? false;

      if (!mounted) return;
      setState(() {
        _packageName = widgetPackage ?? prefs.getString('cached_package') ?? "N/A";
        _remainingData = widgetData ?? prefs.getString('cached_data') ?? "0 MB";
        _expiryDate = widgetExpiry ?? prefs.getString('cached_expiry') ?? "N/A";
        _rawSms = widgetRaw ?? prefs.getString('cached_raw') ?? "";
        _lastCheckedTime = widgetTime ?? prefs.getString('cached_time') ?? "Chưa kiểm tra";
        
        if (widgetIsChecking) {
          _isChecking = true;
          _statusText = "Đang kiểm tra ở chế độ nền...";
          _pulseController.repeat(reverse: true);
          
          telephony.listenIncomingSms(
            onNewMessage: (SmsMessage message) {
              final address = message.address ?? "";
              if (address == "191" || address.contains("191")) {
                _handleIncomingSms(message.body ?? "");
              }
            },
            listenInBackground: false,
          );
          
          _timeoutTimer?.cancel();
          _timeoutTimer = Timer(const Duration(seconds: 30), () {
            if (_isChecking && mounted) {
              setState(() {
                _isChecking = false;
                _statusText = "Không nhận được phản hồi từ 191.";
                _pulseController.stop();
              });
            }
          });
        }
      });

      // Also load auto-check settings
      await _loadAutoCheckSettings();

      // Sync/Cache values to ensure they exist on both sides
      _updateHomeWidget(_packageName, _remainingData, _expiryDate, _lastCheckedTime, _rawSms);
    } catch (e) {
      debugPrint('Lỗi loadCachedData: $e');
    }
  }

  // Load auto-check configuration from SharedPreferences & WorkManager
  Future<void> _loadAutoCheckSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final interval = prefs.getInt('auto_check_interval') ?? 60;

      bool isRunning = false;
      try {
        isRunning = await _autoCheckChannel.invokeMethod<bool>('isAutoCheckRunning') ?? false;
      } catch (e) {
        debugPrint("Error checking WorkManager status: $e");
      }

      setState(() {
        _autoCheckEnabled = isRunning;
        _autoCheckInterval = interval;
      });
    } catch (e) {
      debugPrint("Error loading auto check settings: $e");
    }
  }

  // Toggle Auto Check ON/OFF
  Future<void> _toggleAutoCheck(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_check_enabled', enabled);

    try {
      if (enabled) {
        await _autoCheckChannel.invokeMethod('startAutoCheck', {
          'intervalMinutes': _autoCheckInterval,
        });
      } else {
        await _autoCheckChannel.invokeMethod('stopAutoCheck');
      }
      setState(() {
        _autoCheckEnabled = enabled;
      });
    } catch (e) {
      debugPrint("Error toggling auto-check: $e");
      setState(() {
        _autoCheckEnabled = !enabled;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi thiết lập kiểm tra tự động: $e")),
        );
      }
    }
  }

  // Change Auto Check Repeat Interval
  Future<void> _changeAutoCheckInterval(int interval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_check_interval', interval);
    setState(() {
      _autoCheckInterval = interval;
    });

    if (_autoCheckEnabled) {
      try {
        await _autoCheckChannel.invokeMethod('startAutoCheck', {
          'intervalMinutes': interval,
        });
      } catch (e) {
        debugPrint("Error updating interval: $e");
      }
    }
  }

  // Save parsed data to SharedPreferences
  Future<void> _cacheData(
      String package, String data, String expiry, String raw, String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_package', package);
    await prefs.setString('cached_data', data);
    await prefs.setString('cached_expiry', expiry);
    await prefs.setString('cached_raw', raw);
    await prefs.setString('cached_time', time);

    // Sync to Home Widget
    _updateHomeWidget(package, data, expiry, time, raw);
  }

  // Update data to Android Home Widget
  Future<void> _updateHomeWidget(
      String package, String data, String expiry, String time, String raw) async {
    try {
      await HomeWidget.saveWidgetData<String>('packageName', package);
      await HomeWidget.saveWidgetData<String>('remainingData', data);
      await HomeWidget.saveWidgetData<String>('expiryDate', expiry);
      await HomeWidget.saveWidgetData<String>('lastChecked', time);
      await HomeWidget.saveWidgetData<String>('rawSms', raw);
      await HomeWidget.updateWidget(
        name: 'ViettelDataWidgetProvider',
        androidName: 'ViettelDataWidgetProvider',
      );
    } catch (e) {
      debugPrint("Lỗi cập nhật Widget: $e");
    }
  }

  // Check permissions on start
  Future<void> _checkPermissionsAndStart() async {
    try {
      if (!mounted) return;
      setState(() {
        _statusText = "Kiểm tra quyền truy cập...";
      });

      final smsStatus = await Permission.sms.status;
      
      if (!mounted) return;
      if (smsStatus.isGranted) {
        setState(() {
          _hasPermissions = true;
        });
        _startDataCheck();
      } else {
        setState(() {
          _hasPermissions = false;
          _statusText = "Yêu cầu cấp quyền SMS";
        });
        // Prompt user to grant permissions
        _requestSmsPermissions();
      }
    } catch (e) {
      debugPrint('Lỗi checkPermissions: $e');
      if (!mounted) return;
      setState(() {
        _statusText = "Lỗi kiểm tra quyền: $e";
      });
    }
  }

  // Request SMS permissions
  Future<void> _requestSmsPermissions() async {
    try {
      final status = await Permission.sms.request();
      if (!mounted) return;
      if (status.isGranted) {
        setState(() {
          _hasPermissions = true;
        });
        _startDataCheck();
      } else {
        setState(() {
          _hasPermissions = false;
          _statusText = "Ứng dụng cần quyền SMS để hoạt động. Vui lòng cấp quyền trong cài đặt.";
        });
      }
    } catch (e) {
      debugPrint('Lỗi requestPermissions: $e');
    }
  }

  // Start checking data: register listener and send SMS
  Future<void> _startDataCheck() async {
    if (_isChecking) return;

    try {
      if (!mounted) return;
      setState(() {
        _isChecking = true;
        _statusText = "Đang gửi yêu cầu KTTK đến 191...";
        _pulseController.repeat(reverse: true);
      });

      // 1. Listen to incoming SMS messages in foreground
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          final address = message.address ?? "";
          if (address == "191" || address.contains("191")) {
            _handleIncomingSms(message.body ?? "");
          }
        },
        listenInBackground: false,
      );

      // 2. Set timeout (30 seconds) in case of no response
      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_isChecking && mounted) {
          setState(() {
            _isChecking = false;
            _statusText = "Quá thời gian đợi phản hồi từ 191. Hãy thử lại.";
            _pulseController.stop();
          });
        }
      });

      // 3. Send KTTK SMS to 191
      await telephony.sendSms(
        to: "191",
        message: "KTTK",
      );
      if (!mounted) return;
      setState(() {
        _statusText = "Đang đợi phản hồi từ 191...";
      });
    } catch (e) {
      debugPrint('Lỗi startDataCheck: $e');
      _timeoutTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _statusText = "Lỗi khi gửi tin nhắn: $e";
        _pulseController.stop();
      });
    }
  }

  // Parse Viettel's SMS response
  void _handleIncomingSms(String body) {
    // Only process if the message contains "luu luong" (case-insensitive)
    if (!body.toLowerCase().contains("luu luong")) {
      return;
    }

    _timeoutTimer?.cancel();
    _pulseController.stop();

    String package = "Không rõ";
    String data = "0 MB";
    String expiry = "N/A";

    // 1. Parse Remaining Data (take the first match)
    final RegExp dataRegex = RegExp(
      r'(\d+(?:\.\d+)?\s*(?:GB|MB|KB))',
      caseSensitive: false,
    );
    final dataMatch = dataRegex.firstMatch(body);
    if (dataMatch != null) {
      data = dataMatch.group(1) ?? "0 MB";

      // 2. Parse Package Name
      // Check if there is a package name inside parentheses right after the first data
      // e.g. "589MB (ST60N)" -> ST60N
      final int dataEnd = dataMatch.end;
      final String afterData = body.substring(dataEnd, (dataEnd + 30).clamp(0, body.length));
      final RegExp parenPackageRegex = RegExp(r'^\s*\(([^)]+)\)');
      final parenMatch = parenPackageRegex.firstMatch(afterData);
      if (parenMatch != null) {
        package = parenMatch.group(1) ?? "Không rõ";
      }
    }

    // Fallback package parsing (for older SMS formats where package name is before data)
    if (package == "Không rõ") {
      final RegExp packageRegex = RegExp(
        r'(?:goi\s+cuoc\s+|goi\s+|\(goi\s+)([A-Z0-9]+)',
        caseSensitive: false,
      );
      final RegExp packageRegexFallback = RegExp(
        r'\b([A-Z]+[0-9]+[A-Z]*)\b',
      );

      var packageMatch = packageRegex.firstMatch(body);
      if (packageMatch != null) {
        package = packageMatch.group(1) ?? "Không rõ";
      } else {
        var fallbackMatches = packageRegexFallback.allMatches(body);
        for (var m in fallbackMatches) {
          String candidate = m.group(1) ?? "";
          if (candidate != "MB" && candidate != "GB" && candidate != "KB" && candidate != "KTTK") {
            package = candidate;
            break;
          }
        }
      }
    }

    // 3. Parse Expiry Date (supporting dd/mm/yyyy and dd-mm-yyyy, plus 24h/00h00 times)
    final RegExp expiryRegex = RegExp(
      r'(?:su\s+dung\s+den\s+|den\s+)?((?:\d{2}h\d{2}|24h)?\s*(?:ngay\s+)?\d{2}[-/]\d{2}[-/]\d{4})',
      caseSensitive: false,
    );
    var expiryMatch = expiryRegex.firstMatch(body);
    if (expiryMatch != null) {
      expiry = expiryMatch.group(1) ?? "N/A";
    } else {
      final RegExp dateRegex = RegExp(r'\d{2}[-/]\d{2}[-/]\d{4}');
      var dateMatch = dateRegex.firstMatch(body);
      if (dateMatch != null) {
        expiry = dateMatch.group(0) ?? "N/A";
      }
    }

    final now = DateTime.now();
    final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} - ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";

    setState(() {
      _isChecking = false;
      _packageName = package.toUpperCase();
      _remainingData = data;
      _expiryDate = expiry;
      _rawSms = body;
      _lastCheckedTime = timeString;
      _statusText = "Kiểm tra thành công!";
    });

    _cacheData(_packageName, _remainingData, _expiryDate, _rawSms, _lastCheckedTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0E17),
              Color(0xFF1E1B2E),
              Color(0xFF131124),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(
                        Icons.network_check_rounded,
                        color: Colors.redAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Viettel 4G",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          "Kiểm Tra Dung Lượng",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Core Data Display Card
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatusIndicator(),
                        const SizedBox(height: 32),
                        _buildDataCard(),
                        const SizedBox(height: 24),
                        _buildAutoCheckCard(),
                        if (_rawSms.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildRawSmsCard(),
                        ],
                      ],
                    ),
                  ),
                ),

                // Action/Permission controls at the bottom
                const SizedBox(height: 16),
                if (!_hasPermissions)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6246EA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.security),
                    label: const Text(
                      "Cấp quyền SMS",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _requestSmsPermissions,
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isChecking
                          ? Colors.grey.withValues(alpha: 0.2)
                          : const Color(0xFF6246EA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: _isChecking ? 0 : 4,
                      shadowColor: const Color(0xFF6246EA).withValues(alpha: 0.4),
                    ),
                    icon: _isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(
                      _isChecking ? "Đang kiểm tra..." : "Kiểm tra ngay",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isChecking ? null : _startDataCheck,
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Center(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (_isChecking)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 140 + (30 * _pulseController.value),
                      height: 140 + (30 * _pulseController.value),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF6246EA).withValues(alpha: 0.15 * (1.0 - _pulseController.value)),
                      ),
                    );
                  },
                ),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6246EA), Color(0xFF3F51B5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6246EA).withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    _isChecking ? Icons.hourglass_empty_rounded : Icons.wifi_tethering_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCard() {
    final bool hasData = _remainingData != "0 MB" && _remainingData != "N/A";
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "CHI TIẾT DUNG LƯỢNG",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hasData ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasData ? "Hoạt động" : "Không khả dụng",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: hasData ? const Color(0xFF10B981) : Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Remaining Data Big Display
          const Text(
            "Dung lượng còn lại",
            style: TextStyle(fontSize: 14, color: Colors.white60),
          ),
          const SizedBox(height: 4),
          _buildRemainingDataWidget(),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          
          // Package details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Gói cước", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  SizedBox(height: 4),
                  Icon(Icons.layers_rounded, color: Colors.white38, size: 18),
                ],
              ),
              Text(
                _packageName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Expiry details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Hạn sử dụng", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  SizedBox(height: 4),
                  Icon(Icons.event_note_rounded, color: Colors.white38, size: 18),
                ],
              ),
              Text(
                _expiryDate,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Last Checked Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Cập nhật cuối", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  SizedBox(height: 4),
                  Icon(Icons.access_time_filled_rounded, color: Colors.white38, size: 18),
                ],
              ),
              Text(
                _lastCheckedTime,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRemainingDataWidget() {
    final RegExp regex = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-zA-Z]+)$');
    final match = regex.firstMatch(_remainingData.trim());

    String value = _remainingData;
    String unit = "";

    if (match != null) {
      value = match.group(1) ?? _remainingData;
      unit = match.group(2) ?? "";
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
          ).createShader(bounds),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 54,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        if (unit.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            unit.toUpperCase(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRawSmsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TIN NHẮN GỐC TỪ 191",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _rawSms,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white54,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoCheckCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6246EA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.update_rounded,
                      color: Color(0xFF00F2FE),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "TỰ ĐỘNG CẬP NHẬT",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _autoCheckEnabled ? "Đang bật" : "Đã tắt",
                        style: TextStyle(
                          fontSize: 11,
                          color: _autoCheckEnabled ? const Color(0xFF10B981) : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch.adaptive(
                value: _autoCheckEnabled,
                activeThumbColor: const Color(0xFF00F2FE),
                activeTrackColor: const Color(0xFF6246EA).withValues(alpha: 0.5),
                onChanged: (bool value) {
                  _toggleAutoCheck(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Chu kỳ kiểm tra",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
              Opacity(
                opacity: _autoCheckEnabled ? 1.0 : 0.5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _autoCheckInterval,
                      dropdownColor: const Color(0xFF1E1B2E),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF00F2FE),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      onChanged: _autoCheckEnabled
                          ? (int? newValue) {
                              if (newValue != null) {
                                _changeAutoCheckInterval(newValue);
                              }
                            }
                          : null,
                      items: [15, 30, 60, 120].map<DropdownMenuItem<int>>((int value) {
                        return DropdownMenuItem<int>(
                          value: value,
                          child: Text("$value phút"),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_autoCheckEnabled) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.amberAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Lưu ý chạy ngầm",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amberAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Một số dòng máy có thể dừng kiểm tra tự động do tối ưu pin của Android. Bạn có thể tắt tối ưu pin cho app trong cài đặt hệ thống.",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white60,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => openAppSettings(),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Mở Cài đặt ứng dụng ",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00F2FE),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 12,
                                color: Color(0xFF00F2FE),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
