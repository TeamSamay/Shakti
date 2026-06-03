import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:url_launcher/url_launcher.dart';

class OverlayBubbleApp extends StatelessWidget {
  const OverlayBubbleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayBubble(),
    );
  }
}

class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});

  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  Future<void> _callEmergency() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 92,
        height: 92,
        padding: const EdgeInsets.all(8),
        child: _buildBubble(),
      ),
    );
  }

  Widget _buildBubble() {
    return GestureDetector(
      onTap: _callEmergency,
      onLongPress: _closeOverlay,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.sos_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }
}
