import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EmergencyTriggerButton extends StatefulWidget {
  const EmergencyTriggerButton({
    super.key,
    this.onEmergencyTriggered,
    this.size = 56,
  });

  final VoidCallback? onEmergencyTriggered;
  final double size;

  @override
  State<EmergencyTriggerButton> createState() => _EmergencyTriggerButtonState();
}

class _EmergencyTriggerButtonState extends State<EmergencyTriggerButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 15.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _showEmergencyPopup();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTrigger() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isAnimating = true;
    });
    _animationController.forward();
  }

  void _showEmergencyPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmergencyCountdownDialog(
        onEmergencyTriggered: widget.onEmergencyTriggered,
      ),
    ).then((_) {
      // Reset animation when dialog closes
      setState(() {
        _isAnimating = false;
      });
      _animationController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_isAnimating)
          AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withOpacity(0.72),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        Material(
          color: const Color(0xFFDC2626),
          shape: const CircleBorder(),
          elevation: _isAnimating ? 0 : 10,
          shadowColor: const Color(0xFFDC2626).withOpacity(0.38),
          child: InkWell(
            onTap: _onTrigger,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: const Icon(
                Icons.sos_rounded,
                color: Colors.white,
                size: 27,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class EmergencyCountdownDialog extends StatefulWidget {
  const EmergencyCountdownDialog({super.key, this.onEmergencyTriggered});

  final VoidCallback? onEmergencyTriggered;

  @override
  State<EmergencyCountdownDialog> createState() =>
      _EmergencyCountdownDialogState();
}

class _EmergencyCountdownDialogState extends State<EmergencyCountdownDialog> {
  int _countdown = 5;
  Timer? _timer;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
        HapticFeedback.mediumImpact();
      } else {
        _timer?.cancel();
        _triggerEmergency();
      }
    });
  }

  void _triggerEmergency() {
    setState(() {
      _triggered = true;
    });
    HapticFeedback.heavyImpact();
    widget.onEmergencyTriggered?.call();
    // In a real app, this would start the camera and audio recording services.
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_triggered) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDC2626).withOpacity(0.22),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF1E8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: Color(0xFFDC2626),
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Emergency Tracking Active',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Live location is being shared. Audio, camera, and safety agent are standing by.',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatusIndicator(
                    Icons.mic,
                    'Audio',
                    const Color(0xFFDC2626),
                  ),
                  _buildStatusIndicator(
                    Icons.videocam,
                    'Camera',
                    const Color(0xFFDC2626),
                  ),
                  _buildStatusIndicator(
                    Icons.location_on,
                    'Location',
                    const Color(0xFFDC2626),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  foregroundColor: const Color(0xFF111827),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Cancel Tracking'),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withOpacity(0.42),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Starting\nEmergency Tracking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Location sharing, camera, and audio protection will activate automatically.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                _timer?.cancel();
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(IconData icon, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
