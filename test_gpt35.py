#!/usr/bin/env python3
"""
Test GPT-3.5-turbo (cheaper alternative)
"""

import requests
import json

# Load API key
def load_api_key():
    with open('/Users/user/Desktop/EnglishEar/english_ear_app/.env', 'r') as f:
        for line in f:
            if line.startswith('OPENAI_API_KEY='):
                return line.split('=')[1].strip()
    return None

API_KEY = load_api_key()

print("🧪 Testing GPT-3.5-turbo (Cheaper Model)")
print("=" * 50)

url = "https://api.openai.com/v1/chat/completions"
headers = {
    'Authorization': f'Bearer {API_KEY}',
    'Content-Type': 'application/json'
}

payload = {
    "model": "gpt-3.5-turbo",
    "messages": [
        {
            "role": "system",
            "content": "You are a helpful English tutor. Keep responses brief."
        },
        {
            "role": "user",
            "content": "Hello!"
        }
    ],
    "temperature": 0.7,
    "max_tokens": 50
}

try:
    response = requests.post(url, headers=headers, json=payload)
    
    if response.status_code == 200:
        data = response.json()
        ai_response = data['choices'][0]['message']['content']
        tokens = data['usage']['total_tokens']
        
        print("✅ Success with GPT-3.5-turbo!")
        print(f"Response: {ai_response}")
        print(f"Tokens used: {tokens}")
        print(f"Estimated cost: ${tokens * 0.0000015:.6f}")
    else:
        print(f"❌ Failed: {response.status_code}")
        error = response.json()
        print(f"Error: {error['error']['message']}")
        
except Exception as e:
    print(f"Error: {e}")