import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:external_app_launcher/external_app_launcher.dart';

void main() => runApp(MaterialApp(
  home: RizzieUniversalApp(), 
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark().copyWith(
    scaffoldBackgroundColor: const Color(0xFF121212),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF6C63FF),
      secondary: Color(0xFF03DAC6),
    ),
  ),
));

class RizzieUniversalApp extends StatefulWidget {
  @override
  _RizzieUniversalAppState createState() => _RizzieUniversalAppState();
}

class _RizzieUniversalAppState extends State<RizzieUniversalApp> {
  stt.SpeechToText _speech = stt.SpeechToText();
  AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isListening = false;
  String _appState = "Ready"; // Ready, Listening, Thinking, Speaking
  String _lastWords = "Tap the mic to wake Rizzie...";
  
  String _activeSpeaker = "Rishikesh";
  String _activeRelation = "Admin";
  final String _familyPassword = "rizzie2026family";

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
    _initSpeech();
  }

  void _initSpeech() async {
    await _speech.initialize(
      onError: (val) => setState(() {
        _appState = "Mic Error: Check Permissions";
        _isListening = false;
      }),
    );
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
        _appState = "Listening...";
        _lastWords = "";
      });
      _speech.listen(onResult: (val) {
        setState(() => _lastWords = val.recognizedWords);
        if (val.finalResult) {
          _speech.stop();
          setState(() {
            _isListening = false;
            _appState = "Thinking...";
          });
          if (_lastWords.isNotEmpty) {
            _sendToRizzieCore(_lastWords);
          }
        }
      });
    } else {
      setState(() {
        _appState = "Microphone Denied";
        _isListening = false;
      });
    }
  }

  Future<void> _sendToRizzieCore(String query) async {
    final String backendUrl = "https://rizzie-core.onrender.com"; 
    
    try {
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

        // 1. Play Audio Response
        if (spokenReply.isNotEmpty) {
          setState(() => _appState = "Speaking...");
          final audioResponse = await http.post(
            Uri.parse("$backendUrl/speak"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"text": spokenReply}),
          );

          if (audioResponse.statusCode == 200) {
            await _audioPlayer.play(BytesSource(audioResponse.bodyBytes));
            _audioPlayer.onPlayerComplete.listen((event) {
              setState(() => _appState = "Ready");
            });
          } else {
             setState(() => _appState = "Voice Engine Error");
          }
        } else {
           setState(() => _appState = "Ready");
        }

        // 2. Action Routing (Including new WhatsApp logic)
        if (action == "PLAY_YOUTUBE") {
          final ytUrl = Uri.parse("https://www.youtube.com/results?search_query=$target");
          await launchUrl(ytUrl, mode: LaunchMode.externalApplication);
        } 
        else if (action == "OPEN_APP") {
          String cleanTarget = target.toLowerCase().trim();
          String? packageName = appPackages[cleanTarget];
          if (packageName != null) {
            await LaunchApp.openApp(androidPackageName: packageName);
          }
        }
        else if (action == "SEND_WHATSAPP") {
          final whatsappUrl = Uri.parse("whatsapp://send?text=Hey $target");
          if (await canLaunchUrl(whatsappUrl)) {
            await launchUrl(whatsappUrl);
          } else {
            await LaunchApp.openApp(androidPackageName: "com.whatsapp");
          }
        }
      }
    } catch (e) {
      setState(() => _appState = "Server Connection Failed");
    }
  }

  Widget _buildSpeakerCard(String name, String relation) {
    bool isSelected = _activeSpeaker == name;
    return GestureDetector(
      onTap: () => setState(() {
        _activeSpeaker = name;
        _activeRelation = relation;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF).withOpacity(0.2) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
          ] : [],
        ),
        child: Text(
          name,
          style: TextStyle(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Rizzie", style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              const Text(
                "Active Profile",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13, letterSpacing: 1.5, uppercase: true),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSpeakerCard("Rishikesh", "Admin"),
                  const SizedBox(width: 10),
                  _buildSpeakerCard("Mom", "Mother"),
                  const SizedBox(width: 10),
                  _buildSpeakerCard("Sister", "Sister"),
                ],
              ),
              
              const Spacer(),
              
              // Chat Bubble
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _lastWords,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16, 
                    height: 1.5,
                    color: _lastWords.contains("mic to wake") ? Colors.grey : Colors.white,
                    fontStyle: _lastWords.contains("mic to wake") ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              
              Text(
                _appState.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _appState.contains("Error") || _appState.contains("Failed") || _appState.contains("Denied") 
                      ? Colors.redAccent 
                      : const Color(0xFF03DAC6),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Mic Button
              Center(
                child: GestureDetector(
                  onTap: _isListening ? null : _startListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: _isListening ? 100 : 80,
                    width: _isListening ? 100 : 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isListening ? Colors.redAccent.withOpacity(0.8) : const Color(0xFF6C63FF),
                      boxShadow: [
                        BoxShadow(
                          color: _isListening ? Colors.redAccent.withOpacity(0.4) : const Color(0xFF6C63FF).withOpacity(0.4),
                          blurRadius: _isListening ? 25 : 15,
                          spreadRadius: _isListening ? 5 : 2,
                        )
                      ]
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: _isListening ? 40 : 32,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
