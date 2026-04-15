import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../services/location_service.dart';
import '../../services/tracking_service.dart';
import '../../services/ride_service.dart';
import '../../services/auth_service.dart';

class CaptainHome extends StatefulWidget {
  const CaptainHome({super.key});

  @override
  State<CaptainHome> createState() => _CaptainHomeState();
}

class _CaptainHomeState extends State<CaptainHome> {
  final LocationService _location = LocationService();
  final RideService _rideService = RideService();
  final AuthService _auth = AuthService();
  final TrackingService _tracking = TrackingService();
  GoogleMapController? _mapController;
  LatLng? _currentPos;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _tracking.connect();
    _listenForRides();
  }

  void _listenForRides() {
    _tracking.stream.listen((data) {
      final msg = data is String ? jsonDecode(data) : data;
      if (msg['type'] == 'new_ride_available') {
        _showRideRequest(msg);
      }
    });
  }

  void _showRideRequest(Map<String, dynamic> ride) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildRideRequestSheet(ride),
    );
  }

  Widget _buildRideRequestSheet(Map<String, dynamic> ride) {
    final TextEditingController bidCtrl = TextEditingController();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('NEW RIDE REQUEST', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
              const Icon(Icons.notifications_active, color: Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 25),
          _ridePoint(Icons.circle, Colors.greenAccent, ride['pickup'] ?? 'Unknown location'),
          const Padding(padding: EdgeInsets.only(left: 11), child: SizedBox(height: 20, child: VerticalDivider(color: Colors.white12))),
          _ridePoint(Icons.location_on, Colors.orangeAccent, ride['drop'] ?? 'Unknown destination'),
          const SizedBox(height: 30),
          TextField(
            controller: bidCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Your Bid Amount (₹)',
              labelStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () {
               _rideService.submitBid(ride['ride_id'], double.tryParse(bidCtrl.text) ?? 0);
               Navigator.pop(context);
            },
            child: const Text('SUBMIT BID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _ridePoint(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 15),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16))),
      ],
    );
  }

  void _initLocation() async {
    final hasPermission = await _location.handleLocationPermission();
    if (hasPermission) {
      final pos = await _location.getCurrentPosition();
      setState(() {
        _currentPos = LatLng(pos.latitude, pos.longitude);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPos!, 15));
    }
  }

  void _toggleOnline() {
    final userId = _auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _isOnline = !_isOnline;
    });
    
    if (_isOnline) {
      // Start broadcasting location via WebSocket
      _location.getPositionStream().listen((pos) {
        if (_isOnline) {
          _tracking.updateLocation(userId, pos.latitude, pos.longitude, "available");
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _currentPos == null
            ? const Center(child: CircularProgressIndicator())
            : GoogleMap(
                initialCameraPosition: CameraPosition(target: _currentPos!, zoom: 15),
                onMapCreated: (ctrl) => _mapController = ctrl,
                myLocationEnabled: true,
                style: _mapStyle,
              ),

          // Online Toggle Overlay (Premium Style)
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green.withOpacity(0.9) : Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: (_isOnline ? Colors.green : Colors.black).withOpacity(0.4),
                    blurRadius: 20,
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isOnline ? 'ONLINE - RECEIVING RIDES' : 'OFFLINE',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Switch(
                    value: _isOnline,
                    onChanged: (val) => _toggleOnline(),
                    activeColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          
          // Statistics/Action Card
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: _currentRideId != null ? _buildActionCard() : _buildStatsCard(),
          )
        ],
      ),
    );
  }

  String? _currentRideId;

  Widget _buildActionCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('HEAD TO PICKUP', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)),
            onPressed: () => _showOTPDialog(),
            child: const Text('ENTER OTP TO START', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showOTPDialog() {
    final TextEditingController otpCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Verify OTP'),
        content: TextField(
          controller: otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          style: const TextStyle(fontSize: 32, letterSpacing: 10, color: Colors.orangeAccent),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
               final resp = await http.post(
                 Uri.parse('http://localhost:8090/api/ride/start'),
                 body: jsonEncode({
                   'rideId': _currentRideId,
                   'otp': int.tryParse(otpCtrl.text),
                 }),
                 headers: {'Content-Type': 'application/json'},
               );
               if (resp.statusCode == 200) {
                 Navigator.pop(context);
                 setState(() => _currentRideId = null);
               }
            },
            child: const Text('START RIDE'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('Today', '₹ 0.00'),
          _statItem('Rides', '0'),
          _statItem('Rating', '5.0 ★'),
        ],
      ),
    );
  }

  Widget _statItem(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 5),
        Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }

  static const String _mapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [{"color": "#212121"}]
    },
    {
      "elementType": "labels.icon",
      "stylers": [{"visibility": "off"}]
    }
  ]
  ''';
}
