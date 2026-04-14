import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class TrackingService {
  WebSocketChannel? _channel;
  static const String wsUrl = 'ws://localhost:8090/api/ride/ws';

  /// Connect to the WebSocket tracking server
  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
  }

  /// Broadcast location for Captains
  void updateLocation(String id, double lat, double lng, String status) {
    _channel?.sink.add(jsonEncode({
      "type": "update_location",
      "id": id,
      "lat": lat,
      "lng": lng,
      "status": status,
    }));
  }

  /// Query nearby captains for Riders
  void queryNearby(double lat, double lng) {
    _channel?.sink.add(jsonEncode({
      "type": "get_nearby",
      "lat": lat,
      "lng": lng,
    }));
  }

  /// Listen for incoming messages (nearby captains, etc.)
  Stream<dynamic> get stream => _channel?.stream ?? const Stream.empty();

  void disconnect() {
    _channel?.sink.close();
  }
}
