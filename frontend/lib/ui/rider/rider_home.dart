import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/location_service.dart';
import '../../services/tracking_service.dart';

class RiderHome extends StatefulWidget {
  const RiderHome({super.key});

  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  final LocationService _location = LocationService();
  final TrackingService _tracking = TrackingService();
  GoogleMapController? _mapController;
  LatLng? _currentPos;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initLocation();
    _tracking.connect();
    _listenForCaptains();
  }

  void _initLocation() async {
    final hasPermission = await _location.handleLocationPermission();
    if (hasPermission) {
      final pos = await _location.getCurrentPosition();
      setState(() {
        _currentPos = LatLng(pos.latitude, pos.longitude);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPos!, 15));
      _tracking.queryNearby(pos.latitude, pos.longitude);
    }
  }

  void _listenForCaptains() {
    _tracking.stream.listen((data) {
      // Logic to parse nearby_captains and update markers
      // This is the real-time core
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // The Map
          _currentPos == null 
            ? const Center(child: CircularProgressIndicator())
            : GoogleMap(
                initialCameraPosition: CameraPosition(target: _currentPos!, zoom: 15),
                onMapCreated: (ctrl) => _mapController = ctrl,
                markers: _markers,
                myLocationEnabled: true,
                style: _mapStyle, // Custom Dark Map Style
              ),

          // Bottom Search Bar (Glassmorphic)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _requesting ? _buildBiddingPanel() : _buildSearchPanel(),
          ),
        ],
      ),
    );
  }

  bool _requesting = false;
  String? _activeRideId;

  Widget _buildSearchPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.circle, color: Colors.greenAccent, size: 12),
              const SizedBox(width: 10),
              const Expanded(child: Text('Current Location', style: TextStyle(color: Colors.white70))),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),
          TextField(
            decoration: InputDecoration(
              hintText: 'Where to?',
              prefixIcon: const Icon(Icons.location_on, color: Colors.orangeAccent),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              setState(() => _requesting = true);
              final ride = await RideService().createRide(
                pickupAddress: 'Current Location',
                dropAddress: 'Destination',
                pickupLat: _currentPos!.latitude,
                pickupLng: _currentPos!.longitude,
                dropLat: 0,
                dropLng: 0,
                distance: 5.0,
                initialFare: 100,
              );
              setState(() {
                _activeRideId = ride.id;
                _otp = ride.getString('start_otp');
              });
            },
            child: const Text('SEARCH RIDES', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildBiddingPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // If a captain is matched, show OTP
          _otp != null ? _buildMatchedPanel() : _buildSearchingLoader(),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() => _requesting = false),
            child: const Text('CANCEL REQUEST', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  String? _otp;

  Widget _buildSearchingLoader() {
    return Column(
      children: [
        const LinearProgressIndicator(color: Colors.orangeAccent, backgroundColor: Colors.white12),
        const SizedBox(height: 15),
        Text(
          'Finding Captains...',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
          child: const Row(
            children: [
              CircleAvatar(backgroundColor: Colors.white10, child: Icon(Icons.person, color: Colors.white60)),
              SizedBox(width: 12),
              Text('Waiting for bids...', style: TextStyle(color: Colors.white38)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMatchedPanel() {
    return Column(
      children: [
        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 48),
        const SizedBox(height: 10),
        Text('CAPTAIN MATCHED', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20)),
        const SizedBox(height: 20),
        const Text('Share this OTP with your Captain:', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(16)),
          child: Text(
            _otp ?? '----',
            style: const TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.black, letterSpacing: 8),
          ),
        ),
      ],
    );
  }

  // Simple Dark Map Style JSON
  static const String _mapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [{"color": "#242f3e"}]
    },
    {
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#746855"}]
    },
    {
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#242f3e"}]
    }
  ]
  ''';
}
