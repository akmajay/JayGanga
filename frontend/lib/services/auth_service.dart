import 'package:fetch_client/fetch_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthService {
  // Config
  static const String baseUrl = 'http://localhost:8090'; 
  
  static final AuthService _instance = AuthService._internal();
  late final PocketBase pb;

  // Singleton accessor
  factory AuthService() => _instance;

  AuthService._internal() {
    // On Web, we MUST use FetchClient to support OAuth2 streaming responses
    pb = PocketBase(
      baseUrl,
      httpClientFactory: kIsWeb 
          ? () => FetchClient(mode: RequestMode.cors) 
          : null,
    );
  }

  /// Real Native OAuth2 Google Sign-In for Web
  Future<RecordAuth?> signInWithGoogle() async {
    try {
      final authData = await pb.collection('users').authWithOAuth2(
        'google',
        (url) async {
          // Opens Google Login in the same tab (standard for single-page apps)
          // or use webOnlyWindowName: '_blank' for a popup
          await launchUrl(url);
        },
      );
      
      print("Successfully authenticated User: ${authData.record.id}");
      return authData;
    } catch (e) {
      print("Native OAuth2 Error: $e");
      return null;
    }
  }

  void signOut() {
    pb.authStore.clear();
  }

  bool get isAuthenticated => pb.authStore.isValid;
  RecordModel? get currentUser => pb.authStore.model as RecordModel?;
}
