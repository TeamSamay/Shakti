import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../services/map_service.dart';
import '../services/navigation_service.dart';
import 'pages/chatbot_page.dart';
import 'pages/emergency_check_in_screen.dart';
import 'pages/profile_page.dart';
import 'widgets/route_search_sheet.dart';
import '../widgets/emergency_trigger_button.dart';

// ── Pharmacy Tier Model is now in MapService ──────────────────────────────────

class CustomerMapTab extends StatefulWidget {
  const CustomerMapTab({super.key});

  @override
  State<CustomerMapTab> createState() => _CustomerMapTabState();
}

class _CustomerMapTabState extends State<CustomerMapTab>
    with AutomaticKeepAliveClientMixin {
  static const double _nandedLat = 19.1383;
  static const double _nandedLng = 77.3210;

  @override
  bool get wantKeepAlive => true;

  mapbox.MapboxMap? _mapboxMap;
  Timer? _styleCheckTimer;
  Timer? _locationUpdateTimer;
  Timer? _emergencyBannerTimer;
  Position? _currentPosition;
  User? _currentUser;
  StreamSubscription<User?>? _userSubscription;
  bool _mapInitialized = false;
  bool _hasCenteredOnUser = false;
  bool _showEmergencyBanner = false;

  bool _isRouting = false;
  MapboxPlace? _destination;
  RouteData? _routeData;
  mapbox.PolylineAnnotationManager? _polylineManager;

  @override
  void initState() {
    super.initState();
    _initUser();
    _startLocationTracking();
  }

  void _initUser() {
    _currentUser = FirebaseAuth.instance.currentUser;
    _userSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) setState(() => _currentUser = user);
    });
  }

  Future<void> _startLocationTracking() async {
    await _requestLocationPermission();
    await _refreshCurrentLocation(centerMap: false);
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshCurrentLocation(centerMap: false);
    });
  }

  Future<bool> _requestLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<void> _refreshCurrentLocation({required bool centerMap}) async {
    try {
      final allowed = await _requestLocationPermission();
      if (!allowed) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      if (!mounted) return;
      setState(() => _currentPosition = pos);
      if (centerMap || !_hasCenteredOnUser) {
        _hasCenteredOnUser = true;
        _flyTo(pos.latitude, pos.longitude);
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _mapboxMap!.compass.updateSettings(
      mapbox.CompassSettings(enabled: false),
    );
    _mapboxMap!.logo.updateSettings(mapbox.LogoSettings(enabled: false));
    _mapboxMap!.attribution.updateSettings(
      mapbox.AttributionSettings(enabled: false),
    );
    _mapboxMap!.scaleBar.updateSettings(
      mapbox.ScaleBarSettings(enabled: false),
    );
    _enableLocationPuck();

    _styleCheckTimer?.cancel();
    _styleCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      if (!mounted || _mapboxMap == null) {
        timer.cancel();
        return;
      }
      final loaded = await _mapboxMap!.style.isStyleLoaded();
      if (loaded || timer.tick > 20) {
        timer.cancel();
        await _initializeMap();
      }
    });
  }

  Future<void> _initializeMap() async {
    if (_mapInitialized || _mapboxMap == null) return;
    _mapInitialized = true;
    _polylineManager =
        await _mapboxMap!.annotations.createPolylineAnnotationManager();
    await _enable3DFeatures();
    _enableLocationPuck();
    final pos = _currentPosition;
    if (pos != null) {
      _flyTo(pos.latitude, pos.longitude);
    } else {
      _flyTo(_nandedLat, _nandedLng);
    }
  }

  Future<void> _enableLocationPuck() async {
    if (_mapboxMap == null) return;
    try {
      await _mapboxMap!.location.updateSettings(
        mapbox.LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          puckBearingEnabled: true,
        ),
      );
    } catch (e) {
      debugPrint('Location puck skipped: $e');
    }
  }

  Future<void> _enable3DFeatures() async {
    if (_mapboxMap == null) return;
    try {
      final buildingLayer = mapbox.FillExtrusionLayer(
        id: '3d-buildings-extrusion',
        sourceId: 'composite',
      )
        ..sourceLayer = 'building'
        ..minZoom = 13.0
        ..filter = [
          '==',
          ['get', 'extrude'],
          'true',
        ]
        ..fillExtrusionColor = const Color(0xFFFFFFFF).toARGB32()
        ..fillExtrusionOpacity = 0.82
        ..fillExtrusionAmbientOcclusionIntensity = 0.3;

      await _mapboxMap!.style.addLayer(buildingLayer);
      await _mapboxMap!.style.setStyleLayerProperty(
        '3d-buildings-extrusion',
        'fill-extrusion-height',
        ['get', 'height'],
      );
      await _mapboxMap!.style.setStyleLayerProperty(
        '3d-buildings-extrusion',
        'fill-extrusion-base',
        ['get', 'min_height'],
      );
    } catch (e) {
      debugPrint('3D building layer skipped: $e');
    }

    try {
      await _mapboxMap!.style.addSource(
        mapbox.RasterDemSource(
          id: 'mapbox-dem',
          url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
          tileSize: 512,
        ),
      );
      await _mapboxMap!.style.setStyleTerrainProperty('source', 'mapbox-dem');
      await _mapboxMap!.style.setStyleTerrainProperty('exaggeration', 1.4);
    } catch (e) {
      debugPrint('Terrain skipped: $e');
    }
  }

  void _flyTo(double lat, double lng) {
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        zoom: 16.2,
        pitch: 62.0,
        bearing: -18,
      ),
      mapbox.MapAnimationOptions(duration: 900),
    );
  }

  void _centerOnCurrentLocation() {
    HapticFeedback.selectionClick();
    _refreshCurrentLocation(centerMap: true);
  }

  void _showEmergencyTrackingBanner() {
    _emergencyBannerTimer?.cancel();
    if (mounted) setState(() => _showEmergencyBanner = true);
    _emergencyBannerTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showEmergencyBanner = false);
    });
  }

  @override
  void dispose() {
    _styleCheckTimer?.cancel();
    _locationUpdateTimer?.cancel();
    _emergencyBannerTimer?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Stack(
        children: [
          mapbox.MapWidget(
            onMapCreated: _onMapCreated,
            textureView: true,
            styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(_nandedLng, _nandedLat),
              ),
              zoom: 15.0,
              pitch: 62.0,
            ),
          ),
          // Top Overlays
          if (!_isRouting)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMapStatusPill(),
                  _buildAccountButton(),
                ],
              ),
            ),
          if (_showEmergencyBanner && !_isRouting)
            Positioned(
              top: 106,
              left: 16,
              right: 16,
              child: _buildEmergencyTrackingBanner(),
            ),
          if (!_isRouting)
            Positioned(
              right: 16,
              bottom: 188,
              child: EmergencyTriggerButton(
                onEmergencyTriggered: _showEmergencyTrackingBanner,
              ),
            ),
          if (!_isRouting)
            Positioned(
              right: 16,
              bottom: 112,
              child: _roundAction(
                icon: Icons.call_rounded,
                color: const Color(0xFF059669),
                background: Colors.white,
                onTap: _openDemoFakeCallSheet,
              ),
            ),
          // Bottom Navigation
          if (!_isRouting)
            Positioned(
              left: 16,
              right: 16,
              bottom: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _openSearchSheet,
                    child: _buildSafetyScoreCard(),
                  ),
                  Row(
                    children: [
                      _roundAction(
                        icon: Icons.support_agent_rounded,
                        color: const Color(0xFF8B5CF6),
                        onTap: () => Navigator.of(context).push(
                          _fastRoute(const ChatBotScreen()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _roundAction(
                        icon: Icons.my_location_rounded,
                        color: const Color(0xFF2563EB),
                        background: Colors.white,
                        onTap: _centerOnCurrentLocation,
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Positioned(
              left: 16,
              right: 16,
              bottom: 30,
              child: _buildRoutePreviewPanel(),
            ),
        ],
      ),
    );
  }

  void _openSearchSheet() async {
    final place = await showModalBottomSheet<MapboxPlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: RouteSearchSheet(
          userLat: _currentPosition?.latitude,
          userLng: _currentPosition?.longitude,
        ),
      ),
    );
    if (place != null && _currentPosition != null) {
      _startRoute(place);
    }
  }

  void _openDemoFakeCallSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildDemoFakeCallSheet(),
    );
  }

  Future<void> _startRoute(MapboxPlace place) async {
    final navService = NavigationService();
    final route = await navService.getRoute(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      place.lat,
      place.lng,
    );

    if (route != null && mounted) {
      setState(() {
        _isRouting = true;
        _destination = place;
        _routeData = route;
      });
      _drawRoute(route.geometry);

      _mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              (place.lng + _currentPosition!.longitude) / 2,
              (place.lat + _currentPosition!.latitude) / 2,
            ),
          ),
          zoom: 13.5,
          pitch: 50.0,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );
    }
  }

  void _drawRoute(List<List<double>> geometry) async {
    if (_polylineManager == null) return;
    await _polylineManager!.deleteAll();

    final coordinates =
        geometry.map((c) => mapbox.Position(c[0], c[1])).toList();

    await _polylineManager!.create(
      mapbox.PolylineAnnotationOptions(
        geometry: mapbox.LineString(coordinates: coordinates),
        lineColor: Colors.blueAccent.toARGB32(),
        lineWidth: 6.0,
        lineJoin: mapbox.LineJoin.ROUND,
      ),
    );
  }

  void _endRoute() async {
    if (_polylineManager != null) {
      await _polylineManager!.deleteAll();
    }
    setState(() {
      _isRouting = false;
      _destination = null;
      _routeData = null;
    });
    _centerOnCurrentLocation();
  }

  Widget _buildRoutePreviewPanel() {
    final distanceKm = (_routeData?.distance ?? 0) / 1000;
    final durationMin = (_routeData?.duration ?? 0) / 60;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _floatingDecoration(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _destination?.name ?? 'Destination',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: _endRoute,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${durationMin.toStringAsFixed(0)} min',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '(${distanceKm.toStringAsFixed(1)} km)',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Navigation started!')),
                );
              },
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Start Navigation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapStatusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _floatingDecoration(24),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 18),
          SizedBox(width: 8),
          Text(
            'Guardian Map',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyTrackingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF1E8),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.health_and_safety_rounded,
              color: Color(0xFFDC2626),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Emergency tracking active',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Live location and safety status are being shared.',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              _emergencyBannerTimer?.cancel();
              setState(() => _showEmergencyBanner = false);
            },
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoFakeCallSheet() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 22),
            CircleAvatar(
              radius: 38,
              backgroundColor: const Color(0xFFEFF6FF),
              child: const Text(
                'M',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Mom \u2665',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '03:24',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 26),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 18,
              crossAxisSpacing: 14,
              childAspectRatio: 0.92,
              children: [
                _fakeCallControl(Icons.mic_off_rounded, 'Mute'),
                _fakeCallControl(Icons.volume_up_rounded, 'Speaker'),
                _fakeCallControl(Icons.dialpad_rounded, 'Keypad'),
                _fakeCallControl(
                  Icons.sos_rounded,
                  'Emergency\nTrigger',
                  active: true,
                ),
                _fakeCallControl(Icons.notes_rounded, 'Notes'),
                _fakeCallControl(Icons.contacts_rounded, 'Contacts'),
              ],
            ),
            const SizedBox(height: 24),
            Material(
              color: const Color(0xFFE11D48),
              shape: const CircleBorder(),
              elevation: 8,
              shadowColor: const Color(0xFFE11D48).withOpacity(0.28),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'End Call',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fakeCallControl(
    IconData icon,
    String label, {
    bool active = false,
  }) {
    final color = active ? const Color(0xFFE11D48) : const Color(0xFF111827);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: active ? const Color(0xFFFFF1F2) : const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
            border: active
                ? Border.all(color: const Color(0xFFE11D48), width: 1.5)
                : null,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            color: color,
            fontSize: 11,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildAccountButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(_fastRoute(const ProfilePage())),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: _floatingDecoration(40),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF0F172A),
          backgroundImage: _currentUser?.photoURL != null
              ? NetworkImage(_currentUser!.photoURL!)
              : null,
          child: _currentUser?.photoURL == null
              ? const Icon(Icons.person_rounded, color: Colors.white)
              : null,
        ),
      ),
    );
  }

  Widget _buildSafetyScoreCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _floatingDecoration(20),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route_rounded, color: Color(0xFF2563EB), size: 20),
          SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Safe Route',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Safety score 89%',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuardianBubble() {
    return Material(
      color: const Color(0xFFDC2626),
      shape: const CircleBorder(),
      elevation: 10,
      shadowColor: const Color(0xFFDC2626).withOpacity(0.35),
      child: InkWell(
        onTap: () {
          HapticFeedback.heavyImpact();
          Navigator.of(context).push(
            _fastRoute(const EmergencyCheckInScreen()),
          );
        },
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 64,
          height: 64,
          child: Icon(
            Icons.health_and_safety_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Color? background,
  }) {
    final bg = background ?? color;
    final iconColor = background == null ? Colors.white : color;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: 5,
      shadowColor: color.withOpacity(0.28),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: iconColor, size: 28),
        ),
      ),
    );
  }

  BoxDecoration _floatingDecoration(double radius) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.14),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static Route<T> _fastRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}
