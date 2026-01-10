import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';
import 'home_page.dart';
import 'landing_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithEmail(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithGoogle();
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            LayoutBuilder(
              builder: (context, constraints) {
                const maxContentWidth = 1200.0;

                Widget content;
                if (isWide) {
                  content = Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 32, right: 16),
                          child: Center(
                            child: _AuthCard(
                              formKey: _formKey,
                              email: _email,
                              password: _password,
                              loading: _loading,
                              onLogin: _login,
                              onGoogle: _google,
                              showPassword: _showPassword,
                              toggleShowPassword: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Flexible(
                        flex: 5,
                        child: Align(
                          alignment: Alignment.center,
                          child: _Rainbow3DPanel(
                            maxSide:
                                (constraints.maxWidth.clamp(
                                  900.0,
                                  maxContentWidth,
                                )) *
                                0.45,
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  content = Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _AuthCard(
                        formKey: _formKey,
                        email: _email,
                        password: _password,
                        loading: _loading,
                        onLogin: _login,
                        onGoogle: _google,
                        showPassword: _showPassword,
                        toggleShowPassword: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  );
                }

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: maxContentWidth,
                    ),
                    child: content,
                  ),
                );
              },
            ),

            // Page-level "S" (top-left)
            Positioned(
              top: 16,
              left: 16,
              child: SLogoButton(
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LandingPage()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.formKey,
    required this.email,
    required this.password,
    required this.loading,
    required this.onLogin,
    required this.onGoogle,
    required this.showPassword,
    required this.toggleShowPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool loading;
  final VoidCallback onLogin;
  final VoidCallback onGoogle;
  final bool showPassword;
  final VoidCallback toggleShowPassword;

  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(
      colors: [Color(0xFF7C3AED), Color(0xFF9F67FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    InputDecoration deco(String label, IconData icon) => InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFFA1A1AA)),
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFFA1A1AA)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF27272A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2),
      ),
      filled: true,
      fillColor: const Color(0xFF0F0F11),
    );

    Widget social(IconData icon, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F11),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF27272A)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );

    Widget divider(String text) => Row(
      children: [
        const Expanded(child: Divider(color: Colors.grey)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(text, style: const TextStyle(color: Colors.grey)),
        ),
        const Expanded(child: Divider(color: Colors.grey)),
      ],
    );

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF27272A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.1),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              r"Welcome back to $wap, Sign in",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            // Social buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                social(Icons.apple, () {}),
                const SizedBox(width: 16),
                social(Icons.g_mobiledata, onGoogle),
                const SizedBox(width: 16),
                social(Icons.facebook, () {}),
              ],
            ),
            const SizedBox(height: 20),

            divider("OR"),
            const SizedBox(height: 20),

            TextFormField(
              controller: email,
              style: const TextStyle(color: Colors.white),
              decoration: deco("Email Address", Icons.email),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: password,
              obscureText: !showPassword,
              style: const TextStyle(color: Colors.white),
              decoration: deco("Password", Icons.lock).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    showPassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: toggleShowPassword,
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordPage(),
                    ),
                  );
                },
                child: const Text(
                  "Forgot password?",
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: gradient,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: loading ? null : onLogin,
                child: loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Sign in",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            Center(
              child: GestureDetector(
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SignUpPage())),
                child: const Text.rich(
                  TextSpan(
                    text: "Don’t have an account? ",
                    style: TextStyle(color: Colors.white70),
                    children: [
                      TextSpan(
                        text: "Sign up!",
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              "By continuing, you agree to our Terms of Service & Privacy Policy",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rainbow3DPanel extends StatelessWidget {
  const _Rainbow3DPanel({this.maxSide});

  final double? maxSide;

  @override
  Widget build(BuildContext context) {
    final double side = ((maxSide ?? 480).clamp(320.0, 600.0)).toDouble();

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: side * 0.8,
          height: side * 0.8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x407C3AED),
                blurRadius: 100,
                spreadRadius: 12,
              ),
            ],
          ),
        ),
        SizedBox(
          width: side,
          height: side,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: const _Rainbow3D(),
          ),
        ),
      ],
    );
  }
}

class _Rainbow3D extends StatelessWidget {
  const _Rainbow3D();

  @override
  Widget build(BuildContext context) {
    return ModelViewer(
      src: 'assets/assets/icon.glb',
      alt: '3D rainbow blob',
      autoRotate: true,
      autoRotateDelay: 0,
      cameraControls: true,
      disableZoom: false,
      ar: false,
      exposure: 1.1,
    );
  }
}

class SLogoButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  const SLogoButton({super.key, required this.onTap, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: size,
        width: size,
        child: Image.asset(
          'assets/Swap-removebg-preview.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
