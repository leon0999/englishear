# EnglishEar MVP - AI Voice Chat

## 🎯 MVP 핵심 기능

### 1. AI 음성 대화
- GPT-4와 자연스러운 영어 대화
- 15가지 랜덤 시나리오 (카페, 면접, 공항 등)
- 실시간 음성 인식 (STT) + 고품질 음성 합성 (TTS)

### 2. Upgrade Replay 시스템
- 최소 6턴 대화 후 활성화
- 사용자의 영어를 네이티브 수준으로 개선
- 개선된 대화 전체를 다시 들려줌
- 맞춤형 학습 리포트 제공

### 3. 구독 모델
- **무료**: 일 10회 Upgrade Replay
- **Pro (₩9,900/월)**: 일 30회 Upgrade Replay

## 🚀 실행 방법

### Chrome에서 테스트 (권장)
```bash
# 의존성 설치
flutter pub get

# Chrome에서 실행 (VSCode)
# F5 키를 누르고 "EnglishEar (Chrome Debug)" 선택

# 또는 터미널에서
flutter run -d chrome --web-port 5555
```

### FVM 사용 시
```bash
# FVM Flutter 버전 설정
fvm use 3.35.1

# Chrome에서 실행
fvm flutter run -d chrome --web-port 5555
```

## 📁 프로젝트 구조

```
lib/
├── main.dart                          # 앱 진입점
├── screens/
│   └── voice_chat_screen.dart         # 메인 화면 (MVP)
├── services/
│   ├── conversation_service.dart      # 대화 핵심 로직
│   ├── openai_service.dart           # GPT API 통합
│   ├── usage_limit_service.dart      # 사용 제한 관리
│   └── cache_service.dart            # 캐싱 시스템
├── core/
│   ├── logger.dart                   # 로깅 시스템
│   └── exceptions.dart              # 에러 처리
└── models/
    └── openai_types.dart            # 데이터 모델
```

## 🎮 사용자 플로우

1. **앱 시작**
   - "Start Conversation" 버튼 탭

2. **대화 진행**
   - AI가 먼저 시나리오에 맞는 대사로 시작
   - "Speak" 버튼으로 음성 입력
   - 실시간으로 AI가 응답

3. **Upgrade Replay** (6턴 이후)
   - 보라색 "Upgrade Replay" 버튼 활성화
   - 버튼 탭 시:
     - 사용자 영어를 네이티브 수준으로 개선
     - 개선된 전체 대화 재생
     - 학습 리포트 표시

4. **구독 유도**
   - 무료 10회 소진 시 Pro 업그레이드 안내

## 🔑 API 키 설정

`.env` 파일:
```
OPENAI_API_KEY=your-api-key-here
```

## 📱 배포 준비

### iOS
```bash
flutter build ios --release
# Xcode에서 Archive 후 App Store Connect 업로드
```

### Android
```bash
flutter build appbundle --release
# Google Play Console에서 업로드
```

### Web
```bash
flutter build web --release
# Firebase Hosting 또는 Vercel 배포
```

## 🎯 성과 지표

- **목표**: 사용자 영어 학습 만족도 90%
- **수익**: 월 ₩9,900 × 1,000명 = ₩9,900,000
- **리텐션**: DAU 80% 목표

## 🔧 기술 스택

- **Frontend**: Flutter 3.35.1
- **AI**: OpenAI GPT-4 Turbo
- **음성**: speech_to_text, flutter_tts
- **상태관리**: Provider
- **결제**: in_app_purchase

## 📝 주의사항

- Chrome에서 마이크 권한 허용 필요
- 안정적인 인터넷 연결 필수
- OpenAI API 키 필수

---

**개발자**: 20년차 Google 출신 풀스택 개발자
**목표**: 월 3천만원 수익 달성