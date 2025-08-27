// lib/services/enhanced_subscription_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:intl/intl.dart';

enum SubscriptionTier {
  free,
  pro,
  premium
}

class EnhancedSubscriptionService extends ChangeNotifier {
  // 제한 설정
  static const Map<SubscriptionTier, int> DAILY_LIMITS = {
    SubscriptionTier.free: 10,
    SubscriptionTier.pro: 30,
    SubscriptionTier.premium: 100,
  };
  
  // RevenueCat 설정
  static const String REVENUECAT_API_KEY_IOS = 'appl_YOUR_KEY';
  static const String REVENUECAT_API_KEY_ANDROID = 'goog_YOUR_KEY';
  
  // 상품 ID
  static const String PRO_MONTHLY = 'pro_monthly_9900';
  static const String PRO_YEARLY = 'pro_yearly_99000';
  static const String PREMIUM_MONTHLY = 'premium_monthly_19900';
  
  // 상태
  SubscriptionTier _currentTier = SubscriptionTier.free;
  int _todayUsageCount = 0;
  DateTime? _lastResetDate;
  CustomerInfo? _customerInfo;
  bool _isInitialized = false;
  
  // Getters
  SubscriptionTier get currentTier => _currentTier;
  int get todayUsageCount => _todayUsageCount;
  int get dailyLimit => DAILY_LIMITS[_currentTier]!;
  int get remainingReplays => dailyLimit - _todayUsageCount;
  bool get canUseReplay => _todayUsageCount < dailyLimit;
  bool get isPro => _currentTier != SubscriptionTier.free;
  bool get isPremium => _currentTier == SubscriptionTier.premium;
  
  // 생성자
  EnhancedSubscriptionService() {
    _initialize();
  }
  
  // 1. RevenueCat 초기화
  Future<void> _initialize() async {
    try {
      // RevenueCat 설정
      await Purchases.setLogLevel(LogLevel.debug);
      
      PurchasesConfiguration configuration;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        configuration = PurchasesConfiguration(REVENUECAT_API_KEY_IOS);
      } else {
        configuration = PurchasesConfiguration(REVENUECAT_API_KEY_ANDROID);
      }
      
      await Purchases.configure(configuration);
      
      // 구매자 정보 리스너 설정
      Purchases.addCustomerInfoUpdateListener((customerInfo) {
        _customerInfo = customerInfo;
        _updateSubscriptionStatus(customerInfo);
      });
      
      // 초기 구매자 정보 가져오기
      _customerInfo = await Purchases.getCustomerInfo();
      _updateSubscriptionStatus(_customerInfo!);
      
      _isInitialized = true;
      
      // 로컬 사용량 데이터 로드
      await _loadUsageData();
      
    } catch (e) {
      print('❌ RevenueCat initialization failed: $e');
      // 폴백: 로컬 스토리지만 사용
      await _loadUsageData();
    }
  }
  
  // 2. 구독 상태 업데이트
  void _updateSubscriptionStatus(CustomerInfo customerInfo) {
    if (customerInfo.entitlements.all['premium']?.isActive ?? false) {
      _currentTier = SubscriptionTier.premium;
    } else if (customerInfo.entitlements.all['pro']?.isActive ?? false) {
      _currentTier = SubscriptionTier.pro;
    } else {
      _currentTier = SubscriptionTier.free;
    }
    
    notifyListeners();
  }
  
  // 3. 사용량 데이터 로드 및 리셋
  Future<void> _loadUsageData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 날짜 체크 및 자동 리셋
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastResetStr = prefs.getString('last_reset_date') ?? '';
    
    if (lastResetStr != today) {
      // 새로운 날 - 카운트 리셋
      _todayUsageCount = 0;
      _lastResetDate = DateTime.now();
      await prefs.setString('last_reset_date', today);
      await prefs.setInt('today_usage_count', 0);
      
      // 리셋 시간 기록 (통계용)
      await _recordResetEvent();
    } else {
      // 오늘 사용량 로드
      _todayUsageCount = prefs.getInt('today_usage_count') ?? 0;
    }
    
    notifyListeners();
  }
  
  // 4. Upgrade Replay 사용 기록
  Future<bool> useUpgradeReplay() async {
    // 사용 가능 체크
    if (!canUseReplay) {
      return false;
    }
    
    _todayUsageCount++;
    
    // 로컬 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_usage_count', _todayUsageCount);
    
    // 사용 통계 기록
    await _recordUsageEvent();
    
    notifyListeners();
    return true;
  }
  
  // 5. 상품 가져오기
  Future<List<Package>> getAvailablePackages() async {
    try {
      final offerings = await Purchases.getOfferings();
      
      if (offerings.current != null) {
        return offerings.current!.availablePackages;
      }
      
      return [];
    } catch (e) {
      print('❌ Failed to get offerings: $e');
      return [];
    }
  }
  
  // 6. 구독 구매
  Future<bool> purchaseSubscription(Package package) async {
    try {
      final purchaserInfo = await Purchases.purchasePackage(package);
      _customerInfo = purchaserInfo;
      _updateSubscriptionStatus(purchaserInfo);
      
      // 구매 성공 이벤트
      await _recordPurchaseEvent(package.storeProduct.identifier);
      
      return true;
    } catch (e) {
      print('❌ Purchase failed: $e');
      return false;
    }
  }
  
  // 7. 구독 복원
  Future<bool> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      _customerInfo = customerInfo;
      _updateSubscriptionStatus(customerInfo);
      
      return customerInfo.entitlements.all.isNotEmpty;
    } catch (e) {
      print('❌ Restore failed: $e');
      return false;
    }
  }
  
  // 8. 구독 취소 (관리 페이지로 이동)
  Future<void> manageSubscription() async {
    try {
      await Purchases.showManageSubscriptions();
    } catch (e) {
      print('❌ Failed to show manage subscriptions: $e');
    }
  }
  
  // 9. 프로모션 코드 사용
  Future<bool> redeemPromoCode(String code) async {
    try {
      // iOS only
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await Purchases.presentCodeRedemptionSheet();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Failed to redeem code: $e');
      return false;
    }
  }
  
  // 10. 남은 시간 계산
  String getTimeUntilReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final difference = tomorrow.difference(now);
    
    if (difference.inHours > 0) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    } else {
      return '${difference.inMinutes}m';
    }
  }
  
  // 11. 사용 통계 (Analytics)
  Future<void> _recordUsageEvent() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 주간 사용량 추적
    final weekKey = 'week_${DateFormat('yyyy-ww').format(DateTime.now())}';
    final weekCount = prefs.getInt(weekKey) ?? 0;
    await prefs.setInt(weekKey, weekCount + 1);
    
    // 월간 사용량 추적
    final monthKey = 'month_${DateFormat('yyyy-MM').format(DateTime.now())}';
    final monthCount = prefs.getInt(monthKey) ?? 0;
    await prefs.setInt(monthKey, monthCount + 1);
  }
  
  Future<void> _recordResetEvent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_reset_timestamp', DateTime.now().toIso8601String());
  }
  
  Future<void> _recordPurchaseEvent(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 구매 이력 저장
    final purchases = prefs.getStringList('purchase_history') ?? [];
    purchases.add('${DateTime.now().toIso8601String()}:$productId');
    await prefs.setStringList('purchase_history', purchases);
  }
  
  // 12. 사용량 통계 가져오기
  Future<Map<String, dynamic>> getUsageStatistics() async {
    final prefs = await SharedPreferences.getInstance();
    
    final weekKey = 'week_${DateFormat('yyyy-ww').format(DateTime.now())}';
    final monthKey = 'month_${DateFormat('yyyy-MM').format(DateTime.now())}';
    
    return {
      'today': _todayUsageCount,
      'thisWeek': prefs.getInt(weekKey) ?? 0,
      'thisMonth': prefs.getInt(monthKey) ?? 0,
      'tier': _currentTier.toString(),
      'dailyLimit': dailyLimit,
    };
  }
  
  // 13. 특별 프로모션 체크
  Future<bool> checkSpecialOffer() async {
    // 첫 사용자에게 특별 할인 제공
    final prefs = await SharedPreferences.getInstance();
    final firstUseDate = prefs.getString('first_use_date');
    
    if (firstUseDate == null) {
      await prefs.setString('first_use_date', DateTime.now().toIso8601String());
      return true; // 신규 사용자 할인
    }
    
    // 3일 내 신규 사용자
    final firstUse = DateTime.parse(firstUseDate);
    if (DateTime.now().difference(firstUse).inDays <= 3) {
      return true;
    }
    
    return false;
  }
  
  @override
  void dispose() {
    super.dispose();
  }
}