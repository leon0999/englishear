#!/usr/bin/env python3
"""
Test OpenAI Realtime API WebSocket Connection
Checks if API key has access to Realtime API
"""

import asyncio
import websockets
import json
import base64
import ssl
import certifi

# Load API key
def load_api_key():
    with open('/Users/user/Desktop/EnglishEar/english_ear_app/.env', 'r') as f:
        for line in f:
            if line.startswith('OPENAI_API_KEY='):
                return line.split('=')[1].strip()
    return None

API_KEY = load_api_key()

async def test_realtime_connection():
    """Test WebSocket connection to Realtime API"""
    print("\n🔍 Testing OpenAI Realtime API Access...")
    print("=" * 60)
    
    if not API_KEY:
        print("❌ No API key found in .env file")
        return False
    
    print(f"🔑 Using API key: {API_KEY[:20]}...{API_KEY[-4:]}")
    
    uri = "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17"
    
    try:
        print("\n📡 Attempting WebSocket connection...")
        
        # Create SSL context
        ssl_context = ssl.create_default_context()
        ssl_context.load_verify_locations(certifi.where())
        
        # Connect with auth headers
        headers = {
            "Authorization": f"Bearer {API_KEY}",
            "OpenAI-Beta": "realtime=v1"
        }
        
        async with websockets.connect(uri, additional_headers=headers, ssl=ssl_context) as websocket:
            print("✅ WebSocket connected successfully!")
            
            # Send session update
            session_update = {
                "type": "session.update",
                "session": {
                    "modalities": ["text", "audio"],
                    "instructions": "You are a helpful assistant.",
                    "voice": "nova",
                    "input_audio_format": "pcm16",
                    "output_audio_format": "pcm16",
                    "temperature": 0.8
                }
            }
            
            await websocket.send(json.dumps(session_update))
            print("📤 Sent session configuration")
            
            # Wait for response
            response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
            event = json.loads(response)
            
            print(f"📥 Received event: {event['type']}")
            
            if event['type'] == 'error':
                error = event.get('error', {})
                print(f"\n❌ Error from server:")
                print(f"   Code: {error.get('code')}")
                print(f"   Message: {error.get('message')}")
                
                if error.get('code') == 'invalid_api_key':
                    print("\n⚠️ API key is invalid")
                elif error.get('code') == 'insufficient_quota':
                    print("\n⚠️ Insufficient quota - need to add credits")
                elif error.get('code') == 'unauthorized':
                    print("\n⚠️ API key doesn't have Realtime API access")
                
                return False
                
            elif event['type'] == 'session.created':
                session = event.get('session', {})
                print(f"\n✅ Session created successfully!")
                print(f"   Session ID: {session.get('id')}")
                print(f"   Model: {session.get('model')}")
                
                # Test sending a text message
                test_message = {
                    "type": "conversation.item.create",
                    "item": {
                        "type": "message",
                        "role": "user",
                        "content": [{
                            "type": "text",
                            "text": "Hello, this is a test."
                        }]
                    }
                }
                
                await websocket.send(json.dumps(test_message))
                print("\n📤 Sent test message")
                
                # Request response
                create_response = {
                    "type": "response.create"
                }
                await websocket.send(json.dumps(create_response))
                
                # Wait for AI response
                print("⏳ Waiting for AI response...")
                
                while True:
                    response = await asyncio.wait_for(websocket.recv(), timeout=10.0)
                    event = json.loads(response)
                    
                    if event['type'] == 'response.done':
                        print("✅ AI response completed")
                        break
                    elif event['type'] == 'response.text.delta':
                        delta = event.get('delta', '')
                        print(f"   AI: {delta}", end='')
                
                return True
            
            else:
                print(f"Unexpected event type: {event['type']}")
                return False
                
    except websockets.InvalidStatusCode as e:
        print(f"\n❌ WebSocket connection failed with status code: {e.status_code}")
        
        if e.status_code == 401:
            print("   → Invalid API key")
        elif e.status_code == 403:
            print("   → API key doesn't have Realtime API access")
        elif e.status_code == 429:
            print("   → Rate limit exceeded or quota exhausted")
        elif e.status_code == 503:
            print("   → Service temporarily unavailable")
        
        return False
        
    except asyncio.TimeoutError:
        print("\n⏱️ Connection timed out")
        return False
        
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        return False

def analyze_results(has_access):
    """Provide analysis and recommendations"""
    print("\n" + "=" * 60)
    print("📊 Analysis Results")
    print("=" * 60)
    
    if has_access:
        print("\n🎉 SUCCESS: Your API key has Realtime API access!")
        print("\n✅ You can:")
        print("   • Use WebSocket streaming for real-time conversations")
        print("   • Process audio in real-time with low latency")
        print("   • Build voice-enabled applications")
        
        print("\n💰 Pricing:")
        print("   • Audio input: $0.06/minute")
        print("   • Audio output: $0.24/minute")
        print("   • Text: Standard GPT-4 rates")
        
    else:
        print("\n❌ FAILED: Cannot access Realtime API")
        print("\n🔧 How to fix:")
        print("   1. Check your credits at: https://platform.openai.com/usage")
        print("   2. Add credits (minimum $5): https://platform.openai.com/billing")
        print("   3. Verify API key is valid")
        print("   4. Make sure you're using the latest API key")
        
        print("\n💡 Alternative:")
        print("   Use HTTP-based conversation with:")
        print("   • Whisper API for speech-to-text")
        print("   • GPT-3.5/4 for chat completions")
        print("   • TTS API for text-to-speech")

async def main():
    print("=" * 70)
    print("🚀 OpenAI Realtime API Access Test")
    print("=" * 70)
    
    has_access = await test_realtime_connection()
    analyze_results(has_access)
    
    print("\n" + "=" * 70)
    if has_access:
        print("✅ Realtime API is ready to use in your Flutter app!")
    else:
        print("⚠️ Using HTTP fallback mode in your Flutter app")
    print("=" * 70)

if __name__ == "__main__":
    asyncio.run(main())