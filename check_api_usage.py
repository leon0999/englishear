#!/usr/bin/env python3
"""
OpenAI API Usage Check Script
"""

import requests
import json
from datetime import datetime, timedelta

# Load API key from .env file
def load_api_key():
    env_path = '/Users/user/Desktop/EnglishEar/english_ear_app/.env'
    with open(env_path, 'r') as f:
        for line in f:
            if line.startswith('OPENAI_API_KEY='):
                return line.split('=')[1].strip()
    return None

API_KEY = load_api_key()

def check_api_limits():
    """Check API rate limits and usage"""
    print("\n🔍 Checking API Usage and Limits...")
    print("=" * 60)
    
    # Test with a minimal request to check headers
    url = "https://api.openai.com/v1/models/gpt-3.5-turbo"
    headers = {
        'Authorization': f'Bearer {API_KEY}'
    }
    
    try:
        response = requests.get(url, headers=headers)
        
        # Print response headers that contain usage info
        print("\n📊 API Response Status:")
        print(f"   Status Code: {response.status_code}")
        
        if response.status_code == 200:
            print("   ✅ API Key is valid and active")
        elif response.status_code == 401:
            print("   ❌ Invalid API Key")
        elif response.status_code == 429:
            print("   ⚠️ Rate limit or quota exceeded")
            
            # Check rate limit headers
            if 'x-ratelimit-limit-requests' in response.headers:
                print(f"\n📈 Rate Limits:")
                print(f"   Request Limit: {response.headers.get('x-ratelimit-limit-requests', 'N/A')}")
                print(f"   Remaining Requests: {response.headers.get('x-ratelimit-remaining-requests', 'N/A')}")
                print(f"   Token Limit: {response.headers.get('x-ratelimit-limit-tokens', 'N/A')}")
                print(f"   Remaining Tokens: {response.headers.get('x-ratelimit-remaining-tokens', 'N/A')}")
            
            # Parse error message
            if response.text:
                error_data = json.loads(response.text)
                error_msg = error_data.get('error', {}).get('message', '')
                print(f"\n❌ Error Details:")
                print(f"   {error_msg}")
        
        print("\n💡 Possible Reasons for Quota Exceeded:")
        print("   1. Free trial credits exhausted")
        print("   2. Monthly spending limit reached ($20)")
        print("   3. API key was used extensively in other projects")
        print("   4. Billing issue or payment method problem")
        
        print("\n🔧 How to Fix:")
        print("   1. Check usage at: https://platform.openai.com/usage")
        print("   2. Check billing at: https://platform.openai.com/billing")
        print("   3. Increase usage limits in billing settings")
        print("   4. Add payment method if using free tier")
        
        # Test with the simplest possible request
        print("\n🧪 Testing Minimal API Request...")
        test_url = "https://api.openai.com/v1/models"
        test_response = requests.get(test_url, headers=headers)
        
        if test_response.status_code == 200:
            models = test_response.json()
            print(f"   ✅ Can list models (found {len(models.get('data', []))} models)")
            print("   → API key works, but may have usage limits")
        else:
            print(f"   ❌ Cannot even list models (Status: {test_response.status_code})")
            
    except Exception as e:
        print(f"❌ Error checking API: {e}")

def analyze_api_key():
    """Analyze API key format and age"""
    print("\n🔑 API Key Analysis:")
    print("=" * 60)
    
    if not API_KEY:
        print("❌ No API key found")
        return
    
    # Check key format
    if API_KEY.startswith('sk-proj-'):
        print("   ✅ Project-specific API key (new format)")
        print("   → This is a scoped key with specific permissions")
    elif API_KEY.startswith('sk-'):
        print("   ✅ Standard API key")
    else:
        print("   ⚠️ Unusual API key format")
    
    # Key length check
    print(f"   Key length: {len(API_KEY)} characters")
    if len(API_KEY) > 100:
        print("   → Long key format (post-2024)")
    else:
        print("   → Standard key format")
    
    print(f"\n   Key preview: {API_KEY[:20]}...{API_KEY[-4:]}")

def estimate_usage():
    """Estimate what could have used $20"""
    print("\n💰 What Could Use $20 of API Credits:")
    print("=" * 60)
    
    # Based on current pricing
    print("\n📊 Estimated Usage for $20:")
    print("   • GPT-4 Turbo: ~666,000 input tokens OR ~222,000 output tokens")
    print("   • GPT-3.5 Turbo: ~20 million tokens")
    print("   • Whisper: ~3,333 minutes of audio (~55 hours)")
    print("   • TTS: ~1.3 million characters")
    print("   • DALL-E 3: ~20 images (1024x1024)")
    
    print("\n🤔 Possible Usage Scenarios:")
    print("   1. Heavy testing with GPT-4 (lots of long conversations)")
    print("   2. Image generation with DALL-E")
    print("   3. Extensive audio processing")
    print("   4. Another app/project using the same API key")
    print("   5. Leaked API key being used by others")
    
    print("\n⚠️ Important Notes:")
    print("   • WebSocket Realtime API attempts could consume credits")
    print("   • Failed requests still count towards rate limits")
    print("   • Some models are more expensive than others")

def main():
    print("=" * 70)
    print("🔍 OpenAI API Usage Checker")
    print(f"📅 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)
    
    if not API_KEY:
        print("❌ No API key found in .env file")
        return
    
    # Run checks
    analyze_api_key()
    check_api_limits()
    estimate_usage()
    
    print("\n" + "=" * 70)
    print("📌 Recommended Actions:")
    print("=" * 70)
    print("1. Visit: https://platform.openai.com/usage")
    print("2. Check your actual usage for today and this month")
    print("3. Visit: https://platform.openai.com/billing")
    print("4. Check if $20 limit was reached")
    print("5. Consider:")
    print("   • Increasing the usage limit")
    print("   • Using GPT-3.5-turbo instead of GPT-4 for testing")
    print("   • Creating a new API key for this project only")
    print("\n💡 For testing, you can:")
    print("   • Use GPT-3.5-turbo (much cheaper)")
    print("   • Set up usage alerts")
    print("   • Use playground for manual testing")

if __name__ == "__main__":
    main()