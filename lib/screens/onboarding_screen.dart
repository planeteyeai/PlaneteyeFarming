import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../constants/app_constants.dart';
import '../services/api_service.dart';
import 'face_auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  // action values: 'register' | 'google_signin' | 'daily_check'
  // For phone login, passes 'phone_login' with extra data via onLoginSuccess
  final void Function(String action) onAction;
  final void Function(Map<String, dynamic> loginData)? onLoginSuccess;
  // Called when farmer logs in successfully via Face ID (no server token needed)
  final VoidCallback? onFaceLogin;

  const OnboardingScreen({
    super.key,
    required this.onAction,
    this.onLoginSuccess,
    this.onFaceLogin,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl, _contentCtrl;
  late Animation<double> _bgAnim, _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _googleLoading = false;

  static final _googleSignInClient = GoogleSignIn(scopes: ['email', 'profile']);

  // ── Real Google Sign-In flow ────────────────────────────────────
  Future<void> _handleGoogleSignIn(BuildContext context) async {
    setState(() => _googleLoading = true);
    try {
      // Trigger Google account picker
      final account = await _googleSignInClient.signIn();
      if (account == null) {
        // User cancelled
        setState(() => _googleLoading = false);
        return;
      }

      // Get id_token from Google
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        setState(() => _googleLoading = false);
        _showError(context, 'Could not get Google token. Please try again.');
        return;
      }

      // POST /api/farmers/auth/google/
      final data = await ApiService.googleSignIn(idToken: idToken);

      setState(() => _googleLoading = false);

      // Pass login data up — same handler as phone login
      if (widget.onLoginSuccess != null) {
        // Normalise user.id as farmer_id for the shared handler
        final user = data['user'] as Map<String, dynamic>?;
        final enriched = {
          ...data,
          'farmer_id': user?['id'] ?? data['farmer_id'],
        };
        widget.onLoginSuccess!(enriched);
      } else {
        widget.onAction('google_signin');
      }
    } catch (e) {
      setState(() => _googleLoading = false);
      if (context.mounted) {
        _showError(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: Colors.red.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _contentCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _bgAnim = Tween<double>(begin: 0.05, end: 0.13).animate(_bgCtrl);
    _fadeAnim = CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut);
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
            CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  // ── Forgot Password flow ─────────────────────────────────────────
  // Step 1: Enter email → receive reset link
  // Step 2: Enter uid + token (from link) + new password
  void _showForgotPassword(BuildContext context) {
    // Close the login sheet first, then open forgot-password sheet
    Navigator.pop(context);

    // ── Step 1 state ──
    final emailCtrl = TextEditingController();
    bool loading = false;
    String? error;
    String? successMsg;
    bool showStep2 = false;

    // ── Step 2 state ──
    final uidCtrl   = TextEditingController();
    final tokenCtrl = TextEditingController();
    final newPassCtrl   = TextEditingController();
    bool obscureNew  = true;
    bool step2Done   = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {

          // ── Send forgot-password email ──
          Future<void> doRequestReset() async {
            final email = emailCtrl.text.trim();
            if (email.isEmpty || !email.contains('@')) {
              setSheet(() => error = 'Please enter a valid email address.');
              return;
            }
            setSheet(() { loading = true; error = null; successMsg = null; });
            try {
              final msg = await ApiService.forgotPassword(email: email);
              setSheet(() {
                loading    = false;
                successMsg = msg;
                showStep2  = true;
              });
            } catch (e) {
              setSheet(() {
                loading = false;
                error   = e.toString().replaceFirst('Exception: ', '');
              });
            }
          }

          // ── Confirm new password ──
          Future<void> doResetPassword() async {
            final uid   = uidCtrl.text.trim();
            final token = tokenCtrl.text.trim();
            final pass  = newPassCtrl.text;
            if (uid.isEmpty || token.isEmpty) {
              setSheet(() => error = 'Please enter the UID and token from your reset link.');
              return;
            }
            if (pass.length < 8) {
              setSheet(() => error = 'Password must be at least 8 characters.');
              return;
            }
            setSheet(() { loading = true; error = null; });
            try {
              await ApiService.resetPassword(
                  uid: uid, token: token, newPassword: pass);
              setSheet(() { loading = false; step2Done = true; });
            } catch (e) {
              setSheet(() {
                loading = false;
                error   = e.toString().replaceFirst('Exception: ', '');
              });
            }
          }

          // ── Handle "Back to login" inside sheet ──
          void goBackToLogin() {
            Navigator.pop(ctx);
            _showPhoneLogin(context);
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Handle bar
                Container(
                    width: 44, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2))),

                // Icon + title
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                      color: AppColors.greenLight, shape: BoxShape.circle),
                  child: Icon(
                    step2Done
                        ? Icons.check_circle_outline
                        : showStep2
                            ? Icons.lock_reset
                            : Icons.lock_open_outlined,
                    color: AppColors.primary, size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  step2Done
                      ? 'Password Reset!'
                      : showStep2
                          ? 'Set New Password'
                          : 'Forgot Password',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  step2Done
                      ? 'Your password has been updated. You can now sign in.'
                      : showStep2
                          ? 'Enter the UID & token from the reset link.'
                          : "Enter your email and we'll send a reset link.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMedium,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),

                // ── Success state ──────────────────────────────────
                if (step2Done) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEBF5E6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3))),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('All done! Use your new password to sign in.',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: goBackToLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32)),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 4,
                      ),
                      child: const Text('Back to Sign In',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ]

                // ── Step 2: new password form ──────────────────────
                else if (showStep2) ...[
                  // Email sent banner
                  if (successMsg != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFEBF5E6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3))),
                      child: Row(children: [
                        const Icon(Icons.mail_outline,
                            color: AppColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(successMsg!,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),

                  // Error banner
                  if (error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Row(children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade400, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(error!,
                              style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),

                  _sheetField(
                    controller: uidCtrl,
                    label: 'UID',
                    hint: 'From the reset link',
                    icon: Icons.tag_outlined,
                    enabled: !loading,
                  ),
                  const SizedBox(height: 14),
                  _sheetField(
                    controller: tokenCtrl,
                    label: 'Token',
                    hint: 'From the reset link',
                    icon: Icons.vpn_key_outlined,
                    enabled: !loading,
                  ),
                  const SizedBox(height: 14),
                  _sheetField(
                    controller: newPassCtrl,
                    label: 'New Password',
                    hint: '••••••••',
                    icon: Icons.lock_outline,
                    keyboard: TextInputType.visiblePassword,
                    obscure: obscureNew,
                    enabled: !loading,
                    suffix: GestureDetector(
                      onTap: () => setSheet(() => obscureNew = !obscureNew),
                      child: Icon(
                          obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textLight, size: 20),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : doResetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withOpacity(0.6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32)),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 4,
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 3, color: Colors.white))
                          : const Text('Reset Password',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: loading ? null : goBackToLogin,
                    child: const Text('Back to Sign In',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                ]

                // ── Step 1: email form ─────────────────────────────
                else ...[
                  // Error banner
                  if (error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Row(children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade400, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(error!,
                              style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),

                  _sheetField(
                    controller: emailCtrl,
                    label: 'Email Address',
                    hint: 'farmer@example.com',
                    icon: Icons.mail_outline,
                    keyboard: TextInputType.emailAddress,
                    enabled: !loading,
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : doRequestReset,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withOpacity(0.6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(32)),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 4,
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 3, color: Colors.white))
                          : const Text('Send Reset Link',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: goBackToLogin,
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textMedium),
                        children: [
                          TextSpan(text: 'Remembered it? '),
                          TextSpan(
                              text: 'Sign In',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Phone + Password Login bottom sheet ──────────────────────────
  void _showPhoneLogin(BuildContext context) {
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool loading = false;
    bool obscurePass = true;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> doLogin() async {
            final phone = phoneCtrl.text.trim();
            final pass = passCtrl.text;

            if (phone.isEmpty || pass.isEmpty) {
              setSheet(() => error = 'Please enter phone number and password.');
              return;
            }

            setSheet(() { loading = true; error = null; });

            // ── Developer test account (no network needed) ────────
            const _testPhone = '9325657201';
            const _testPass  = 'pari@123';
            final cleanPhone = phone.replaceAll(RegExp(r'[\s\-\+]'), '');

            if ((cleanPhone == _testPhone || phone == '+91$_testPhone') &&
                pass == _testPass) {
              await Future.delayed(const Duration(milliseconds: 600));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              final testData = {
                'access':        'test_access_token',
                'refresh':       'test_refresh_token',
                'farmer_id':     1,
                '_bypass_login': true,          // ← skip API, go to dashboard
                'user': {
                  'id':           1,
                  'first_name':   'Developer',
                  'last_name':    'Test',
                  'username':     'devtest',
                  'email':        'dev@cropeye.app',
                  'phone_number': _testPhone,
                },
              };
              // Store mock tokens so API calls don't fail on auth
              ApiService.accessToken  = 'test_access_token';
              ApiService.refreshToken = 'test_refresh_token';
              ApiService.farmerId     = 1;
              if (widget.onLoginSuccess != null) {
                widget.onLoginSuccess!(testData);
              } else {
                widget.onAction('phone_login');
              }
              return;
            }

            try {
              // ── POST /api/farmers/login/ ──────────────────────────
              final data = await ApiService.login(
                phoneNumber: phone,
                password: pass,
              );

              if (!ctx.mounted) return;
              Navigator.pop(ctx); // close sheet

              // Pass login response up — contains farmer_id, access, refresh
              if (widget.onLoginSuccess != null) {
                widget.onLoginSuccess!(data);
              } else {
                widget.onAction('phone_login');
              }
            } catch (e) {
              setSheet(() {
                loading = false;
                error = e.toString().replaceFirst('Exception: ', '');
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(36)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Handle bar
                Container(
                    width: 44, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2))),

                // Icon + title
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.phone_android,
                      color: AppColors.primary, size: 28),
                ),
                const SizedBox(height: 12),
                const Text('Sign In',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textDark)),
                const SizedBox(height: 4),
                const Text('Use your registered phone & password',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMedium,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),

                // Error banner
                if (error != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.shade200)),
                    child: Row(children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(error!,
                              style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ],

                // Phone number field
                _sheetField(
                  controller: phoneCtrl,
                  label: 'Phone Number',
                  hint: '+91 98765 43210',
                  icon: Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                  enabled: !loading,
                ),
                const SizedBox(height: 14),

                // Password field
                _sheetField(
                  controller: passCtrl,
                  label: 'Password',
                  hint: '••••••••',
                  icon: Icons.lock_outline,
                  keyboard: TextInputType.visiblePassword,
                  obscure: obscurePass,
                  enabled: !loading,
                  suffix: GestureDetector(
                    onTap: () =>
                        setSheet(() => obscurePass = !obscurePass),
                    child: Icon(
                        obscurePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textLight,
                        size: 20),
                  ),
                ),

                // Forgot password link
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, right: 4),
                    child: GestureDetector(
                      onTap: loading
                          ? null
                          : () => _showForgotPassword(ctx),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Login button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : doLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 18),
                      elevation: 4,
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Colors.white))
                        : const Text('Sign In',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Face ID login button ──────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: loading ? null : () {
                      Navigator.pop(ctx);
                      // Open FaceAuthScreen in verify mode
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => FaceAuthScreen(
                          mode: FaceAuthMode.verify,
                          onSuccess: () {
                            Navigator.of(context).pop(); // close FaceAuthScreen
                            if (widget.onFaceLogin != null) {
                              widget.onFaceLogin!();
                            }
                          },
                          onSkip: () => Navigator.of(context).pop(),
                        )),
                      );
                    },
                    icon: const Icon(Icons.face_retouching_natural, size: 20),
                    label: const Text('Login with Face ID',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onAction('register');
                  },
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textMedium),
                      children: [
                        TextSpan(text: "Don't have an account? "),
                        TextSpan(
                            text: 'Register',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
    bool enabled = true,
    Widget? suffix,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: AppColors.textLight,
                letterSpacing: 1.5)),
      ),
      TextField(
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        enabled: enabled,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: AppColors.textLight, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.background,
          hintStyle: const TextStyle(
              color: AppColors.textLight, fontWeight: FontWeight.w500),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide:
                  const BorderSide(color: AppColors.borderLight, width: 2)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide:
                  const BorderSide(color: AppColors.borderLight, width: 2)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2)),
          disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(
                  color: AppColors.borderLight.withOpacity(0.5), width: 2)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
            fontSize: 15),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        // Animated blobs
        AnimatedBuilder(
          animation: _bgAnim,
          builder: (_, __) => Stack(children: [
            Positioned(
                top: -80, right: -80,
                child: Container(
                    width: 260, height: 260,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            AppColors.primary.withOpacity(_bgAnim.value)))),
            Positioned(
                bottom: -80, left: -80,
                child: Container(
                    width: 320, height: 320,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent
                            .withOpacity(_bgAnim.value * 0.5)))),
          ]),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              const Spacer(),

              // Hero image card
              FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Container(
                    height: 260, width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(48),
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 30,
                            offset: const Offset(0, 10))
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(44),
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network(
                          'https://images.unsplash.com/photo-1500382017468-9049fed747ef?auto=format&fit=crop&w=800&q=80',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF2D5A27),
                              child: const Icon(Icons.agriculture,
                                  size: 80, color: Colors.white54)),
                        ),
                        Container(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.65)
                              ])),
                        ),
                        Positioned(
                            bottom: 24, left: 28, right: 28,
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Welcome,\nFarmer',
                                      style: TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          height: 1.1)),
                                  const SizedBox(height: 8),
                                  Container(
                                      height: 4, width: 44,
                                      decoration: BoxDecoration(
                                          color: AppColors.accent,
                                          borderRadius:
                                              BorderRadius.circular(2))),
                                ])),
                      ]),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              FadeTransition(
                opacity: _fadeAnim,
                child: const Text(
                  'Empowering your fields with AI-driven precision and satellite insights.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMedium,
                      height: 1.5),
                ),
              ),

              const Spacer(),

              FadeTransition(
                opacity: _fadeAnim,
                child: Column(children: [

                  // ── Register new farm ────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => widget.onAction('register'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 20),
                        elevation: 8,
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text('Register the Farm',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17)),
                            SizedBox(width: 10),
                            Icon(Icons.agriculture, size: 22),
                          ]),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Divider ──────────────────────────────────────
                  Row(children: [
                    Expanded(
                        child: Container(
                            height: 1, color: AppColors.borderLight)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Text('OR SIGN IN WITH',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textLight,
                              letterSpacing: 1.5)),
                    ),
                    Expanded(
                        child: Container(
                            height: 1, color: AppColors.borderLight)),
                  ]),
                  const SizedBox(height: 14),

                  // ── Google + Phone sign in ───────────────────────
                  Row(children: [
                    // Google
                    Expanded(
                      child: GestureDetector(
                        onTap: _googleLoading ? null : () => _handleGoogleSignIn(context),
                        child: _signInCard(
                          child: Column(children: [
                            _googleLoading
                                ? const SizedBox(
                                    width: 38, height: 38,
                                    child: Center(
                                      child: SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: AppColors.primary),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 38, height: 38,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        border: Border.all(
                                            color: AppColors.borderLight,
                                            width: 1.5)),
                                    child: Center(
                                      child: RichText(
                                        text: const TextSpan(children: [
                                          TextSpan(
                                              text: 'G',
                                              style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  color: Color(0xFF4285F4))),
                                        ]),
                                      ),
                                    ),
                                  ),
                            const SizedBox(height: 8),
                            Text(_googleLoading ? 'Signing in...' : 'Google',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textDark)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Phone login
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showPhoneLogin(context),
                        child: _signInCard(
                          child: Column(children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.greenLight,
                                  border: Border.all(
                                      color: AppColors.primary
                                          .withOpacity(0.25),
                                      width: 1.5)),
                              child: const Icon(Icons.phone_android,
                                  color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(height: 8),
                            const Text('Phone',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textDark)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  // ── Daily check (skip) ───────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => widget.onAction('daily_check'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMedium,
                        side: const BorderSide(
                            color: AppColors.borderLight, width: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(40)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text('Begin Daily Check',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            SizedBox(width: 10),
                            Icon(Icons.check_circle_outline, size: 20),
                          ]),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 36),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _signInCard({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderLight, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05), blurRadius: 12)
          ],
        ),
        child: child,
      );
}