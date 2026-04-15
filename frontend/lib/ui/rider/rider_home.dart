import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../services/location_service.dart';
import '../../services/tracking_service.dart';
import '../../services/ride_service.dart';

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

  bool _isSelectingPickup = true;
  bool _isSelectingDropoff = false;
  LatLng? _tempCenter;
  String _pickupAddress = "Locating...";
  String _dropAddress = "Selecting...";
  LatLng? _pickupLatLng;
  LatLng? _dropLatLng;

  void _initLocation() async {
    final hasPermission = await _location.handleLocationPermission();
    if (hasPermission) {
      final pos = await _location.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentPos = latLng;
        _tempCenter = latLng;
        _pickupLatLng = latLng;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15));
      _tracking.queryNearby(pos.latitude, pos.longitude);
      _getAddressFromLatLng(latLng, true);
    }
  }

  void _listenForCaptains() {
    _tracking.stream.listen((data) {
      // Logic to parse nearby_captains and update markers in real-time
    });
  }

  Future<void> _getAddressFromLatLng(LatLng pos, bool isPickup) async {
    // Note: This requires Geocoding API enabled on the key
    final url = 'https://maps.googleapis.com/maps/api/geocode/json?latlng=${pos.latitude},${pos.longitude}&key=AIzaSyCSTul_3IBZuhT9MOuMdH5-A3zrxCOyucM';
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['status'] == 'OK') {
          final addr = data['results'][0]['formatted_address'];
          setState(() {
            if (isPickup) _pickupAddress = addr;
            else _dropAddress = addr;
          });
        }
      }
    } catch (_) {}
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
                onCameraMove: (pos) => _tempCenter = pos.target,
                onCameraIdle: () {
                  if (_tempCenter != null && (_isSelectingPickup || _isSelectingDropoff)) {
                    _getAddressFromLatLng(_tempCenter!, _isSelectingPickup);
                  }
                },
                style: _mapStyle,
              ),

          // center pin pointer
          if (_isSelectingPickup || _isSelectingDropoff)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 35),
                child: Icon(
                  Icons.location_on, 
                  size: 50, 
                  color: _isSelectingPickup ? Colors.greenAccent : Colors.orangeAccent
                ),
              ),
            ),

          // Top Selection Banner
          if (_isSelectingPickup || _isSelectingDropoff)
            Positioned(
              top: 60, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  _isSelectingPickup ? '📍 MOVE MAP TO PICKUP' : '🏁 DRAG TO DESTINATION',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
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
        color: Colors.black.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.circle, color: _isSelectingPickup ? Colors.greenAccent : Colors.white24, size: 10),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isSelectingPickup ? "Set Pickup: $_pickupAddress" : "Pickup: $_pickupAddress",
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _isSelectingPickup ? Colors.white : Colors.white38),
                )
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Icon(Icons.location_on, color: _isSelectingDropoff ? Colors.orangeAccent : Colors.white24, size: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isSelectingDropoff ? "Set Dropoff: $_dropAddress" : "Dropoff: $_dropAddress",
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _isSelectingDropoff ? Colors.white : Colors.white38),
                )
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              try {
                if (_isSelectingPickup) {
                  setState(() {
                    _pickupLatLng = _tempCenter;
                    _isSelectingPickup = false;
                    _isSelectingDropoff = true;
                  });
                  // Move map slightly to prompt user to drag for destination
                } else if (_isSelectingDropoff) {
                  setState(() {
                    _dropLatLng = _tempCenter;
                    _isSelectingDropoff = false;
                    _requesting = true;
                  });
                  
                  final ride = await RideService().createRide(
                    pickupAddress: _pickupAddress,
                    dropAddress: _dropAddress,
                    pickupLat: _pickupLatLng!.latitude,
                    pickupLng: _pickupLatLng!.longitude,
                    dropLat: _dropLatLng!.latitude,
                    dropLng: _dropLatLng!.longitude,
                    distance: 5.0,
                    initialFare: 100,
                  );
                  
                  setState(() {
                    _activeRideId = ride.id;
                    _otp = ride.data['start_otp']?.toString();
                  });
                }
              } catch (e) {
                print("Ride Request Error: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to request ride: $e'), backgroundColor: Colors.redAccent)
                );
                setState(() => _requesting = false);
              }
            },
            child: Text(
              _isSelectingPickup ? 'CONFIRM PICKUP' : 'CONFIRM DESTINATION',
              style: const TextStyle(fontWeight: FontWeight.bold)
            ),
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
            style: const TextStyle(color: Colors.black, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 8),
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
