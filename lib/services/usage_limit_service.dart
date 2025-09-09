import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/logger.dart';

class UsageLimitService extends ChangeNotifier {
  static const int FREE_DAILY_LIMIT = 10;
  static const int PRO_DAILY_LIMIT = 30;
  static const String REPLAY_COUNT_KEY = 'replay_count';
  static const String LAST_RESET_KEY = 'last_reset_date';
  static const String IS_PRO_KEY = 'is_pro_user';
  
  late SharedPreferences _prefs;
  int _todayReplayCount = 0;
  bool _isPro = false;
  DateTime? _lastResetDate;
  
  int get todayReplayCount => _todayReplayCount;
  bool get isPro => _isPro;
  int get dailyLimit => _isPro ? PRO_DAILY_LIMIT : FREE_DAILY_LIMIT;
  int get remainingReplays => dailyLimit - _todayReplayCount;
  bool get canUseReplay => _todayReplayCount < dailyLimit;
  
  // 사용률 퍼센트
  double get usagePercent => (_todayReplayCount / dailyLimit) * 100;
  
  // Singleton
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  UsageLimitService._internal();
  
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadData();
      await _checkAndResetDaily();
      AppLogger.info('Usage limit service initialized');
    } catch (e) {
      AppLogger.error('Failed to initialize usage limit service', e);
    }
  }
  
  Future<void> _loadData() async {
    _todayReplayCount = _prefs.getInt(REPLAY_COUNT_KEY) ?? 0;
    _isPro = _prefs.getBool(IS_PRO_KEY) ?? false;
    
    final lastResetString = _prefs.getString(LAST_RESET_KEY);
    if (lastResetString != null) {
      _lastResetDate = DateTime.parse(lastResetString);
    }
    
    AppLogger.debug('Loaded usage data - Count: $_todayReplayCount, Pro: $_isPro');
  }
  
  Future<void> _checkAndResetDaily() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_lastResetDate == null || _lastResetDate!.isBefore(today)) {
      // 새로운 날이므로 카운트 리셋
      await _resetDailyCount();
      _lastResetDate = today;
      await _prefs.setString(LAST_RESET_KEY, today.toIso8601String());
      AppLogger.info('Daily replay count reset');
    }
  }
  
  Future<void> _resetDailyCount() async {
    _todayReplayCount = 0;
    await _prefs.setInt(REPLAY_COUNT_KEY, 0);
    notifyListeners();
  }
  
  // Upgrade Replay 사용
  Future<bool> useReplay() async {
    await _checkAndResetDaily(); // 날짜 체크
    
    if (!canUseReplay) {
      AppLogger.warning('Replay limit reached - Count: $_todayReplayCount/$dailyLimit');
      return false;
    }
    
    _todayReplayCount++;
    await _prefs.setInt(REPLAY_COUNT_KEY, _todayReplayCount);
    notifyListeners();
    
    AppLogger.info('Replay used - Count: $_todayReplayCount/$dailyLimit');
    return true;
  }
  
  // Pro 구독 설정
  Future<void> setProStatus(bool isPro) async {
    _isPro = isPro;
    await _prefs.setBool(IS_PRO_KEY, isPro);
    notifyListeners();
    
    AppLogger.info('Pro status updated: $isPro');
  }
  
  // 사용 통계
  Map<String, dynamic> getUsageStats() {
    return {
      'todayUsed': _todayReplayCount,
      'dailyLimit': dailyLimit,
      'remaining': remainingReplays,
      'usagePercent': usagePercent,
      'isPro': _isPro,
      'lastReset': _lastResetDate?.toIso8601String(),
    };
  }
  
  // 개발용: 카운트 리셋
  Future<void> debugResetCount() async {
    if (kDebugMode) {
      await _resetDailyCount();
      AppLogger.debug('Debug: Count reset');
    }
  }
  
  // 개발용: 카운트 설정
  Future<void> debugSetCount(int count) async {
    if (kDebugMode) {
      _todayReplayCount = count;
      await _prefs.setInt(REPLAY_COUNT_KEY, count);
      notifyListeners();
      AppLogger.debug('Debug: Count set to $count');
    }
  }
}