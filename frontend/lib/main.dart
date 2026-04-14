import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/auth_service.dart';
import 'ui/rider/rider_home.dart';
import 'ui/captain/captain_home.dart';

void main() {
  runApp(const JayGangaApp());
}

class JayGangaApp extends StatelessWidget {
  const JayGangaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JayGanga',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _auth = AuthService();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return _auth.isAuthenticated ? const RoleSelector() : _buildLoginScreen();
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F0F1A), Color(0xFF1A1A2E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo Placeholder (Rich Text for MVP)
                  Text(
                    'JAYGANGA',
                    style: GoogleFonts.outfit(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Zero Commission. Full Freedom.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 100),
                  // Google Login Button (Premium Style)
                  _loading 
                    ? const CircularProgressIndicator(color: Colors.orangeAccent)
                    : InkWell(
                        onTap: () async {
                          setState(() => _loading = true);
                          try {
                            await _auth.signInWithGoogle();
                             if (mounted) setState(() {});
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orangeAccent.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Google Icon Emoji as placeholder (will replace with real image later)
                              const Text('G ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 20)),
                              const SizedBox(width: 12),
                              const Text(
                                'Sign in with Google',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RoleSelector extends StatelessWidget {
  const RoleSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F0F1A), Color(0xFF1A1A2E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Choose Your Role',
                  style: GoogleFonts.outfit(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 50),
                _roleCard(
                  context,
                  'RIDER',
                  'Find a ride in seconds',
                  Icons.person_pin_circle,
                  Colors.orangeAccent,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RiderHome())),
                ),
                const SizedBox(height: 20),
                _roleCard(
                  context,
                  'CAPTAIN',
                  'Turn your vehicle into income',
                  Icons.drive_eta,
                  Colors.greenAccent,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CaptainHome())),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleCard(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            )
          ],
        ),
      ),
    );
  }
}
