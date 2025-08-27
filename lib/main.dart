import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/training_screen.dart'; // 🔥 추가
import 'screens/immersive_training_screen.dart'; // 몰입형 화면 추가
import 'screens/immersive_training_screen_v2.dart'; // 개선된 몰입형 화면
import 'services/image_generation_service.dart';
import 'services/stable_diffusion_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 환경 변수 로드
  try {
    await dotenv.load(fileName: ".env");
    print('✅ Environment variables loaded successfully');
  } catch (e) {
    print('⚠️ Warning: Could not load .env file. Using default values.');
  }

  // 이미지 생성 서비스 초기화
  try {
    final imageService = ImageGenerationService();
    await imageService.initialize();
    print('✅ Image generation service initialized');
  } catch (e) {
    print('⚠️ Warning: Image service initialization failed: $e');
  }

  // Stable Diffusion API 헬스 체크
  try {
    final sdService = StableDiffusionService();
    final health = await sdService.checkAPIHealth();
    if (health['healthy'] == true) {
      print('✅ Stable Diffusion API: ${health['message']}');
      if (health['credits'] != null) {
        print('   Credits: \$${health['credits'].toStringAsFixed(2)}');
      }
    } else {
      print('⚠️ Stable Diffusion API: ${health['message']}');
    }
  } catch (e) {
    print('⚠️ Could not check SD API health: $e');
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
      // 🔥 개발 중 임시 - ImmersiveTrainingScreenV2 직접 실행
      home: ImmersiveTrainingScreenV2(),
      // initialRoute: '/home',
      // routes: {
      //   '/': (context) => const SplashScreen(),
      //   '/onboarding': (context) => const OnboardingScreen(),
      //   '/home': (context) => const HomeScreen(),
      // },
    );
  }
}
