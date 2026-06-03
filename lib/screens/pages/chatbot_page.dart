import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shakti/services/map_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'mic_style.dart';
import 'voice_assisatnt_page.dart';
import 'ai_fake_call_screen.dart';

const Color _chatBackground = Color(0xFFF8FAFC);
const Color _chatSurface = Colors.white;
const Color _chatElevated = Color(0xFFEFF6FF);
const Color _chatBorder = Color(0xFFE2E8F0);
const Color _chatPrimaryText = Color(0xFF0F172A);
const Color _chatSecondaryText = Color(0xFF64748B);
const Color _chatAccent = Color(0xFF2563EB);
const Color _chatAccentDeep = Color(0xFF10B981);
const Color _chatUserBubble = Color(0xFF2563EB);

class ChatbotPage extends StatelessWidget {
  final Pharmacy? initialPharmacy;
  const ChatbotPage({super.key, this.initialPharmacy});

  @override
  Widget build(BuildContext context) => const ChatBotScreen();
}

class ChatBotScreen extends StatefulWidget {
  const ChatBotScreen({super.key});

  @override
  _ChatBotScreenState createState() => _ChatBotScreenState();
}

class _ChatBotScreenState extends State<ChatBotScreen>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  int? _currentChatIndex;
  List<ChatMessage> messages = [];
  List<List<ChatMessage>> previousChats = [];
  List<List<ChatMessage>> filteredChats = [];
  bool isTyping = false;
  bool isSearching = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // New animation controller for the sliding effect
  late AnimationController _drawerAnimationController;
  late Animation<double> _drawerSlideAnimation;

  FlutterTts flutterTts = FlutterTts();
  int? currentlySpeakingIndex;
  bool isTtsPlaying = false;
  bool _stopRequested = false;

  final String _serverUrl =
      'https://Samay-Verse-womenSafety-Backend-chatbot.hf.space/chat';

  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();

    // Initialize the new animation controller
    _drawerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // This will animate the body's horizontal position
    _drawerSlideAnimation = Tween<double>(
      begin: 0.0,
      end: 0.8, // The factor of the screen width to slide
    ).animate(CurvedAnimation(
      parent: _drawerAnimationController,
      curve: Curves.easeInOut,
    ));

    _loadAllChats();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    flutterTts.stop();
    _fadeController.dispose();
    _drawerAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.toLowerCase().trim();
      final wasSearching = isSearching;
      final newIsSearching = query.isNotEmpty;
      if (wasSearching != newIsSearching ||
          (newIsSearching &&
              (filteredChats.isEmpty ||
                  !_areChatsEqual(filteredChats, _getFilteredChats(query))))) {
        setState(() {
          isSearching = newIsSearching;
          if (query.isEmpty) {
            filteredChats = List.from(previousChats);
          } else {
            filteredChats = _getFilteredChats(query);
          }
        });
      }
    });
  }

  List<List<ChatMessage>> _getFilteredChats(String query) {
    return previousChats.where((chat) {
      return chat.any((message) => message.text.toLowerCase().contains(query));
    }).toList();
  }

  bool _areChatsEqual(
      List<List<ChatMessage>> chats1, List<List<ChatMessage>> chats2) {
    if (chats1.length != chats2.length) return false;
    for (int i = 0; i < chats1.length; i++) {
      if (chats1[i].length != chats2[i].length) return false;
      for (int j = 0; j < chats1[i].length; j++) {
        if (chats1[i][j].text != chats2[i][j].text ||
            chats1[i][j].isUser != chats2[i][j].isUser) {
          return false;
        }
      }
    }
    return true;
  }

  String _getSearchHighlightedTitle(List<ChatMessage> chat, String query) {
    if (query.isEmpty) {
      return chat.isNotEmpty
          ? (chat.first.isUser ? chat.first.text : 'Chat')
          : 'Chat';
    }
    for (ChatMessage message in chat) {
      if (message.text.toLowerCase().contains(query.toLowerCase())) {
        String text = message.text;
        if (text.length > 50) {
          text = '${text.substring(0, 50)}...';
        }
        return text;
      }
    }
    return chat.isNotEmpty
        ? (chat.first.isUser ? chat.first.text : 'Chat')
        : 'Chat';
  }

  String _buildSafetyPrompt(String text) {
    return '''
You are Shakti, an AI safety assistant for a women's safety mobile app.
Answer with calm, practical, concise guidance. If the user may be in danger,
prioritize immediate safety steps, moving to a public place, calling emergency
contacts, using SOS, fake call, evidence recording, and live location sharing.
Do not overclaim police/legal/medical certainty. Keep the answer useful for India.

User message: $text
''';
  }

  String _fallbackSafetyReply(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('follow') ||
        lower.contains('unsafe') ||
        lower.contains('danger') ||
        lower.contains('scared')) {
      return '''
I understand. Do this now:

1. Move toward a crowded, well-lit place.
2. Keep your phone unlocked and start live location sharing.
3. Tap SOS if the person keeps following you.
4. Start Evidence Mode if it is safe to record.
5. Call a trusted contact and say your exact location clearly.

If you are in immediate danger, call local emergency services now.
''';
    }
    if (lower.contains('route') || lower.contains('travel')) {
      return '''
For safer travel, choose the route with:

- better lighting
- more public movement
- nearby police station, hospital, petrol pump, or open shops
- fewer isolated turns

Avoid shortcuts through quiet lanes at night. Use the Safe Route screen and keep Guardian Mode active.
''';
    }
    if (lower.contains('sos') || lower.contains('emergency')) {
      return '''
Emergency mode should:

1. Lock your current location.
2. Notify emergency contacts.
3. Start evidence recording if safe.
4. Keep the fake call option ready.
5. Show nearby help points.

Use SOS immediately if you cannot safely talk.
''';
    }
    return '''
I am Shakti, your AI safety assistant. I can help with:

- safe route decisions
- SOS guidance
- fake call escape steps
- evidence recording advice
- emergency message drafting
- nearby help planning

Tell me what is happening or where you are going.
''';
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      messages.add(ChatMessage(text: text, isUser: true));
      isTyping = true;
      _stopRequested = false;
    });
    _messageController.clear();
    _scrollToBottom();
    await _saveCurrentChat();
    final startTime = DateTime.now();
    try {
      final response = await http
          .post(
            Uri.parse(_serverUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': _buildSafetyPrompt(text)}),
          )
          .timeout(const Duration(seconds: 20));
      final elapsed = DateTime.now().difference(startTime);
      const minTypingDuration = Duration(milliseconds: 800);
      if (elapsed < minTypingDuration) {
        await Future.delayed(minTypingDuration - elapsed);
      }
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        setState(() {
          messages.add(ChatMessage(
            text: data['reply'] ?? 'No response from server.',
            isUser: false,
          ));
          isTyping = false;
        });
      } else {
        setState(() {
          messages.add(ChatMessage(
            text: _fallbackSafetyReply(text),
            isUser: false,
          ));
          isTyping = false;
        });
      }
    } catch (e) {
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      setState(() {
        messages.add(ChatMessage(
          text: _fallbackSafetyReply(text),
          isUser: false,
        ));
        isTyping = false;
      });
    }
    _scrollToBottom();
    await _saveCurrentChat();
    // New logic to highlight the chat after the first message is sent
    if (_currentChatIndex == null) {
      setState(() {
        if (previousChats.isEmpty ||
            previousChats.last.first.text != messages.first.text) {
          previousChats.add(List<ChatMessage>.from(messages));
        }
        _currentChatIndex = previousChats.length - 1;
      });
    }
  }

  Future<void> _regenerateResponse(int botMsgIndex) async {
    int userMsgIndex = botMsgIndex - 1;
    while (userMsgIndex >= 0 && !messages[userMsgIndex].isUser) {
      userMsgIndex--;
    }
    if (userMsgIndex < 0) return;
    setState(() {
      messages.removeAt(botMsgIndex);
    });
    setState(() {
      isTyping = true;
      _stopRequested = false;
    });
    final userMsg = messages[userMsgIndex].text;
    try {
      final response = await http
          .post(
            Uri.parse(_serverUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': _buildSafetyPrompt(userMsg)}),
          )
          .timeout(const Duration(seconds: 20));
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        setState(() {
          messages.add(ChatMessage(
            text: data['reply'] ?? 'No response from server.',
            isUser: false,
            type: 'text',
          ));
          isTyping = false;
        });
      } else {
        setState(() {
          messages.add(ChatMessage(
            text: _fallbackSafetyReply(userMsg),
            isUser: false,
            type: 'text',
          ));
          isTyping = false;
        });
      }
    } catch (e) {
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      setState(() {
        messages.add(ChatMessage(
          text: _fallbackSafetyReply(userMsg),
          isUser: false,
          type: 'text',
        ));
        isTyping = false;
      });
    }
    _scrollToBottom();
    await _saveCurrentChat();
  }

  Future<void> _saveCurrentChat() async {
    final prefs = await SharedPreferences.getInstance();
    final chatJson = jsonEncode(messages.map((m) => m.toJson()).toList());
    await prefs.setString('current_chat', chatJson);
  }

  Future<void> _saveAllChats() async {
    final prefs = await SharedPreferences.getInstance();
    final allChatsJson = jsonEncode(previousChats
        .map((chat) => chat.map((m) => m.toJson()).toList())
        .toList());
    await prefs.setString('all_chats', allChatsJson);
  }

  Future<void> _loadCurrentChat() async {
    final prefs = await SharedPreferences.getInstance();
    final chatJson = prefs.getString('current_chat');
    if (chatJson != null) {
      final List<dynamic> decoded = jsonDecode(chatJson);
      setState(() {
        messages = decoded.map((e) => ChatMessage.fromJson(e)).toList();
      });
    }
  }

  Future<void> _loadAllChats() async {
    final prefs = await SharedPreferences.getInstance();
    final allChatsJson = prefs.getString('all_chats');
    if (allChatsJson != null) {
      final List<dynamic> decoded = jsonDecode(allChatsJson);
      setState(() {
        previousChats = decoded
            .map<List<ChatMessage>>((chat) =>
                (chat as List).map((e) => ChatMessage.fromJson(e)).toList())
            .toList();
        filteredChats = List.from(previousChats);
      });
    }
    await _loadCurrentChat();
  }

  void _startNewChat() async {
    if (messages.isNotEmpty) {
      previousChats.add(List<ChatMessage>.from(messages));
      await _saveAllChats();
    }
    setState(() {
      messages.clear();
      // _currentChatIndex = null; // Add this line
    });
    await _saveCurrentChat();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _chatBackground,
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: _chatBackground,
        elevation: 0,
        iconTheme: const IconThemeData(color: _chatPrimaryText),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () {
            // Open the drawer and start the slide animation
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _startNewChat,
            tooltip: 'New chat',
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: _chatBackground,
        width: MediaQuery.of(context).size.width * 0.90,
        child: _buildSideNavigation(),
      ),
      drawerEdgeDragWidth: MediaQuery.of(context).size.width,
      onDrawerChanged: (isOpened) {
        if (isOpened) {
          _drawerAnimationController.forward();
        } else {
          _drawerAnimationController.reverse();
        }
      },
      body: AnimatedBuilder(
        animation: _drawerAnimationController,
        builder: (context, child) {
          final double slide =
              MediaQuery.of(context).size.width * _drawerSlideAnimation.value;
          final double scale = 1.0 -
              (_drawerSlideAnimation.value * 0.2); // Optional scaling effect
          final double borderRadius = _drawerAnimationController.value * 24;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(slide)
              ..scale(scale),
            child: GestureDetector(
              onTap: () {
                if (_scaffoldKey.currentState!.isDrawerOpen) {
                  Navigator.pop(context);
                }
              },
              onHorizontalDragUpdate: (details) {
                if (!_scaffoldKey.currentState!.isDrawerOpen) {
                  _drawerAnimationController.value += details.primaryDelta! /
                      (MediaQuery.of(context).size.width * 0.90);
                }
              },
              onHorizontalDragEnd: (details) {
                if (_drawerAnimationController.value > 0.5) {
                  _scaffoldKey.currentState!.openDrawer();
                } else {
                  _drawerAnimationController.reverse();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: AbsorbPointer(
                  absorbing: _scaffoldKey.currentState!.isDrawerOpen,
                  child: Stack(
                    children: [
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                color: _chatBackground,
                                child: messages.isEmpty
                                    ? _buildShaktiEmptyState()
                                    : _buildMessagesList(),
                              ),
                            ),
                            _buildMessageInput(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShaktiEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _chatBorder),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.shield_rounded,
                    size: 42,
                    color: _chatAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'How can I help you stay safe?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _chatPrimaryText,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask about SOS, safer routes, evidence, fake call, or emergency messages.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _chatSecondaryText,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 34),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionButton(Icons.sos_rounded, 'Emergency help'),
                _buildSuggestionButton(Icons.route_rounded, 'Safer route'),
                _buildSuggestionButton(Icons.videocam_rounded, 'Evidence tips'),
                _buildSuggestionButton(Icons.call_rounded, 'Emergency text'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() => _buildShaktiEmptyState();

  Widget _buildMessagesList() {
    return Container(
      color: _chatBackground,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: messages.length + (isTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length && isTyping) {
            return _buildTypingIndicator();
          }
          return _buildMessageBubble(messages[index]);
        },
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _chatSurface,
              border: Border.all(color: _chatBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_chatAccent),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Shakti is typing...',
                  style: TextStyle(
                    color: _chatSecondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    bool isBot = !message.isUser;
    final markdownStyleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(color: message.isUser ? Colors.white : _chatPrimaryText, fontSize: 16),
      strong: TextStyle(color: message.isUser ? Colors.white : _chatPrimaryText, fontWeight: FontWeight.bold),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot) ...[
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _chatElevated,
                shape: BoxShape.circle,
                border: Border.all(color: _chatBorder),
              ),
              child: Image.asset(
                'assets/logo.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.shield_rounded,
                  size: 20,
                  color: _chatAccent,
                ),
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser ? _chatUserBubble : _chatSurface,
                border: message.isUser ? null : Border.all(color: _chatBorder),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: message.isUser ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: message.isUser ? const Radius.circular(4) : const Radius.circular(16),
                ),
                boxShadow: message.isUser
                    ? [
                        BoxShadow(
                          color: _chatUserBubble.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (message.type == 'image' && message.data != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          Uint8List.fromList(message.data!),
                          width: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  if (message.type == 'file')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.insert_drive_file, color: message.isUser ? Colors.white : _chatAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              message.text,
                              style: TextStyle(
                                color: message.isUser ? Colors.white : _chatPrimaryText,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.text,
                      styleSheet: markdownStyleSheet,
                      selectable: true,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: message.isUser ? Colors.white.withOpacity(0.7) : _chatSecondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final isInputNotEmpty = _messageController.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _chatSurface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: _chatBorder),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            _inputCircleButton(
              icon: Icons.add_rounded,
              color: _chatPrimaryText,
              background: const Color(0xFFF8FAFC),
              onTap: _onAddPressed,
              tooltip: 'Attach',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: _chatPrimaryText, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Ask Shakti',
                  hintStyle: TextStyle(
                    color: _chatSecondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _sendMessage,
                minLines: 1,
                maxLines: 5,
                enabled: !isTyping,
              ),
            ),
            const SizedBox(width: 8),
            if (isTyping)
              _inputCircleButton(
                icon: Icons.stop_rounded,
                color: Colors.white,
                background: const Color(0xFFE11D48),
                onTap: () {
                  setState(() {
                    _stopRequested = true;
                    isTyping = false;
                  });
                },
                tooltip: 'Stop',
              )
            else if (isInputNotEmpty)
              _inputCircleButton(
                icon: Icons.arrow_upward_rounded,
                color: Colors.white,
                background: _chatAccent,
                onTap: () => _sendMessage(_messageController.text),
                tooltip: 'Send',
              )
            else ...[
              _inputCircleButton(
                icon: Icons.mic_none_rounded,
                color: _chatAccent,
                background: const Color(0xFFEFF6FF),
                onTap: _onMicPressed,
                tooltip: 'Voice input',
              ),
              const SizedBox(width: 6),
              _inputCircleButton(
                icon: Icons.graphic_eq_rounded,
                color: Colors.white,
                background: _chatAccentDeep,
                onTap: _onVoiceAssistantPressed,
                tooltip: 'Voice assistant',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inputCircleButton({
    required IconData icon,
    required Color color,
    required Color background,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  void _onAddPressed() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _chatSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Draggable handle
                Center(
                  child: Container(
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: _chatBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildOptionTile(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage();
                  },
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'File',
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _chatElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _chatBorder),
              ),
              child: Icon(
                icon,
                size: 24,
                color: _chatAccent,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _chatPrimaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _chatElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _chatBorder),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: _chatAccent,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: _chatPrimaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final fileBytes = await pickedFile.readAsBytes();
      final chatMessage = ChatMessage(
        text: "User uploaded an image.",
        isUser: true,
        type: 'image',
        filePath: pickedFile.path,
        data: fileBytes,
      );
      setState(() {
        messages.add(chatMessage);
      });
      _scrollToBottom();
      _sendMessageWithFile(chatMessage);
    }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
    );
    if (result != null) {
      final fileBytes = await File(result.files.single.path!).readAsBytes();
      final chatMessage = ChatMessage(
        text: "User uploaded a file: ${result.files.single.name}",
        isUser: true,
        type: 'file',
        filePath: result.files.single.path,
        data: fileBytes,
      );
      setState(() {
        messages.add(chatMessage);
      });
      _scrollToBottom();
      _sendMessageWithFile(chatMessage);
    }
  }

  Future<void> _sendMessageWithFile(ChatMessage message) async {
    if (message.data == null) return;
    setState(() {
      isTyping = true;
      _stopRequested = false;
    });
    _scrollToBottom();
    await _saveCurrentChat();
    final startTime = DateTime.now();

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_serverUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'file', // Field name for the file on your backend
        message.data!,
        filename: message.filePath!.split('/').last,
        contentType: message.type == 'image'
            ? MediaType('image', 'jpeg')
            : MediaType('application', 'octet-stream'),
      ));
      request.fields['message'] = message.text; // Add the message text

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 40));
      final response = await http.Response.fromStream(streamedResponse);

      // ... rest of your response handling logic from _sendMessage
      final elapsed = DateTime.now().difference(startTime);
      const minTypingDuration = Duration(milliseconds: 800);
      if (elapsed < minTypingDuration) {
        await Future.delayed(minTypingDuration - elapsed);
      }
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        setState(() {
          messages.add(ChatMessage(
            text: data['reply'] ?? 'No response from server.',
            isUser: false,
            type: 'text',
          ));
          isTyping = false;
        });
      } else {
        setState(() {
          messages.add(ChatMessage(
            text: _fallbackSafetyReply(message.text),
            isUser: false,
            type: 'text',
          ));
          isTyping = false;
        });
      }
    } catch (e) {
      // ... your existing error handling
      if (_stopRequested) {
        setState(() => isTyping = false);
        return;
      }
      setState(() {
        messages.add(ChatMessage(
          text: _fallbackSafetyReply(message.text),
          isUser: false,
          type: 'text',
        ));
        isTyping = false;
      });
    }
    _scrollToBottom();
    await _saveCurrentChat();
  }

  void _onMicPressed() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return MicStylePopup(
          onSpeechRecognized: (String text) {
            if (text.isNotEmpty) {
              _messageController.text = text;
              _sendMessage(text);
            }
          },
        );
      },
    );
  }

  void _onVoiceAssistantPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AIAssistantScreen()),
    );
  }

  Widget _buildSideNavigation() {
    return Drawer(
      backgroundColor: _chatBackground,
      width: MediaQuery.of(context).size.width * 0.90,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _chatSurface,
                border: Border(
                  bottom: BorderSide(
                    color: _chatBorder,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _chatElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _chatBorder),
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      height: 32,
                      width: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.chat_bubble_outline,
                        size: 24,
                        color: _chatAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shakti',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _chatPrimaryText,
                          ),
                        ),
                        Text(
                          'AI Safety Assistant',
                          style: TextStyle(
                            fontSize: 12,
                            color: _chatSecondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: _chatElevated,
                    child: Icon(Icons.person, color: _chatAccent),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InkWell(
                onTap: () {
                  _startNewChat();
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _chatElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _chatBorder),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 20, color: _chatAccent),
                      SizedBox(width: 12),
                      Text(
                        'New chat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _chatPrimaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.history,
                              color: _chatAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Recent Chats',
                            style: const TextStyle(
                              color: _chatAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${previousChats.length} chats',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: previousChats.isEmpty
                          ? _buildEmptyHistoryState()
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.only(top: 8),
                              itemCount: previousChats.length,
                              itemBuilder: (context, idx) {
                                final chat = previousChats[idx];
                                final title = chat.isNotEmpty
                                    ? (chat.first.isUser
                                        ? chat.first.text
                                        : 'Chat')
                                    : 'Chat';
                                final time = chat.isNotEmpty
                                    ? _formatTime(chat.first.timestamp)
                                    : '';
                                return _buildConversationItem(title, time, idx);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Resources',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _chatPrimaryText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildResourceBox('Safety Tips', Icons.security),
                        _buildResourceBox('Emergency Help', Icons.warning),
                        _buildResourceBox('Legal Support', Icons.gavel),
                        _buildResourceBox('Support Groups', Icons.group),
                        _buildResourceBox('Self Defense', Icons.shield),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationItem(String title, String time, int idx) {
    final isSelected = _currentChatIndex == idx;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? _chatElevated : Colors.transparent,
        border: Border.all(
          color: isSelected ? _chatBorder : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            setState(() {
              messages = List<ChatMessage>.from(previousChats[idx]);
              _currentChatIndex = idx; // Add this line
            });
            await _saveCurrentChat();
            Navigator.pop(context);
          },
          onLongPress: () => _showDeleteChatDialog(idx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.length > 30
                            ? '${title.substring(0, 30)}...'
                            : title,
                        style: const TextStyle(
                          color: _chatPrimaryText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        time,
                        style: TextStyle(
                          color: _chatSecondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteChatDialog(int idx) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Chat'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete this chat? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteChat(idx);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _deleteChat(int idx) {
    try {
      setState(() {
        if (isSearching) {
          if (idx >= 0 && idx < filteredChats.length) {
            final chatToDelete = filteredChats[idx];
            final originalIndex = previousChats.indexOf(chatToDelete);
            if (originalIndex != -1) {
              previousChats.removeAt(originalIndex);
            }
            filteredChats.removeAt(idx);
          }
        } else {
          if (idx >= 0 && idx < previousChats.length) {
            previousChats.removeAt(idx);
          }
        }
      });
      if (isSearching) {
        final query = _searchController.text.toLowerCase().trim();
        if (query.isEmpty) {
          filteredChats = List.from(previousChats);
        } else {
          filteredChats = previousChats.where((chat) {
            return chat
                .any((message) => message.text.toLowerCase().contains(query));
          }).toList();
        }
      }
      _saveAllChats();
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text('Chat deleted successfully'),
      //     backgroundColor: Colors.green,
      //   ),
      // );
    } catch (e) {
      print('Error deleting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error deleting chat. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildResourceBox(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        _sendMessage(label);
        Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _chatElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _chatBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: _chatAccent),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: _chatPrimaryText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return "Today, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } else {
      return "${dt.day}/${dt.month}/${dt.year}";
    }
  }

  Widget _buildEmptyHistoryState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          const Text(
            'No chat history',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Start a conversation with Shakti to see your chat history here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_sweep, color: Colors.red),
              SizedBox(width: 8),
              Text('Clear All Chats'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete all chat history? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                // Navigator.of(context).pop();
                // _clearAllChats();
              },
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteMessageDialog(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Message'),
            ],
          ),
          content: const Text(
            'Are you sure you want to delete this message? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteMessage(index);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _deleteMessage(int index) {
    try {
      if (index >= 0 && index < messages.length) {
        setState(() {
          messages.removeAt(index);
        });
        _saveCurrentChat();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error deleting message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error deleting message. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSuggestionButton(IconData icon, String text) {
    return ActionChip(
      avatar: Icon(icon, color: _chatAccent, size: 18),
      label: Text(
        text,
        style: const TextStyle(
          color: _chatPrimaryText,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      backgroundColor: Colors.white,
      side: const BorderSide(color: _chatBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      onPressed: () => _sendMessage(text),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? filePath;
  final String? type;
  final List<int>? data; // Add this line

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.filePath,
    this.type = 'text',
    this.data, // Add this line
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'filePath': filePath,
        'type': type,
        'data': data, // Add this line
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'],
        isUser: json['isUser'],
        timestamp: DateTime.parse(json['timestamp']),
        filePath: json['filePath'],
        type: json['type'],
        data: (json['data'] as List?)?.cast<int>(), // Add this line
      );
}
