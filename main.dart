import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(MaterialApp(home: RizzieUniversalApp()));

class RizzieUniversalApp extends StatefulWidget {
  @override
  _RizzieUniversalAppState createState() => _RizzieUniversalAppState();
}

class _RizzieUniversalAppState extends State<RizzieUniversalApp> {
  stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts _tts = FlutterTts();
  bool _isListening = false;
  String _lastWords = "";
  
  // Dynamic Speaker State (Can be changed instantly on any phone)
  String _activeSpeaker = "Rishikesh";
  String _activeRelation = "Admin";
  final String _familyPassword = "rizzie2026family";

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
    final url = Uri.parse("https://rizzie-core.onrender.com/rizzie");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "password": _familyPassword,
          "speaker": "$_activeSpeaker ($_activeRelation)", // Dynamically sent based on who is holding the phone!
          "query": query,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String spokenReply = data["spoken_reply"] ?? "";
        String action = data["action"] ?? "NONE";
        String target = data["target"] ?? "";

        await _tts.speak(spokenReply);

        if (action == "PLAY_YOUTUBE") {
          final ytUrl = Uri.parse("https://www.youtube.com/results?search_query=$target");
          await launchUrl(ytUrl, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      await _tts.speak("Sorry, I couldn't reach the Rizzie server.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Rizzie - Family AI Companion")),
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
                  label: Text("Rishikesh (Admin)"),
                  selected: _activeSpeaker == "Rishikesh",
                  onSelected: (selected) {
                    setState(() { _activeSpeaker = "Rishikesh"; _activeRelation = "Admin"; });
                  },
                ),
                ChoiceChip(
                  label: Text("Mom"),
                  selected: _activeSpeaker == "Mom",
                  onSelected: (selected) {
                    setState(() { _activeSpeaker = "Mom"; _activeRelation = "Mother"; });
                  },
                ),
                ChoiceChip(
                  label: Text("Sister"),
                  selected: _activeSpeaker == "Sister",
                  onSelected: (selected) {
                    setState(() { _activeSpeaker = "Sister"; _activeRelation = "Sister"; });
                  },
                ),
              ],
            ),
            SizedBox(height: 40),
            Text(_isListening ? "Listening..." : "Tap mic to talk to Rizzie", style: TextStyle(fontSize: 18)),
            SizedBox(height: 30),
            FloatingActionButton.large(
              onPressed: _startListening,
              child: Icon(_isListening ? Icons.mic : Icons.mic_none, size: 36),
            ),
            SizedBox(height: 40),
            Text("Last Heard:\n\"$_lastWords\"", textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}