import 'package:pocketbase/pocketbase.dart';
import 'auth_service.dart';

class RideService {
  final AuthService _auth = AuthService();
  late PocketBase pb;

  RideService() {
    pb = _auth.pb;
  }

  /// Create a new ride request
  Future<RecordModel> createRide({
    required String pickupAddress,
    required String dropAddress,
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required double distance,
    required double initialFare,
  }) async {
    final body = <String, dynamic>{
      "rider_id": _auth.currentUser?.id,
      "pickup_address": pickupAddress,
      "drop_address": dropAddress,
      "pickup_lat": pickupLat,
      "pickup_lng": pickupLng,
      "drop_lat": dropLat,
      "drop_lng": dropLng,
      "distance_km": distance,
      "agreed_fare": initialFare,
      "status": "matched", // Initial status
    };

    return await pb.collection('rides').create(body: body);
  }

  /// Submit a bid for a ride (Captain only)
  Future<RecordModel> submitBid(String rideId, double amount) async {
    final body = <String, dynamic>{
      "ride_id": rideId,
      "captain_id": _auth.currentUser?.id,
      "amount": amount,
      "status": "pending",
    };

    return await pb.collection('bids').create(body: body);
  }

  /// Accept a bid (Rider only)
  Future<void> acceptBid(String rideId, String captainId, double finalFare) async {
    await pb.collection('rides').update(rideId, body: {
      "captain_id": captainId,
      "agreed_fare": finalFare,
      "status": "matched",
    });
  }

  /// Stream of bids for a specific ride
  Stream<RecordModel?> streamBids(String rideId) {
    // PocketBase real-time subscription
    return pb.collection('bids').subscribe("*", (e) {
      if (e.action == "create" && e.record?.getString("ride_id") == rideId) {
        // New bid found
      }
    }).then((_) => null).asStream().map((event) => null);
    // Note: In real implementation, we use a StreamController to wrap the subscription
  }
}
