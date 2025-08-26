import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  print('Testing API Keys...');
  print('OpenAI Key: ${dotenv.env['OPENAI_API_KEY']?.substring(0, 20)}...');
  print('Stability Key: ${dotenv.env['STABILITY_API_KEY']?.substring(0, 20)}...');
  
  // Test OpenAI API
  final dio = Dio();
  
  try {
    print('\n🔍 Testing OpenAI API...');
    final response = await dio.get(
      'https://api.openai.com/v1/models',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY']}',
        },
      ),
    );
    print('✅ OpenAI API works! Available models: ${response.data['data'].length}');
  } catch (e) {
    print('❌ OpenAI API Error: $e');
  }
  
  try {
    print('\n🔍 Testing Stability API...');
    final response = await dio.get(
      'https://api.stability.ai/v1/user/account',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${dotenv.env['STABILITY_API_KEY']}',
        },
      ),
    );
    print('✅ Stability API works! Credits: ${response.data['credits']}');
  } catch (e) {
    print('❌ Stability API Error: $e');
  }
  
  exit(0);
}