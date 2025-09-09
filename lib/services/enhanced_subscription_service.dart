import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../core/logger.dart';

/// Enhanced Subscription Service without RevenueCat
/// Uses local storage for MVP - can add RevenueCat later when needed
enum SubscriptionTier {
  free,
  pro,
  premium
}

class EnhancedSubscriptionService extends ChangeNotifier {
  // Daily limits for each tier
  static const Map<SubscriptionTier, int> DAILY_LIMITS = {
    SubscriptionTier.free: 10,
    SubscriptionTier.pro: 30,
    SubscriptionTier.premium: 100,
  };
  
  // Pricing (for display purposes)
  static const Map<String, String> PRICING = {
    'pro_monthly': '\$9.99',
    'pro_yearly': '\$99.99',
    'premium_monthly': '\$19.99',
  };
  
  // State
  SubscriptionTier _currentTier = SubscriptionTier.free;
  int _todayUsageCount = 0;
  DateTime? _lastResetDate;
  bool _isInitialized = false;
  
  // Trial management
  DateTime? _trialStartDate;
  static const int TRIAL_DAYS = 7;
  
  // Usage statistics
  final Map<String, int> _weeklyUsage = {};
  final Map<String, int> _monthlyUsage = {};
  
  // Getters
  SubscriptionTier get currentTier => _currentTier;
  int get todayUsageCount => _todayUsageCount;
  int get dailyLimit => DAILY_LIMITS[_currentTier]!;
  int get remainingReplays => dailyLimit - _todayUsageCount;
  bool get canUseReplay => _todayUsageCount < dailyLimit;
  bool get isPro => _currentTier != SubscriptionTier.free;
  bool get isPremium => _currentTier == SubscriptionTier.premium;
  bool get isSubscribed => _currentTier != SubscriptionTier.free;
  
  // Constructor
  EnhancedSubscriptionService() {
    _loadFromLocalStorage();
  }
  
  /// Initialize service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadFromLocalStorage();
      await _checkAndResetDailyUsage();
      _startDailyResetTimer();
      _isInitialized = true;
      
      AppLogger.info('✅ Subscription service initialized (Local implementation)');
    } catch (e) {
      AppLogger.error('Failed to initialize subscription service', e);
    }
  }
  
  /// Load subscription data from local storage
  Future<void> _loadFromLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load subscription tier
    final tierString = prefs.getString('subscription_tier') ?? 'free';
    _currentTier = SubscriptionTier.values.firstWhere(
      (t) => t.name == tierString,
      orElse: () => SubscriptionTier.free,
    );
    
    // Load usage data
    _todayUsageCount = prefs.getInt('today_usage_count') ?? 0;
    final lastResetString = prefs.getString('last_reset_date');
    if (lastResetString != null) {
      _lastResetDate = DateTime.parse(lastResetString);
    }
    
    // Load trial data
    final trialStartString = prefs.getString('trial_start_date');
    if (trialStartString != null) {
      _trialStartDate = DateTime.parse(trialStartString);
      _checkTrialExpiry();
    }
    
    // Load statistics
    await _loadUsageStatistics();
    
    notifyListeners();
  }
  
  /// Save subscription data to local storage
  Future<void> _saveToLocalStorage() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString('subscription_tier', _currentTier.name);
    await prefs.setInt('today_usage_count', _todayUsageCount);
    
    if (_lastResetDate != null) {
      await prefs.setString('last_reset_date', _lastResetDate!.toIso8601String());
    }
    
    if (_trialStartDate != null) {
      await prefs.setString('trial_start_date', _trialStartDate!.toIso8601String());
    }
  }
  
  /// Check and reset daily usage if needed
  Future<void> _checkAndResetDailyUsage() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_lastResetDate == null || !_isSameDay(_lastResetDate!, today)) {
      // Save yesterday's usage to statistics
      if (_lastResetDate != null) {
        await _saveUsageStatistics(_todayUsageCount);
      }
      
      // Reset for new day
      _todayUsageCount = 0;
      _lastResetDate = today;
      await _saveToLocalStorage();
      
      AppLogger.info('📅 Daily usage reset completed');
      notifyListeners();
    }
  }
  
  /// Start daily reset timer
  void _startDailyResetTimer() {
    // Calculate time until midnight
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);
    
    // Set timer for midnight
    Timer(timeUntilMidnight, () {
      _checkAndResetDailyUsage();
      _startDailyResetTimer(); // Reschedule for next day
    });
    
    AppLogger.info('⏰ Daily reset timer scheduled for midnight');
  }
  
  /// Increment usage count
  Future<bool> incrementUsage(String feature) async {
    if (!canUseReplay) {
      AppLogger.warning('Usage limit reached for today');
      return false;
    }
    
    _todayUsageCount++;
    await _saveToLocalStorage();
    notifyListeners();
    
    AppLogger.info('📊 Usage incremented: $_todayUsageCount/$dailyLimit');
    return true;
  }
  
  /// Start free trial
  Future<void> startFreeTrial() async {
    if (_trialStartDate != null) {
      AppLogger.warning('Trial already started');
      return;
    }
    
    _trialStartDate = DateTime.now();
    _currentTier = SubscriptionTier.pro;
    await _saveToLocalStorage();
    notifyListeners();
    
    AppLogger.success('🎉 Free trial started for $TRIAL_DAYS days');
  }
  
  /// Check trial expiry
  void _checkTrialExpiry() {
    if (_trialStartDate == null) return;
    
    final daysSinceTrial = DateTime.now().difference(_trialStartDate!).inDays;
    if (daysSinceTrial >= TRIAL_DAYS && _currentTier == SubscriptionTier.pro) {
      _currentTier = SubscriptionTier.free;
      _saveToLocalStorage();
      notifyListeners();
      
      AppLogger.info('⏱️ Free trial expired');
    }
  }
  
  /// Simulate purchase (for MVP - replace with actual IAP later)
  Future<void> purchaseSubscription(String productId) async {
    // In production, this would handle actual in-app purchase
    // For MVP, we'll simulate the purchase
    
    if (productId.contains('premium')) {
      _currentTier = SubscriptionTier.premium;
    } else if (productId.contains('pro')) {
      _currentTier = SubscriptionTier.pro;
    }
    
    await _saveToLocalStorage();
    notifyListeners();
    
    AppLogger.success('✅ Subscription activated: ${_currentTier.name}');
  }
  
  /// Cancel subscription
  Future<void> cancelSubscription() async {
    _currentTier = SubscriptionTier.free;
    await _saveToLocalStorage();
    notifyListeners();
    
    AppLogger.info('❌ Subscription cancelled');
  }
  
  /// Restore purchases (for MVP - just reload from storage)
  Future<void> restorePurchases() async {
    await _loadFromLocalStorage();
    AppLogger.info('🔄 Purchases restored');
  }
  
  /// Get usage statistics
  Future<Map<String, dynamic>> getUsageStatistics() async {
    await _loadUsageStatistics();
    
    return {
      'today': _todayUsageCount,
      'weekly': _weeklyUsage,
      'monthly': _monthlyUsage,
      'tier': _currentTier.name,
      'limit': dailyLimit,
    };
  }
  
  /// Load usage statistics
  Future<void> _loadUsageStatistics() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load weekly usage
    _weeklyUsage.clear();
    for (int i = 0; i < 7; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = 'usage_${DateFormat('yyyy-MM-dd').format(date)}';
      final usage = prefs.getInt(key) ?? 0;
      if (usage > 0) {
        _weeklyUsage[DateFormat('EEE').format(date)] = usage;
      }
    }
    
    // Load monthly usage
    _monthlyUsage.clear();
    for (int i = 0; i < 30; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = 'usage_${DateFormat('yyyy-MM-dd').format(date)}';
      final usage = prefs.getInt(key) ?? 0;
      if (usage > 0) {
        final week = 'Week ${(i ~/ 7) + 1}';
        _monthlyUsage[week] = (_monthlyUsage[week] ?? 0) + usage;
      }
    }
  }
  
  /// Save usage statistics
  Future<void> _saveUsageStatistics(int usage) async {
    final prefs = await SharedPreferences.getInstance();
    final date = _lastResetDate ?? DateTime.now();
    final key = 'usage_${DateFormat('yyyy-MM-dd').format(date)}';
    await prefs.setInt(key, usage);
  }
  
  /// Check if same day
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
  
  /// Get remaining trial days
  int? getRemainingTrialDays() {
    if (_trialStartDate == null) return null;
    
    final daysSinceTrial = DateTime.now().difference(_trialStartDate!).inDays;
    final remaining = TRIAL_DAYS - daysSinceTrial;
    return remaining > 0 ? remaining : 0;
  }
  
  /// Check if in trial period
  bool get isInTrial {
    if (_trialStartDate == null) return false;
    final remaining = getRemainingTrialDays();
    return remaining != null && remaining > 0;
  }
  
  /// Get subscription status text
  String getSubscriptionStatus() {
    if (isInTrial) {
      return 'Free Trial (${getRemainingTrialDays()} days left)';
    }
    
    switch (_currentTier) {
      case SubscriptionTier.premium:
        return 'Premium Member';
      case SubscriptionTier.pro:
        return 'Pro Member';
      default:
        return 'Free User';
    }
  }
  
  /// Use upgrade replay
  Future<bool> useUpgradeReplay() async {
    return await incrementUsage('upgrade');
  }
  
  /// Get time until daily reset
  String getTimeUntilReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final difference = tomorrow.difference(now);
    
    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '$hours hr ${minutes} min';
    } else {
      return '$minutes min';
    }
  }
  
  @override
  void dispose() {
    _saveToLocalStorage();
    super.dispose();
  }
}