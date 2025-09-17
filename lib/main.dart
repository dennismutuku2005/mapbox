import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      home: const UberLikeMapPage(),
    );
  }
}

class UberLikeMapPage extends StatefulWidget {
  const UberLikeMapPage({super.key});

  @override
  State<UberLikeMapPage> createState() => _UberLikeMapPageState();
}

class _UberLikeMapPageState extends State<UberLikeMapPage> with TickerProviderStateMixin {
  LatLng? _currentLocation;
  LatLng? _destination;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  double? _routeDistance; // in kilometers
  double? _routeDuration; // in minutes
  double _costPerKm = 70; // Cost per kilometer
  final LatLng _nairobiCenter = const LatLng(-1.286389, 36.817223);

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enable location services")),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied")),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission denied forever")),
      );
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_currentLocation!, 12);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error getting location: $e")),
      );
    }
  }

  Future<void> _searchPlace(String query) async {
    if (query.isEmpty) return;

    const mapboxToken = "pk.eyJ1IjoibXV1b2RldiIsImEiOiJjbWZvNHI1cHgwMjBkMmpzOHg5Y3owOGduIn0.JP7PYOy9okV_OdI3MoQBuQ";
    final url = "https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json?proximity=36.817223,-1.286389&access_token=$mapboxToken";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["features"] != null && data["features"].isNotEmpty) {
          final place = data["features"][0];
          final coordinates = place["geometry"]["coordinates"];
          setState(() {
            _destination = LatLng(coordinates[1], coordinates[0]);
            _routePoints.clear();
          });
          await _getRoute();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Place not found")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error searching place")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network error during search")),
      );
    }
  }

  Future<void> _getRoute() async {
    if (_currentLocation == null || _destination == null) return;

    setState(() {
      _isLoadingRoute = true;
    });

    try {
      const mapboxToken = "pk.eyJ1IjoibXV1b2RldiIsImEiOiJjbWZvNHI1cHgwMjBkMmpzOHg5Y3owOGduIn0.JP7PYOy9okV_OdI3MoQBuQ";
      final url =
          "https://api.mapbox.com/directions/v5/mapbox/driving/${_currentLocation!.longitude},${_currentLocation!.latitude};${_destination!.longitude},${_destination!.latitude}?geometries=geojson&access_token=$mapboxToken";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["routes"] != null && data["routes"].isNotEmpty) {
          final coords = data["routes"][0]["geometry"]["coordinates"] as List;
          final distance = data["routes"][0]["distance"] / 1000; // Convert to km
          final duration = data["routes"][0]["duration"] / 60; // Convert to minutes
          setState(() {
            _routePoints = coords
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
            _routeDistance = distance;
            _routeDuration = duration;
          });

          _fitRouteBounds();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Route found!"),
              duration: const Duration(seconds: 1),
              backgroundColor: Colors.green[700],
            ),
          );
        }
      } else {
        setState(() {
          _routePoints = [_currentLocation!, _destination!];
          _routeDistance = null;
          _routeDuration = null;
        });

        _fitRouteBounds();

        String errorMsg = "Routing failed";
        if (response.statusCode == 401) {
          errorMsg = "API token issue - using straight line";
        } else if (response.statusCode == 429) {
          errorMsg = "Rate limit exceeded - using straight line";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.orange[700],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _routePoints = [_currentLocation!, _destination!];
        _routeDistance = null;
        _routeDuration = null;
      });

      _fitRouteBounds();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Network error - using straight line route"),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.red[700],
        ),
      );
    }

    setState(() {
      _isLoadingRoute = false;
    });
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;

    double minLat = _routePoints[0].latitude;
    double maxLat = _routePoints[0].latitude;
    double minLng = _routePoints[0].longitude;
    double maxLng = _routePoints[0].longitude;

    for (var point in _routePoints) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    final bounds = LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _destination = point;
      _routePoints.clear();
      _routeDistance = null;
      _routeDuration = null;
    });
    _getRoute();
  }

  void _clearRoute() {
    setState(() {
      _destination = null;
      _routePoints.clear();
      _routeDistance = null;
      _routeDuration = null;
      _searchController.clear();
    });
    _mapController.move(_currentLocation ?? _nairobiCenter, 12);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Your Bike Route'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_destination != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearRoute,
              tooltip: 'Clear Route',
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_currentLocation == null)
            const Center(child: CircularProgressIndicator())
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation!,
                initialZoom: 12,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoibXV1b2RldiIsImEiOiJjbWZvNHI1cHgwMjBkMmpzOHg5Y3owOGduIn0.JP7PYOy9okV_OdI3MoQBuQ",
                  additionalOptions: {
                    'accessToken': 'pk.eyJ1IjoibXV1b2RldiIsImEiOiJjbWZvNHI1cHgwMjBkMmpzOHg5Y3owOGduIn0.JP7PYOy9okV_OdI3MoQBuQ',
                    'id': 'mapbox.streets',
                  },
                  userAgentPackageName: 'com.example.app',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: Colors.blue[600]!,
                        borderStrokeWidth: 1,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.location_pin,
                        color: Colors.blue[800],
                        size: 40,
                      ),
                    ),
                    if (_destination != null)
                      Marker(
                        point: _destination!,
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.directions_bike,
                          color: Colors.red[600],
                          size: 40,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          Positioned(
            top: 10,
            left: 20,
            right: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search for a place (e.g., Kilimani)',
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchPlace(_searchController.text),
                    ),
                  ),
                  onSubmitted: _searchPlace,
                ),
              ),
            ),
          ),
          if (_isLoadingRoute)
            Positioned(
              top: 70,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[800]!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Calculating route...',
                        style: TextStyle(color: Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_destination != null && _routeDistance != null && _routeDuration != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Your Bike Ride',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Distance'),
                          Text('${_routeDistance!.toStringAsFixed(1)} km'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Est. Time'),
                          Text('${_routeDuration!.toStringAsFixed(0)} min'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cost'),
                          Text('KES ${(_routeDistance! * _costPerKm).toStringAsFixed(0)}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_destination == null)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Card(
                color: Colors.black.withOpacity(0.7),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Tap the map or search to set your bike destination',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "location",
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue[800],
            onPressed: () {
              _getUserLocation();
              _mapController.move(_currentLocation ?? _nairobiCenter, 12);
            },
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "nairobi",
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue[800],
            onPressed: () {
              setState(() {
                _currentLocation = _nairobiCenter;
              });
              _mapController.move(_nairobiCenter, 12);
            },
            child: const Icon(Icons.location_city),
            tooltip: 'Center on Nairobi',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}