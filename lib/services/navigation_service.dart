import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class MapboxPlace {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;

  MapboxPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory MapboxPlace.fromJson(Map<String, dynamic> json) {
    return MapboxPlace(
      id: json['id'] as String,
      name: json['text'] as String? ?? 'Unknown Place',
      address: json['place_name'] as String? ?? '',
      lat: (json['center'][1] as num).toDouble(),
      lng: (json['center'][0] as num).toDouble(),
    );
  }
}

class RouteData {
  final List<List<double>> geometry; // List of [lng, lat]
  final double distance; // meters
  final double duration; // seconds

  RouteData({
    required this.geometry,
    required this.distance,
    required this.duration,
  });

  factory RouteData.fromJson(Map<String, dynamic> json) {
    final routes = json['routes'] as List;
    if (routes.isEmpty) {
      throw Exception('No routes found');
    }
    final route = routes.cast<Map<String, dynamic>>().reduce((best, route) {
      final bestDistance =
          (best['distance'] as num?)?.toDouble() ?? double.infinity;
      final routeDistance =
          (route['distance'] as num?)?.toDouble() ?? double.infinity;
      return routeDistance < bestDistance ? route : best;
    });

    // Geometry can be a string (encoded polyline) or GeoJSON object.
    // We requested geometries=geojson
    final geo = route['geometry'];
    final coords = (geo['coordinates'] as List)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();

    return RouteData(
      geometry: coords,
      distance: (route['distance'] as num).toDouble(),
      duration: (route['duration'] as num).toDouble(),
    );
  }
}

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  static const String _mapboxToken = "pk.eyJ1Ijoic2FtYXkwMSIsImEiOiJjbW4xeWJpcDExMW1sMnJzZmFyeGljZTU3In0.TIsucT8Ce_c-XgfBtotOPw";

  Future<List<MapboxPlace>> searchPlaces(String query, {double? proximityLat, double? proximityLng}) async {
    if (query.isEmpty) return [];

    try {
      String url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=$_mapboxToken&autocomplete=true';
      if (proximityLat != null && proximityLng != null) {
        url += '&proximity=$proximityLng,$proximityLat';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        return features.map((f) => MapboxPlace.fromJson(f)).toList();
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
    }
    return [];
  }

  Future<RouteData?> getRoute(double startLat, double startLng, double endLat, double endLng) async {
    try {
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/$startLng,$startLat;$endLng,$endLat'
          '?geometries=geojson&overview=full&steps=true&alternatives=true&continue_straight=true&access_token=$_mapboxToken';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RouteData.fromJson(data);
      } else {
        debugPrint('Route API error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }
    return null;
  }
}
