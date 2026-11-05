import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:quick_actions/quick_actions.dart';

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
  final QuickActions quickActions = const QuickActions();
  
  bool _isListening = false;
  String _appState = "Checking Permissions..."; 
  String _lastWords = "Tap the mic to wake Rizzie...";
  
  String _activeSpeaker = "Auto"; // Default to AI Inference
  String _activeRelation = "Unknown";
  String _listenLocale = "en_IN"; // Default to Tanglish (Indian English)
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
    _requestPermissions();
    _setupShortcuts();
  }

  void _setupShortcuts() {
    quickActions.initialize((String shortcutType) {
      if (shortcutType == 'action_listen') {
        _startListening();
      }
    });
    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
        type: 'action_listen',
        localizedTitle: 'Wake Rizzie',
        icon: 'ic_launcher'
      ),
    ]);
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.phone,
    ].request();

    if (statuses[Permission.microphone]!.isGranted) {
      _initSpeech();
    } else {
      setState(() => _appState = "Microphone Denied");
    }
  }

  void _initSpeech() async {
    bool available = await _speech.initialize(
      onError: (val) => setState(() {
        _appState = "Mic Error";
        _isListening = false;
      }),
    );
    if (available) {
      setState(() => _appState = "Ready");
      // Optional: Auto-listen on app open
      // _startListening(); 
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
        _appState = "Listening...";
        _lastWords = "";
      });
      // localeId forces the recognizer to expect specific languages
      _speech.listen(
        localeId: _listenLocale,
        onResult: (val) {
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
          "speaker": _activeSpeaker == "Auto" ? "Auto" : "$_activeSpeaker ($_activeRelation)", 
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
          }
        } else {
           setState(() => _appState = "Ready");
        }

        // 2. Action Routing Execution
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
        else if (action == "MAKE_CALL") {
          // Removes spaces/dashes and dials
          final callUrl = Uri.parse("tel:${target.replaceAll(RegExp(r'[^0-9+]'), '')}");
          if (await canLaunchUrl(callUrl)) {
            await launchUrl(callUrl);
          }
        }
        else if (action == "NAVIGATE_MAPS") {
          // Triggers native Google Maps navigation
          final mapUrl = Uri.parse("google.navigation:q=$target");
          if (await canLaunchUrl(mapUrl)) {
            await launchUrl(mapUrl, mode: LaunchMode.externalApplication);
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF).withOpacity(0.2) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
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
        actions: [
          // Tanglish / Tamil Toggle
          TextButton(
            onPressed: () {
              setState(() {
                _listenLocale = _listenLocale == "en_IN" ? "ta_IN" : "en_IN";
              });
            },
            child: Text(
              _listenLocale == "en_IN" ? "TANGLISH" : "TAMIL",
              style: const TextStyle(color: Color(0xFF03DAC6), fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              const Text(
                "ACTIVE PROFILE",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSpeakerCard("Auto", "Inference"),
                    const SizedBox(width: 8),
                    _buildSpeakerCard("Rishikesh", "Admin"),
                    const SizedBox(width: 8),
                    _buildSpeakerCard("Mom", "Mother"),
                    const SizedBox(width: 8),
                    _buildSpeakerCard("Sister", "Sister"),
                  ],
                ),
              ),
              
              const Spacer(),
              
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
