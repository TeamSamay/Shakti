import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'overlay_bubble.dart';
import 'services/guardian_overlay_service.dart';
import 'screens/welcome_screen.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayBubbleApp());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(
      "pk.eyJ1Ijoic2FtYXkwMSIsImEiOiJjbW4xeWJpcDExMW1sMnJzZmFyeGljZTU3In0.TIsucT8Ce_c-XgfBtotOPw");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ShaktiApp());
}

class ShaktiApp extends StatefulWidget {
  const ShaktiApp({super.key});

  @override
  State<ShaktiApp> createState() => _ShaktiAppState();
}

class _ShaktiAppState extends State<ShaktiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      GuardianOverlayService.close();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      GuardianOverlayService.close();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shakti',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF2563EB),
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
      ),
      home: const WelcomeScreen(),
    );
  }
}
