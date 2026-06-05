import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class AIFakeCallScreen extends StatefulWidget {
  const AIFakeCallScreen({super.key});

  @override
  State<AIFakeCallScreen> createState() => _AIFakeCallScreenState();
}

class _AIFakeCallScreenState extends State<AIFakeCallScreen>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isResponding = false;
  bool _isMuted = false;
  bool _isSpeaker = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final String _serverUrl =
      'https://samay-verse-womensafety-backend-chatbot.hf.space/chat';

  List<String> _sentencesToSpeak = [];
  int _currentSentenceIndex = 0;
  String _currentSpokenText = "Connecting to Shakti AI...";
  
  int _callDurationSeconds = 0;
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startCallTimer();
    _initTts();

    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _currentSpokenText = "I am listening. How can I help you?";
      });
      _startListening();
    });
  }
  
  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDurationSeconds++;
        });
      }
    });
  }

  void _initTts() async {
    await _tts.setLanguage('en-IN');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _isResponding = true);
    });

    _tts.setCompletionHandler(() {
      _currentSentenceIndex++;
      if (_currentSentenceIndex < _sentencesToSpeak.length) {
        _speakResponse();
      } else {
        if (mounted) {
          setState(() {
            _isResponding = false;
            _currentSpokenText = "Listening...";
          });
          _startListening();
        }
      }
    });

    _tts.setErrorHandler((msg) {
      if (mounted) {
        setState(() {
          _isResponding = false;
        });
        _startListening();
      }
    });
  }

  void _startListening() async {
    if (!_isListening && !_isProcessing && mounted && !_isMuted) {
      bool available = await _speech.initialize(
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && !_isMuted) _startListening();
          });
        },
      );

      if (available && mounted) {
        setState(() {
          _isListening = true;
          _currentSpokenText = "Listening...";
        });

        _speech.listen(
          onResult: (result) {
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              _processVoiceCommand(result.recognizedWords);
              _stopListening();
            }
          },
          partialResults: false,
          localeId: 'en_IN',
          cancelOnError: false,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        );
      }
    }
  }

  void _stopListening() {
    if (_isListening) {
      _speech.stop();
      if (mounted) setState(() => _isListening = false);
    }
  }

  void _processVoiceCommand(String command) async {
    if (command.trim().isEmpty) {
      if (mounted) _startListening();
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _isListening = false;
        _currentSpokenText = "Thinking...";
      });
    }

    try {
      final response = await http
          .post(
            Uri.parse(_serverUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': _buildSafetyPrompt(command)}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && mounted) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        final reply = data['reply'] ?? 'I apologize, but I couldn\'t process that request.';

        _sentencesToSpeak = _splitIntoSentences(reply);
        _currentSentenceIndex = 0;

        setState(() {
          _isProcessing = false;
          _currentSpokenText = reply;
        });

        _speakResponse();
      } else {
        _handleFallback(command);
      }
    } catch (e) {
      _handleFallback(command);
    }
  }
  
  void _handleFallback(String command) {
    if (!mounted) return;
    final reply = _fallbackVoiceReply(command);
    _sentencesToSpeak = _splitIntoSentences(reply);
    _currentSentenceIndex = 0;
    setState(() {
      _isProcessing = false;
      _currentSpokenText = reply;
    });
    _speakResponse();
  }

  Future<void> _speakResponse() async {
    if (_currentSentenceIndex < _sentencesToSpeak.length && mounted) {
      final sentence = _sentencesToSpeak[_currentSentenceIndex].trim();
      if (sentence.isNotEmpty) {
        await _tts.speak(sentence);
      } else {
        _currentSentenceIndex++;
        _speakResponse();
      }
    }
  }

  List<String> _splitIntoSentences(String text) {
    return text.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.isNotEmpty).toList();
  }

  String _buildSafetyPrompt(String command) {
    return '''
You are Shakti, an AI voice safety assistant. Keep your answer brief, conversational, and helpful like a phone call.
User said: $command
''';
  }

  String _fallbackVoiceReply(String command) {
    return 'I am here with you. Please stay on the line and head to a safe, crowded area.';
  }

  void _endCall() {
    _callTimer?.cancel();
    _stopListening();
    _tts.stop();
    Navigator.pop(context);
  }
  
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _stopListening();
        _currentSpokenText = "Microphone muted";
      } else {
        _startListening();
      }
    });
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _speech.stop();
    _tts.stop();
    _pulseController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = _isListening || _isProcessing || _isResponding;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark mode for phone call UI
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Caller Info
            const Text(
              'Shakti AI Agent',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formattedTime,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 18,
              ),
            ),
            const Spacer(),
            
            // Avatar / Animation
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: isActive && !_isMuted ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                      ),
                      boxShadow: [
                        if (isActive && !_isMuted)
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withOpacity(0.5),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 60),
            
            // Subtitles / Spoken Text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _currentSpokenText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            
            const Spacer(),
            
            // Call Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildControlButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        label: 'Mute',
                        isActive: _isMuted,
                        onTap: _toggleMute,
                      ),
                      _buildControlButton(
                        icon: Icons.dialpad,
                        label: 'Keypad',
                        isActive: false,
                        onTap: () {},
                      ),
                      _buildControlButton(
                        icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
                        label: 'Speaker',
                        isActive: _isSpeaker,
                        onTap: () {
                          setState(() => _isSpeaker = !_isSpeaker);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : const Color(0xFF334155),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF0F172A) : Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
