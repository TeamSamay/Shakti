import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'chatbot_page.dart';

class AIAssistantScreen extends StatefulWidget {
  const AIAssistantScreen({super.key});

  @override
  _AIAssistantScreenState createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen>
    with TickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _isListening = false;
  bool _isProcessing = false;

  String _displayText = "How can I help you today?";

  late AnimationController _rotationController;
  late AnimationController _pulseController;

  final String _serverUrl =
      'https://samay-verse-womensafety-backend-chatbot.hf.space/chat';

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _initTts();

    Future.delayed(const Duration(milliseconds: 500), () {
      _startListening();
    });
  }

  void _initTts() async {
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setCompletionHandler(() {
      _startListening();
    });

    _tts.setErrorHandler((msg) {
      _startListening();
    });
  }

  void _startListening() async {
    if (!_isListening && !_isProcessing) {
      setState(() {
        _displayText = "Listening...";
      });
      bool available = await _speech.initialize(
        onError: (error) {
          setState(() {
            _isListening = false;
            _displayText =
                "Unable to start voice recognition. Please try again.";
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) _startListening();
          });
        },
      );

      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (result) {
            setState(() {
              _displayText = result.recognizedWords.isNotEmpty
                  ? result.recognizedWords
                  : "Listening...";
            });
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              _processVoiceCommand(result.recognizedWords);
              _stopListening();
            }
          },
          listenOptions: stt.SpeechListenOptions(
            partialResults: true,
            cancelOnError: false,
            listenFor: const Duration(seconds: 30),
            pauseFor: const Duration(seconds: 3),
          ),
          localeId: 'en_IN',
        );
      } else {
        setState(() {
          _displayText = "Microphone access denied or unavailable.";
        });
      }
    }
  }

  void _stopListening() {
    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    }
  }

  String _buildSafetyPrompt(String command) {
    return '''
You are Shakti, an AI voice safety assistant for a women's safety mobile app.
Reply briefly, clearly, and in a conversational style. Keep it very short, 1 or 2 sentences max.

User voice command: $command
''';
  }

  void _processVoiceCommand(String command) async {
    if (command.trim().isEmpty) {
      _startListening();
      return;
    }

    setState(() {
      _isProcessing = true;
      _isListening = false;
    });

    try {
      final response = await http
          .post(
            Uri.parse(_serverUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': _buildSafetyPrompt(command)}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        final reply = data['reply'] ??
            'I apologize, but I couldn\'t process that request.';

        setState(() {
          _isProcessing = false;
          _displayText = reply;
        });

        await _tts.speak(reply);
      } else {
        setState(() {
          _isProcessing = false;
          _displayText = "Connection error. Trying to recover...";
        });
        await _tts.speak("I couldn't reach the server.");
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _displayText = "Error connecting to AI.";
      });
      await _tts.speak("Error connecting to AI.");
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine colors based on theme if required, but default to dark for the glow effect
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // We will use a very dark background even in light theme to ensure glowing works,
    // or slightly adapt it. The user requested to use the background animation in light theme too.
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFF1A1A1A);
    final iconBgColor = Colors.black.withOpacity(0.4);
    final iconColor = Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Background Animation
          AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Stack(
                children: [
                  // Green Glow
                  Positioned(
                    top: -150 +
                        math.sin(_rotationController.value * 2 * math.pi) * 40,
                    left: -100 +
                        math.cos(_rotationController.value * 2 * math.pi) * 40,
                    child: Container(
                      width: 500,
                      height: 500,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green.withOpacity(isDark ? 0.4 : 0.6),
                      ),
                    ),
                  ),
                  // White Glow
                  Positioned(
                    bottom: -100 +
                        math.cos(_rotationController.value * 2 * math.pi) * 30,
                    right: -50 +
                        math.sin(_rotationController.value * 2 * math.pi) * 30,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(isDark ? 0.15 : 0.25),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Blur Layer over background blobs
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
            child: Container(color: Colors.transparent),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Hamburger Menu
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const ChatbotPage()),
                          );
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: iconBgColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.menu, color: iconColor, size: 24),
                        ),
                      ),
                      // Options Pill
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          // Handle selection
                        },
                        color: iconBgColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        offset: const Offset(0, 50),
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'lang',
                            child: ListTile(
                              leading:
                                  Icon(Icons.language, color: Colors.white),
                              title: Text('Change Language',
                                  style: TextStyle(color: Colors.white)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'voice',
                            child: ListTile(
                              leading: Icon(Icons.record_voice_over,
                                  color: Colors.white),
                              title: Text('Change Voice Type',
                                  style: TextStyle(color: Colors.white)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: iconBgColor,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.web_asset, color: iconColor, size: 20),
                              const SizedBox(width: 12),
                              Icon(Icons.more_horiz,
                                  color: iconColor, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Transcript Text Box
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _displayText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // Bottom Bar
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 30, left: 20, right: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Camera
                      _buildIconButton(
                          Icons.videocam_outlined, iconBgColor, iconColor),
                      // Upload
                      _buildIconButton(
                          Icons.upload_outlined, iconBgColor, iconColor),

                      // Mic
                      _buildIconButton(
                          Icons.mic_none,
                          _isListening
                              ? Colors.white.withOpacity(0.3)
                              : iconBgColor,
                          iconColor, onTap: () {
                        if (_isListening) {
                          _stopListening();
                        } else {
                          _startListening();
                        }
                      }),
                      // Close
                      _buildIconButton(Icons.close, iconBgColor, iconColor,
                          onTap: () {
                        Navigator.pop(context);
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, Color bgColor, Color iconColor,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 24,
        ),
      ),
    );
  }
}
