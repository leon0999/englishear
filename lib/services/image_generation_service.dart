import 'package:dio/dio.dart';

class ImageGenerationService {
  final Dio _dio = Dio();
  
  // Stable Diffusion 또는 DALL-E API 연동
  Future<String> generateSceneImage(String prompt) async {
    try {
      // 실제 구현시 API 키와 엔드포인트 설정 필요
      // final response = await _dio.post(
      //   'https://api.openai.com/v1/images/generations',
      //   options: Options(
      //     headers: {
      //       'Authorization': 'Bearer YOUR_API_KEY',
      //       'Content-Type': 'application/json',
      //     },
      //   ),
      //   data: {
      //     'prompt': prompt,
      //     'n': 1,
      //     'size': '512x512',
      //   },
      // );
      // return response.data['data'][0]['url'];
      
      // 현재는 더미 이미지 URL 반환
      return 'https://picsum.photos/400/250?random=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      print('Image generation error: $e');
      return 'https://picsum.photos/400/250';
    }
  }
  
  // 미리 생성된 이미지 세트 가져오기
  List<Map<String, dynamic>> getPreGeneratedScenes() {
    return [
      {
        'imageUrl': 'https://picsum.photos/400/250?random=1',
        'keywords': ['walking', 'dog', 'park'],
        'sentence': 'A woman is walking her dog in the park',
      },
      {
        'imageUrl': 'https://picsum.photos/400/250?random=2',
        'keywords': ['reading', 'book', 'cafe'],
        'sentence': 'Someone is reading a book at a cozy cafe',
      },
      {
        'imageUrl': 'https://picsum.photos/400/250?random=3',
        'keywords': ['playing', 'guitar', 'street'],
        'sentence': 'A musician is playing guitar on the street',
      },
      {
        'imageUrl': 'https://picsum.photos/400/250?random=4',
        'keywords': ['cooking', 'kitchen', 'vegetables'],
        'sentence': 'A chef is cooking with fresh vegetables in the kitchen',
      },
      {
        'imageUrl': 'https://picsum.photos/400/250?random=5',
        'keywords': ['running', 'beach', 'sunset'],
        'sentence': 'People are running on the beach during sunset',
      },
    ];
  }
}