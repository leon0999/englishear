#!/bin/bash

echo "🔧 Flutter SDK 문제 해결 시작..."

# 1. 캐시 정리
echo "📦 캐시 정리 중..."
flutter clean
rm -rf pubspec.lock
rm -rf .dart_tool
rm -rf ios/Pods
rm -rf ios/Podfile.lock

# 2. pub cache 정리
echo "🗑️ Pub 캐시 정리 중..."
flutter pub cache clean --force

# 3. 패키지 재설치
echo "📥 패키지 재설치 중..."
flutter pub get

# 4. iOS 의존성 설치 (iOS용)
echo "🍎 iOS 의존성 설치 중..."
cd ios && pod install --repo-update && cd ..

echo "✅ 완료! 이제 flutter run을 실행하세요."