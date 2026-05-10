import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart'
    if (dart.library.html) 'google_sign_in_stub.dart';
import 'main.dart';
import 'home_screen.dart';
import 'notification_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscure = true;
  String _error = '';
  // After sign-up: show email verification waiting screen
  bool _awaitingVerification = false;
  User? _unverifiedUser;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ─── SUBMIT ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();
    final name = _nameCtrl.text.trim();

    if (!_isLogin && name.isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter email and password.');
      return;
    }
    if (!_isLogin && password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() { _loading = true; _error = ''; });

    try {
      if (_isLogin) {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        // Block unverified email/password users
        if (cred.user != null && !cred.user!.emailVerified) {
          _unverifiedUser = cred.user;
          if (mounted) setState(() { _awaitingVerification = true; _loading = false; });
          return;
        }
        await NotificationService.scheduleAllReminders();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(_smoothRoute(const HomeScreen()));
      } else {
        // Sign up
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await cred.user?.updateDisplayName(name);
        // Send verification email
        await cred.user?.sendEmailVerification();
        _unverifiedUser = cred.user;
        if (mounted) setState(() { _awaitingVerification = true; _loading = false; });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _msg(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── CHECK VERIFICATION ──────────────────────────────────────────────────

  Future<void> _checkVerification() async {
    setState(() => _loading = true);
    try {
      await _unverifiedUser?.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        await NotificationService.scheduleAllReminders();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(_smoothRoute(const HomeScreen()));
      } else {
        if (mounted) {
          setState(() => _error = 'Email not verified yet. Check your inbox and try again.');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not check verification. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendVerification() async {
    setState(() { _loading = true; _error = ''; });
    try {
      await _unverifiedUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Verification email sent!', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.success.withOpacity(0.85),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to resend. Try again shortly.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _backToLogin() {
    _unverifiedUser?.delete().catchError((_) {});
    FirebaseAuth.instance.signOut().catchError((_) {});
    if (mounted) {
      setState(() {
        _awaitingVerification = false;
        _unverifiedUser = null;
        _isLogin = true;
        _error = '';
      });
    }
  }

  // ─── FORGOT PASSWORD ──────────────────────────────────────────────────────

  void _showForgotPassword() {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    bool sending = false;
    bool sent = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(
                width: 36, height: 4, color: AppColors.border)),
            const SizedBox(height: 20),
            Text('Reset Password',
                style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
                sent
                    ? 'A reset link has been sent. Check your inbox.'
                    : 'Enter your email and we\'ll send a reset link.',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            if (!sent) ...[
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.emailAddress,
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  hintStyle:
                      GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
                  prefixIcon: const Icon(Icons.mail_outline_rounded,
                      color: AppColors.textSecondary, size: 21),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide:
                        BorderSide(color: AppColors.border.withOpacity(0.8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide:
                        BorderSide(color: AppColors.border.withOpacity(0.8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                        color: AppColors.accent.withOpacity(0.8), width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: sending
                    ? null
                    : () async {
                        final email = ctrl.text.trim();
                        if (email.isEmpty) return;
                        setS(() => sending = true);
                        try {
                          await FirebaseAuth.instance
                              .sendPasswordResetEmail(email: email);
                          setS(() { sending = false; sent = true; });
                        } on FirebaseAuthException catch (e) {
                          setS(() => sending = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(_msg(e.code),
                                style: GoogleFonts.dmSans()),
                            backgroundColor: AppColors.danger,
                          ));
                        }
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 56,
                  decoration: BoxDecoration(
                    color: sending
                        ? AppColors.accent.withOpacity(0.55)
                        : AppColors.accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : Text('Send Reset Link',
                            style: GoogleFonts.dmSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Icon(Icons.mark_email_read_rounded,
                  color: AppColors.success, size: 48),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: AppColors.border.withOpacity(0.85)),
                  ),
                  child: Center(
                    child: Text('Done',
                        style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  // ─── GOOGLE SIGN IN ──────────────────────────────────────────────────────

  Future<void> _googleSignIn() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Google Sign-In works on the Android app build.',
            style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.card,
      ));
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await NotificationService.scheduleAllReminders();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(_smoothRoute(const HomeScreen()));
    } catch (_) {
      if (mounted) setState(() => _error = 'Google sign in failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── ROUTING ─────────────────────────────────────────────────────────────

  PageRouteBuilder _smoothRoute(Widget page) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  String _msg(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'No internet connection. Check your network.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in Firebase.';
      default:
        return 'Something went wrong. Try again.';
    }
  }

  void _toggleMode() {
    setState(() { _isLogin = !_isLogin; _error = ''; _obscure = true; });
  }

  // ─── BUILD ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_awaitingVerification) return _verificationScreen();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 42),
                        _brandHeader(),
                        const SizedBox(height: 38),
                        _authCard(),
                        const SizedBox(height: 18),
                        _switchModeText(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── EMAIL VERIFICATION WAITING SCREEN ───────────────────────────────────

  Widget _verificationScreen() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mark_email_unread_rounded,
                  color: AppColors.accent, size: 72),
              const SizedBox(height: 28),
              Text('Verify your email',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5)),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to\n${_unverifiedUser?.email ?? ''}',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.6),
              ),
              const SizedBox(height: 8),
              Text(
                'Open your email app, tap the link, then come back here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    height: 1.5),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                _errorBox(),
              ],
              const SizedBox(height: 36),
              // Primary: I've verified
              _primaryButton('I\'ve verified — Continue', _checkVerification),
              const SizedBox(height: 12),
              // Secondary: resend
              GestureDetector(
                onTap: _loading ? null : _resendVerification,
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border:
                        Border.all(color: AppColors.border.withOpacity(0.85)),
                  ),
                  child: Center(
                    child: Text('Resend verification email',
                        style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _backToLogin,
                child: Center(
                  child: Text('← Back to sign in',
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── WIDGETS ─────────────────────────────────────────────────────────────

  Widget _brandHeader() {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.accent.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(Icons.directions_run_rounded,
              color: AppColors.accent, size: 36),
        ),
        const SizedBox(height: 18),
        Text(
          'FitQuest',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Fitness that feels rewarding.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _authCard() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey(_isLogin),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border.withOpacity(0.75)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isLogin ? 'Welcome back' : 'Create account',
              style: GoogleFonts.dmSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isLogin
                  ? 'Sign in to continue your progress.'
                  : 'Start your fitness quest today.',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            if (!_isLogin) ...[
              _label('Name'),
              const SizedBox(height: 8),
              _field(_nameCtrl, 'Your name', Icons.person_outline_rounded,
                  action: TextInputAction.next),
              const SizedBox(height: 16),
            ],
            _label('Email'),
            const SizedBox(height: 8),
            _field(_emailCtrl, 'you@example.com', Icons.mail_outline_rounded,
                type: TextInputType.emailAddress, action: TextInputAction.next),
            const SizedBox(height: 16),
            _label('Password'),
            const SizedBox(height: 8),
            _field(
              _passCtrl,
              '••••••••',
              Icons.lock_outline_rounded,
              obscure: _obscure,
              action: TextInputAction.done,
              onSubmit: _submit,
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            // Forgot password (login mode only)
            if (_isLogin) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: _showForgotPassword,
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 14),
              _errorBox(),
            ],
            const SizedBox(height: 22),
            _primaryButton(_isLogin ? 'Sign in' : 'Create account', _submit),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: Divider(color: AppColors.border.withOpacity(0.8))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
              Expanded(
                  child: Divider(color: AppColors.border.withOpacity(0.8))),
            ]),
            const SizedBox(height: 16),
            _googleButton(),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(text,
        style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary));
  }

  Widget _field(
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType? type,
    bool obscure = false,
    Widget? suffix,
    TextInputAction action = TextInputAction.next,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: controller,
      keyboardType: type,
      obscureText: obscure,
      textInputAction: action,
      onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
      style: GoogleFonts.dmSans(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 21),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.border.withOpacity(0.8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.border.withOpacity(0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              BorderSide(color: AppColors.accent.withOpacity(0.8), width: 1.4),
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: _loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 56,
        decoration: BoxDecoration(
          color: _loading
              ? AppColors.accent.withOpacity(0.55)
              : AppColors.accent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            if (!_loading)
              BoxShadow(
                color: AppColors.accent.withOpacity(0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Center(
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white))
              : Text(label,
                  style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
        ),
      ),
    );
  }

  Widget _googleButton() {
    return GestureDetector(
      onTap: _loading ? null : _googleSignIn,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withOpacity(0.85)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('G',
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 10),
          Text('Continue with Google',
              style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ]),
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded,
            color: AppColors.danger, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_error,
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger)),
        ),
      ]),
    );
  }

  Widget _switchModeText() {
    return Center(
      child: GestureDetector(
        onTap: _loading ? null : _toggleMode,
        child: RichText(
          text: TextSpan(
            style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textSecondary),
            children: [
              TextSpan(
                text: _isLogin
                    ? "Don't have an account? "
                    : 'Already have an account? ',
              ),
              TextSpan(
                text: _isLogin ? 'Sign up' : 'Sign in',
                style: GoogleFonts.dmSans(
                    color: AppColors.accent, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
