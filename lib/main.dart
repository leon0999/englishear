import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'services/enhanced_subscription_service.dart';
import 'services/openai_service_simple.dart';
import 'services/conversation_service.dart';
import 'services/usage_limit_service.dart';
import 'core/logger.dart';
import 'screens/voice_chat_screen.dart';
import 'screens/chatgpt_level_screen.dart';
import 'screens/chatgpt_level_screen_v2.dart';
import 'screens/realtime_only_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 환경 변수 로드
  try {
    await dotenv.load(fileName: ".env");
    AppLogger.info('Environment variables loaded successfully');
  } catch (e) {
    AppLogger.warning('Could not load .env file. Using default values.');
  }
  
  // 서비스 초기화
  try {
    final openAIService = OpenAIServiceSimple();
    await openAIService.initializeCache();
    AppLogger.info('OpenAI service initialized');
    
    final usageLimitService = UsageLimitService();
    await usageLimitService.initialize();
    AppLogger.info('Usage limit service initialized');
  } catch (e) {
    AppLogger.error('Failed to initialize services', e);
  }

  // iOS 스타일 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EnhancedSubscriptionService()),
        ChangeNotifierProvider(create: (_) => ConversationService()),
        ChangeNotifierProvider(create: (_) => UsageLimitService()),
      ],
      child: MaterialApp(
        title: 'EnglishEar - AI Voice Chat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: Colors.blue,
          colorScheme: const ColorScheme.dark(
            primary: Colors.blue,
            secondary: Colors.purple,
          ),
          scaffoldBackgroundColor: const Color(0xFF0A0A0A),
          fontFamily: 'SF Pro Display',
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
        ),
        home: const RealtimeOnlyScreen(),  // Using Realtime API only
      ),
    );
  }
}
