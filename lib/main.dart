import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:external_app_launcher/external_app_launcher.dart';

void main() => runApp(MaterialApp(home: RizzieUniversalApp(), debugShowCheckedModeBanner: false));

class RizzieUniversalApp extends StatefulWidget {
  @override
  _RizzieUniversalAppState createState() => _RizzieUniversalAppState();
}

class _RizzieUniversalAppState extends State<RizzieUniversalApp> {
  stt.SpeechToText _speech = stt.SpeechToText();
  AudioPlayer _audioPlayer = AudioPlayer(); // Replaced FlutterTts with AudioPlayer
  
  bool _isListening = false;
  String _lastWords = "";
  
  // Dynamic Speaker State
  String _activeSpeaker = "Rishikesh";
  String _activeRelation = "Admin";
  final String _familyPassword = "rizzie2026family";

  // Quick lookup map for common Android apps
  final Map<String, String> appPackages = {
    "whatsapp": "com.whatsapp",
    "spotify": "com.spotify.music",
    "instagram": "com.instagram.android",
    "calculator": "com.google.android.calculator",
    "maps": "com.google.android.apps.maps"
  };

  @override
  void initState() {
    super.initState();
    _speech.initialize();
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(onResult: (val) {
        setState(() => _lastWords = val.recognizedWords);
        if (val.finalResult) {
          _speech.stop();
          setState(() => _isListening = false);
          if (_lastWords.isNotEmpty) {
            _sendToRizzieCore(_lastWords);
          }
        }
      });
    }
  }

  Future<void> _sendToRizzieCore(String query) async {
    // Make sure this matches your live Render URL exactly
    final String backendUrl = "https://rizzie-core.onrender.com"; 
    
    try {
      // 1. Get AI Logic from Groq/Gemini
      final response = await http.post(
        Uri.parse("$backendUrl/rizzie"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "password": _familyPassword,
          "speaker": "$_activeSpeaker ($_activeRelation)", 
          "query": query,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String spokenReply = data["spoken_reply"] ?? "";
        String action = data["action"] ?? "NONE";
        String target = data["target"] ?? "";

        // 2. Play Sarvam AI Voice
        if (spokenReply.isNotEmpty) {
          final audioResponse = await http.post(
            Uri.parse("$backendUrl/speak"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"text": spokenReply}),
          );

          if (audioResponse.statusCode == 200) {
            // Play the .wav bytes directly from the server memory!
            await _audioPlayer.play(BytesSource(audioResponse.bodyBytes));
          } else {
            print("Sarvam Audio Error: ${audioResponse.body}");
          }
        }

        // 3. Execute On-Device Actions
        if (action == "PLAY_YOUTUBE") {
          final ytUrl = Uri.parse("https://www.youtube.com/results?search_query=$target");
          await launchUrl(ytUrl, mode: LaunchMode.externalApplication);
        } 
        else if (action == "OPEN_APP") {
          // Clean the target string and find the package name
          String cleanTarget = target.toLowerCase().trim();
          String? packageName = appPackages[cleanTarget];
          
          if (packageName != null) {
            await LaunchApp.openApp(androidPackageName: packageName);
          } else {
            print("App package not mapped for: $target");
          }
        }
      }
    } catch (e) {
      print("Network Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Rizzie - Family AI"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Who is speaking right now?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            
            // Universal Speaker Selector Chips
            Wrap(
              spacing: 10.0,
              children: [
                ChoiceChip(
                  label: Text("Rishikesh"),
                  selected: _activeSpeaker == "Rishikesh",
                  onSelected: (selected) => setState(() { _activeSpeaker = "Rishikesh"; _activeRelation = "Admin"; }),
                ),
                ChoiceChip(
                  label: Text("Mom"),
                  selected: _activeSpeaker == "Mom",
                  onSelected: (selected) => setState(() { _activeSpeaker = "Mom"; _activeRelation = "Mother"; }),
                ),
                ChoiceChip(
                  label: Text("Sister"),
                  selected: _activeSpeaker == "Sister",
                  onSelected: (selected) => setState(() { _activeSpeaker = "Sister"; _activeRelation = "Sister"; }),
                ),
              ],
            ),
            SizedBox(height: 60),
            
            Text(_isListening ? "Listening..." : "Tap mic to talk", style: TextStyle(fontSize: 18, color: Colors.grey[700])),
            SizedBox(height: 20),
            
            GestureDetector(
              onTap: _startListening,
              child: CircleAvatar(
                radius: 45,
                backgroundColor: _isListening ? Colors.redAccent : Colors.indigo,
                child: Icon(_isListening ? Icons.mic : Icons.mic_none, size: 40, color: Colors.white),
              ),
            ),
            SizedBox(height: 40),
            
            Text("Last Heard:\n\"$_lastWords\"", textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
