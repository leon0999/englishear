import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/training_screen.dart'; // 🔥 추가
import 'services/image_generation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 환경 변수 로드
  try {
    await dotenv.load(fileName: ".env");
    print('Environment variables loaded successfully');
  } catch (e) {
    print('Warning: Could not load .env file. Using default values.');
  }

  // 이미지 생성 서비스 초기화
  try {
    final imageService = ImageGenerationService();
    await imageService.initialize();
    print('Image generation service initialized');
  } catch (e) {
    print('Warning: Image service initialization failed: $e');
  }

  // iOS 스타일 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 세로 모드만 허용
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const EnglishEarApp());
}

class EnglishEarApp extends StatelessWidget {
  const EnglishEarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EnglishEar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF2196F3),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        fontFamily: 'SF Pro Display',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
      ),
      // 🔥 개발 중 임시 - TrainingScreen 직접 실행
      home: TrainingScreen(),
      // initialRoute: '/home',
      // routes: {
      //   '/': (context) => const SplashScreen(),
      //   '/onboarding': (context) => const OnboardingScreen(),
      //   '/home': (context) => const HomeScreen(),
      // },
    );
  }
}
