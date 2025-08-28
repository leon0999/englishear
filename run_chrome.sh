#!/bin/bash

echo "🧹 Cleaning Flutter project..."
/Users/user/Desktop/EnglishEar/flutter/bin/flutter clean

echo "📦 Getting dependencies..."
/Users/user/Desktop/EnglishEar/flutter/bin/flutter pub get

echo "🌐 Running on Chrome..."
/Users/user/Desktop/EnglishEar/flutter/bin/flutter run -d chrome --web-port 5555 --web-renderer html

# FVM을 사용하는 경우:
# fvm flutter clean
# fvm flutter pub get  
# fvm flutter run -d chrome --web-port 5555 --web-renderer html