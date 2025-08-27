// lib/services/subscription_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

enum SubscriptionStatus {
  free,
  pro,
  expired,
}

class SubscriptionService extends ChangeNotifier {
  static const int FREE_DAILY_LIMIT = 10;
  static const int PRO_DAILY_LIMIT = 30;
  static const double PRO_MONTHLY_PRICE = 9900;
  static const String PRO_PRODUCT_ID = 'com.englishear.pro.monthly';
  
  // 상태
  SubscriptionStatus _status = SubscriptionStatus.free;
  int _todayUsageCount = 0;
  DateTime? _lastResetDate;
  DateTime? _subscriptionEndDate;
  
  // In-app purchase 관련
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _purchasePending = false;
  
  // Getters
  SubscriptionStatus get status => _status;
  int get todayUsageCount => _todayUsageCount;
  int get dailyLimit => _status == SubscriptionStatus.pro ? PRO_DAILY_LIMIT : FREE_DAILY_LIMIT;
  int get remainingReplays => dailyLimit - _todayUsageCount;
  bool get canUseReplay => _todayUsageCount < dailyLimit;
  bool get isPro => _status == SubscriptionStatus.pro;
  bool get purchasePending => _purchasePending;
  
  SubscriptionService() {
    _initializeStore();
    _loadUsageData();
  }
  
  // 1. 스토어 초기화
  Future<void> _initializeStore() async {
    if (kIsWeb) {
      // 웹에서는 임시로 로컬 스토리지만 사용
      print('📱 Web platform detected - using local storage only');
      return;
    }
    
    final bool available = await _inAppPurchase.isAvailable();
    if (!available) {
      print('❌ In-app purchase not available');
      return;
    }
    
    _isAvailable = available;
    
    // 제품 정보 로드
    const Set<String> _kIds = <String>{PRO_PRODUCT_ID};
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_kIds);
    
    if (response.error != null) {
      print('❌ Error loading products: ${response.error}');
      return;
    }
    
    if (response.productDetails.isEmpty) {
      print('❌ Products not found');
      return;
    }
    
    _products = response.productDetails;
    
    // 구매 스트림 리스닝
    _subscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (error) {
        print('❌ Purchase stream error: $error');
      },
    );
    
    // 이전 구매 복원
    await _restorePurchases();
  }
  
  // 2. 구매 업데이트 처리
  void _handlePurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
        notifyListeners();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          print('❌ Purchase error: ${purchaseDetails.error}');
          _purchasePending = false;
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          // 구매 성공
          _activateProSubscription();
        }
        
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
        
        _purchasePending = false;
        notifyListeners();
      }
    }
  }
  
  // 3. 사용량 데이터 로드
  Future<void> _loadUsageData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 날짜 체크 및 리셋
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastResetStr = prefs.getString('last_reset_date') ?? '';
    
    if (lastResetStr != today) {
      // 날짜가 바뀌면 사용량 리셋
      _todayUsageCount = 0;
      _lastResetDate = DateTime.now();
      await prefs.setString('last_reset_date', today);
      await prefs.setInt('today_usage_count', 0);
    } else {
      // 오늘 사용량 로드
      _todayUsageCount = prefs.getInt('today_usage_count') ?? 0;
    }
    
    // 구독 상태 체크
    final subscriptionEndStr = prefs.getString('subscription_end_date');
    if (subscriptionEndStr != null) {
      _subscriptionEndDate = DateTime.parse(subscriptionEndStr);
      if (_subscriptionEndDate!.isAfter(DateTime.now())) {
        _status = SubscriptionStatus.pro;
      } else {
        _status = SubscriptionStatus.expired;
      }
    }
    
    notifyListeners();
  }
  
  // 4. 사용량 기록
  Future<bool> recordReplayUsage() async {
    if (!canUseReplay) {
      return false;
    }
    
    _todayUsageCount++;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_usage_count', _todayUsageCount);
    
    notifyListeners();
    return true;
  }
  
  // 5. Pro 구독 구매
  Future<void> purchaseProSubscription() async {
    if (!_isAvailable || _products.isEmpty) {
      print('❌ Store not available or products not loaded');
      
      // 웹에서는 임시로 바로 Pro 활성화 (테스트용)
      if (kIsWeb) {
        await _activateProSubscription();
      }
      return;
    }
    
    final ProductDetails productDetails = _products.first;
    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: productDetails,
    );
    
    _purchasePending = true;
    notifyListeners();
    
    try {
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      print('❌ Purchase error: $e');
      _purchasePending = false;
      notifyListeners();
    }
  }
  
  // 6. Pro 구독 활성화
  Future<void> _activateProSubscription() async {
    _status = SubscriptionStatus.pro;
    _subscriptionEndDate = DateTime.now().add(const Duration(days: 30));
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subscription_end_date', _subscriptionEndDate!.toIso8601String());
    
    notifyListeners();
  }
  
  // 7. 구매 복원
  Future<void> _restorePurchases() async {
    if (!_isAvailable) return;
    
    try {
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      print('❌ Restore purchases error: $e');
    }
  }
  
  // 8. 구독 취소 (테스트용)
  Future<void> cancelSubscription() async {
    _status = SubscriptionStatus.free;
    _subscriptionEndDate = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('subscription_end_date');
    
    notifyListeners();
  }
  
  // 9. 사용량 리셋 (테스트용)
  Future<void> resetDailyUsage() async {
    _todayUsageCount = 0;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_usage_count', 0);
    
    notifyListeners();
  }
  
  // 10. 남은 시간 계산
  String getTimeUntilReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final difference = tomorrow.difference(now);
    
    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;
    
    return '${hours}h ${minutes}m';
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}