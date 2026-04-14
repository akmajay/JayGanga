import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:http/http.dart' as http;

class AuthService {
  // Config
  static const String baseUrl = 'http://localhost:8090'; // Change to your VPS IP in production
  
  final PocketBase pb = PocketBase(baseUrl);
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Authenticate with Google and then with our custom PocketBase endpoint
  Future<RecordAuth?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception("Failed to get Google ID Token");
      }

      // Call our custom Go endpoint to verify token and get PocketBase JWT
      final response = await http.post(
        Uri.parse('$baseUrl/api/ride/auth-google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );

      if (response.statusCode != 200) {
        throw Exception("Backend auth failed: ${response.body}");
      }

      final data = jsonDecode(response.body);
      
      // Manually update the PocketBase AuthStore with the received token and model
      final token = data['token'];
      final model = RecordModel.fromJson(data['record']);
      
      pb.authStore.save(token, model);
      
      return RecordAuth(token: token, record: model);
    } catch (e) {
      print("Google Sign-In Error: $e");
      rethrow;
    }
  }

  void signOut() {
    _googleSignIn.signOut();
    pb.authStore.clear();
  }

  bool get isAuthenticated => pb.authStore.isValid;
  RecordModel? get currentUser => pb.authStore.model as RecordModel?;
}
