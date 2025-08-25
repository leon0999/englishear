class SentenceDatabase {
  static const List<Map<String, dynamic>> beginner = [
    {
      'image': 'park',
      'keywords': ['walking', 'dog'],
      'sentence': 'A woman is walking her dog',
      'difficulty': 1,
    },
    {
      'image': 'kitchen',
      'keywords': ['eating', 'breakfast'],
      'sentence': 'He is eating breakfast',
      'difficulty': 1,
    },
    {
      'image': 'classroom',
      'keywords': ['reading', 'book'],
      'sentence': 'Students are reading books',
      'difficulty': 1,
    },
    {
      'image': 'playground',
      'keywords': ['playing', 'children'],
      'sentence': 'Children are playing outside',
      'difficulty': 1,
    },
    {
      'image': 'bedroom',
      'keywords': ['sleeping', 'bed'],
      'sentence': 'The cat is sleeping on the bed',
      'difficulty': 1,
    },
  ];
  
  static const List<Map<String, dynamic>> intermediate = [
    {
      'image': 'cafe',
      'keywords': ['drinking', 'coffee', 'laptop'],
      'sentence': 'Someone is drinking coffee while working on a laptop',
      'difficulty': 2,
    },
    {
      'image': 'market',
      'keywords': ['shopping', 'vegetables', 'fresh'],
      'sentence': 'People are shopping for fresh vegetables at the market',
      'difficulty': 2,
    },
    {
      'image': 'gym',
      'keywords': ['exercising', 'weights', 'training'],
      'sentence': 'Athletes are training with weights in the gym',
      'difficulty': 2,
    },
    {
      'image': 'restaurant',
      'keywords': ['waiter', 'serving', 'customers'],
      'sentence': 'The waiter is serving food to customers',
      'difficulty': 2,
    },
    {
      'image': 'beach',
      'keywords': ['surfing', 'waves', 'ocean'],
      'sentence': 'Surfers are riding the waves in the ocean',
      'difficulty': 2,
    },
  ];
  
  static const List<Map<String, dynamic>> advanced = [
    {
      'image': 'conference',
      'keywords': ['presenting', 'audience', 'projector', 'business'],
      'sentence': 'The executive is presenting quarterly results to the board of directors',
      'difficulty': 3,
    },
    {
      'image': 'laboratory',
      'keywords': ['conducting', 'experiment', 'microscope', 'research'],
      'sentence': 'Scientists are conducting groundbreaking research using advanced microscopes',
      'difficulty': 3,
    },
    {
      'image': 'concert',
      'keywords': ['performing', 'orchestra', 'symphony', 'conductor'],
      'sentence': 'The orchestra is performing a classical symphony under the conductor\'s direction',
      'difficulty': 3,
    },
    {
      'image': 'courtroom',
      'keywords': ['arguing', 'lawyer', 'judge', 'case'],
      'sentence': 'The defense lawyer is arguing the case before the judge and jury',
      'difficulty': 3,
    },
    {
      'image': 'surgery',
      'keywords': ['operating', 'surgeon', 'patient', 'medical'],
      'sentence': 'The surgical team is performing a complex operation on the patient',
      'difficulty': 3,
    },
  ];
  
  // 난이도별 문장 가져오기
  static List<Map<String, dynamic>> getSentencesByDifficulty(int difficulty) {
    switch (difficulty) {
      case 1:
        return beginner;
      case 2:
        return intermediate;
      case 3:
        return advanced;
      default:
        return beginner;
    }
  }
  
  // 랜덤 문장 가져오기
  static Map<String, dynamic> getRandomSentence(int difficulty) {
    final sentences = getSentencesByDifficulty(difficulty);
    sentences.shuffle();
    return sentences.first;
  }
  
  // 모든 문장 가져오기
  static List<Map<String, dynamic>> getAllSentences() {
    return [...beginner, ...intermediate, ...advanced];
  }
}