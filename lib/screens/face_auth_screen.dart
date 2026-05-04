import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';
import '../constants/app_constants.dart';
import '../services/api_service.dart';

enum FaceAuthMode { verify, enroll }

class FaceAuthScreen extends StatefulWidget {
  final FaceAuthMode mode;
  final String? username;
  final VoidCallback onSuccess;
  final VoidCallback onSkip;

  const FaceAuthScreen({
    super.key,
    required this.mode,
    required this.onSuccess,
    required this.onSkip,
    this.username,
  });

  @override
  State<FaceAuthScreen> createState() => _FaceAuthScreenState();
}

class _FaceAuthScreenState extends State<FaceAuthScreen>
    with SingleTickerProviderStateMixin {

  CameraController? _cam;
  bool _camReady = false;
  bool _usingFront = true; // track which camera is active

  late FaceAuthMode _mode;
  bool _processing = false;
  String? _message;
  bool _isError = false;
  bool _succeeded = false;
  bool _showRegisterOption = false;

  // Enroll: collect 3 face captures
  final List<List<double>> _capturedEmbeddings = [];
  String? _lastImageBase64;
  static const _enrollTarget = 3;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  // ML Kit face detector — with landmarks for real embeddings
  late final FaceDetector _faceDetector;

  String get _baseUrl => AppEnv.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Enable all landmarks + classifications for rich embedding
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
      ),
    );

    _initCamera(front: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _faceDetector.close();
    _disposeCamera();
    super.dispose();
  }

  Future<void> _initCamera({bool front = true}) async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) { _setMsg('No camera found.', error: true); return; }

      // Prefer front camera for face login
      final cam = cams.firstWhere(
        (c) => c.lensDirection == (front
            ? CameraLensDirection.front
            : CameraLensDirection.back),
        orElse: () => cams.first,
      );

      await _cam?.dispose();
      _cam = CameraController(cam, ResolutionPreset.high, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() { _camReady = true; _usingFront = front; });
    } catch (e) {
      _setMsg('Camera error: $e', error: true);
    }
  }

  Future<void> _flipCamera() async {
    if (_processing) return;
    setState(() => _camReady = false);
    await _initCamera(front: !_usingFront);
  }

  Future<void> _disposeCamera() async {
    try { await _cam?.dispose(); } catch (_) {}
    _cam = null;
  }

  void _setMsg(String msg, {bool error = false, bool success = false}) {
    if (!mounted) return;
    setState(() { _message = msg; _isError = error; _succeeded = success; });
  }

  // ── Capture photo, detect face, extract geometric embedding via ML Kit ────
  Future<List<double>?> _captureAndExtractEmbedding() async {
    if (_cam == null || !_cam!.value.isInitialized) return null;

    try {
      final xfile = await _cam!.takePicture();
      final bytes = await xfile.readAsBytes();
      _lastImageBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      // Use dart:io Directory.systemTemp — no path_provider plugin needed
      final tmpFile = File(
        '${Directory.systemTemp.path}/face_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tmpFile.writeAsBytes(bytes);

      final inputImage = InputImage.fromFile(tmpFile);
      final faces = await _faceDetector.processImage(inputImage);

      // Clean up
      tmpFile.deleteSync();

      if (faces.isEmpty) {
        _setMsg('No face detected. Please look directly at the camera.', error: true);
        return null;
      }

      return _buildGeometricEmbedding(faces.first);

    } catch (e) {
      _setMsg('Face detection error: $e', error: true);
      return null;
    }
  }

  // ── Build 128-float geometric embedding from ML Kit face landmarks ────────
  List<double> _buildGeometricEmbedding(Face face) {
    final bb    = face.boundingBox;
    final faceW = bb.width;
    final faceH = bb.height;
    final faceX = bb.left;
    final faceY = bb.top;

    double nx(num? x) => x == null ? 0.0 : ((x.toDouble() - faceX) / faceW * 2 - 1).clamp(-1.0, 1.0);
    double ny(num? y) => y == null ? 0.0 : ((y.toDouble() - faceY) / faceH * 2 - 1).clamp(-1.0, 1.0);

    final leftEye     = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye    = face.landmarks[FaceLandmarkType.rightEye];
    final noseBase    = face.landmarks[FaceLandmarkType.noseBase];
    final leftEar     = face.landmarks[FaceLandmarkType.leftEar];
    final rightEar    = face.landmarks[FaceLandmarkType.rightEar];
    final leftMouth   = face.landmarks[FaceLandmarkType.leftMouth];
    final rightMouth  = face.landmarks[FaceLandmarkType.rightMouth];
    final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth];
    final leftCheek   = face.landmarks[FaceLandmarkType.leftCheek];
    final rightCheek  = face.landmarks[FaceLandmarkType.rightCheek];

    final features = <double>[
      nx(leftEye?.position.x),   ny(leftEye?.position.y),
      nx(rightEye?.position.x),  ny(rightEye?.position.y),
      leftEye != null && rightEye != null
          ? (rightEye.position.x.toDouble() - leftEye.position.x.toDouble()) / faceW : 0.0,
      leftEye != null && rightEye != null
          ? (rightEye.position.y.toDouble() - leftEye.position.y.toDouble()) / faceH : 0.0,
      nx(noseBase?.position.x), ny(noseBase?.position.y),
      noseBase != null && leftEye != null
          ? sqrt(pow(noseBase.position.x.toDouble() - leftEye.position.x.toDouble(), 2) +
                 pow(noseBase.position.y.toDouble() - leftEye.position.y.toDouble(), 2)) / faceW : 0.0,
      noseBase != null && rightEye != null
          ? sqrt(pow(noseBase.position.x.toDouble() - rightEye.position.x.toDouble(), 2) +
                 pow(noseBase.position.y.toDouble() - rightEye.position.y.toDouble(), 2)) / faceW : 0.0,
      nx(leftMouth?.position.x),   ny(leftMouth?.position.y),
      nx(rightMouth?.position.x),  ny(rightMouth?.position.y),
      nx(bottomMouth?.position.x), ny(bottomMouth?.position.y),
      leftMouth != null && rightMouth != null
          ? (rightMouth.position.x.toDouble() - leftMouth.position.x.toDouble()) / faceW : 0.0,
      noseBase != null && bottomMouth != null
          ? (bottomMouth.position.y.toDouble() - noseBase.position.y.toDouble()) / faceH : 0.0,
      nx(leftEar?.position.x),  ny(leftEar?.position.y),
      nx(rightEar?.position.x), ny(rightEar?.position.y),
      nx(leftCheek?.position.x),  ny(leftCheek?.position.y),
      nx(rightCheek?.position.x), ny(rightCheek?.position.y),
      faceW > 0 ? faceH / faceW : 1.0,
      leftEye != null && bottomMouth != null
          ? (bottomMouth.position.y - leftEye.position.y) / faceH : 0.0,
      leftEye != null ? (ny(leftEye.position.y.toDouble()) + 1.0) / 2.0 : 0.5,
      leftEar != null && rightEar != null
          ? (rightEar.position.x.toDouble() - leftEar.position.x.toDouble()) / faceW : 0.0,
      (face.headEulerAngleY ?? 0.0) / 90.0,
      (face.headEulerAngleZ ?? 0.0) / 90.0,
      (face.headEulerAngleX ?? 0.0) / 90.0,
      face.leftEyeOpenProbability  ?? 0.5,
      face.rightEyeOpenProbability ?? 0.5,
      face.smilingProbability      ?? 0.0,
    ];

    final padded = List<double>.filled(128, 0.0);
    for (var i = 0; i < features.length && i < 128; i++) {
      padded[i] = features[i].clamp(-1.0, 1.0);
    }
    final baseLen = features.length;
    for (var i = baseLen; i < 128; i++) {
      final a = padded[(i - baseLen) % baseLen];
      final b = padded[(i - baseLen + 1) % baseLen];
      padded[i] = ((a * b + a - b) / 2.0).clamp(-1.0, 1.0);
    }
    final norm = sqrt(padded.fold(0.0, (s, v) => s + v * v));
    if (norm > 0.001) {
      for (var i = 0; i < 128; i++) padded[i] /= norm;
    }
    return padded;
  }

  // ── Average multiple embeddings for robust enroll ─────────────────────────
  List<double> _averageEmbeddings(List<List<double>> embeddings) {
    final avg = List<double>.filled(128, 0.0);
    for (final emb in embeddings) {
      for (var i = 0; i < 128; i++) avg[i] += emb[i];
    }
    for (var i = 0; i < 128; i++) avg[i] /= embeddings.length;
    // Re-normalise
    final norm = sqrt(avg.fold(0.0, (s, v) => s + v * v));
    if (norm > 0.001) {
      for (var i = 0; i < 128; i++) avg[i] /= norm;
    }
    return avg;
  }

  void _switchToEnroll() {
    setState(() {
      _mode = FaceAuthMode.enroll;
      _capturedEmbeddings.clear();
      _message = null;
      _isError = false;
      _showRegisterOption = false;
      _processing = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  VERIFY — POST /api/farmers/face/login/identify/
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _verify() async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _message = 'Detecting your face…';
      _isError = false;
      _showRegisterOption = false;
    });

    final embedding = await _captureAndExtractEmbedding();
    if (embedding == null) {
      setState(() => _processing = false);
      return;
    }

    _setMsg('Matching with registered faces…');

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/farmers/face/login/identify/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'embedding': embedding}),
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200) {
        final access  = data['access']  as String?;
        final refresh = data['refresh'] as String?;
        final user    = data['user']    as Map<String, dynamic>?;
        final score   = data['score']   as num?;

        if (access != null) {
          ApiService.accessToken  = access;
          ApiService.refreshToken = refresh;
          await ApiService.saveTokens();
          if (user != null) {
            final id = user['id'];
            if (id != null)
              await ApiService.saveFarmerId(
                  id is int ? id : int.tryParse(id.toString()) ?? 0);
          }
          _setMsg(
            'Face matched! ✓  (confidence: ${((score ?? 0) * 100).toStringAsFixed(0)}%)',
            success: true,
          );
          await Future.delayed(const Duration(milliseconds: 1500));
          widget.onSuccess();
        } else {
          setState(() {
            _message = 'Login response missing token.';
            _isError = true;
            _showRegisterOption = true;
            _processing = false;
          });
        }
      } else if (resp.statusCode == 400) {
        // Ambiguous match — multiple similar faces or low confidence
        final detail = data['detail'] ?? data['error'] ?? data['message'] ?? '';
        final isAmbiguous = detail.toString().toLowerCase().contains('ambiguous') ||
            detail.toString().toLowerCase().contains('multiple');
        setState(() {
          _message = isAmbiguous
              ? 'Face match is ambiguous. Please re-register your face for better accuracy.'
              : detail.toString().isNotEmpty
                  ? detail.toString()
                  : 'Could not verify face. Please try again.';
          _isError = true;
          _showRegisterOption = true;
          _processing = false;
        });
      } else if (resp.statusCode == 404 || resp.statusCode == 401) {
        final detail = data['detail'] ?? data['error'] ?? 'Face not recognised.';
        setState(() {
          _message = 'Face not found. Please register first.';
          _isError = true;
          _showRegisterOption = true;
          _processing = false;
        });
      } else {
        final detail = data['detail']?.toString() ??
            data['error']?.toString() ??
            data['message']?.toString() ??
            'Server error (${resp.statusCode})';
        setState(() {
          _message = detail;
          _isError = true;
          _showRegisterOption = true;
          _processing = false;
        });
      }
    } on TimeoutException {
      setState(() {
        _message = 'Server timed out. Is the backend running?';
        _isError = true;
        _processing = false;
      });
    } catch (e) {
      setState(() {
        _message = 'Connection error: $e';
        _isError = true;
        _processing = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ENROLL — POST /api/farmers/face/enroll/
  //  Capture 3 different poses, average embeddings → more robust profile
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _captureForEnroll() async {
    if (_processing || _capturedEmbeddings.length >= _enrollTarget) return;

    setState(() {
      _processing = true;
      _message = 'Detecting face ${_capturedEmbeddings.length + 1} of $_enrollTarget…';
      _isError = false;
    });

    final embedding = await _captureAndExtractEmbedding();
    if (embedding == null) {
      setState(() => _processing = false);
      return;
    }

    setState(() {
      _capturedEmbeddings.add(embedding);
      _processing = false;
      if (_capturedEmbeddings.length < _enrollTarget) {
        _message =
            '✓ Capture ${_capturedEmbeddings.length}/$_enrollTarget done.'
            ' Slightly tilt your head and capture again.';
        _isError = false;
      } else {
        _message = 'All $_enrollTarget captures done. Enrolling…';
      }
    });

    if (_capturedEmbeddings.length >= _enrollTarget) {
      await _submitEnroll();
    }
  }

  Future<void> _submitEnroll() async {
    setState(() => _processing = true);

    // Average the 3 embeddings — much more robust than a single capture
    final avgEmbedding = _averageEmbeddings(_capturedEmbeddings);

    try {
      final token = ApiService.accessToken;
      if (token == null) {
        _setMsg('Not logged in. Please log in with password first.',
            error: true);
        setState(() => _processing = false);
        return;
      }

      final body = <String, dynamic>{'embedding': avgEmbedding};
      if (_lastImageBase64 != null) body['image_base64'] = _lastImageBase64;

      final resp = await http.post(
        Uri.parse('$_baseUrl/api/farmers/face/enroll/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        _setMsg('✅ Face registered successfully! You can now login with your face.', success: true);
        setState(() { _processing = false; _succeeded = true; });
        // Show success clearly for 3 seconds before navigating
        await Future.delayed(const Duration(milliseconds: 3000));
        if (mounted) widget.onSuccess();
      } else {
        setState(() {
          _capturedEmbeddings.clear();
          _message = data['detail']?.toString() ??
              data['error']?.toString() ??
              'Enrollment failed (${resp.statusCode}). Try again.';
          _isError = true;
          _processing = false;
        });
      }
    } on TimeoutException {
      setState(() {
        _capturedEmbeddings.clear();
        _message = 'Server timed out during enrollment.';
        _isError = true;
        _processing = false;
      });
    } catch (e) {
      setState(() {
        _capturedEmbeddings.clear();
        _message = 'Connection error: $e';
        _isError = true;
        _processing = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isEnroll = _mode == FaceAuthMode.enroll;
    return Scaffold(
      backgroundColor: const Color(0xFF080F09),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: widget.onSkip,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white60, size: 18),
                  ),
                ),
                const Spacer(),
                Text(isEnroll ? 'Register Face' : 'Face Login',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                const SizedBox(width: 40),
              ]),
            ),
            const SizedBox(height: 6),
            Text(
              isEnroll
                  ? 'Capture $_enrollTarget photos from different angles'
                  : 'Look at the camera and tap Scan Face',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Camera oval
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Transform.scale(
                  scale: _processing ? _pulse.value : 1.0, child: child),
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: 264, height: 316,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(150),
                    boxShadow: [BoxShadow(
                      color: (_succeeded ? Colors.green : AppColors.primary)
                          .withOpacity(_processing ? 0.5 : 0.25),
                      blurRadius: 28, spreadRadius: 4,
                    )],
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(150),
                  child: SizedBox(
                    width: 256, height: 308,
                    child: _camReady
                        ? Transform(
                            // Correct for front camera mirror + any rotation
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..rotateY(_usingFront ? 3.14159 : 0), // mirror front cam horizontally
                            child: CameraPreview(_cam!),
                          )
                        : Container(
                            color: const Color(0xFF1A2E1B),
                            child: const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary,
                                    strokeWidth: 2))),
                  ),
                ),
                // Flip camera button — top right of preview
                Positioned(
                  top: 12, right: 28,
                  child: GestureDetector(
                    onTap: _flipCamera,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.55),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Icon(Icons.flip_camera_android_rounded,
                          color: Colors.white70, size: 20),
                    ),
                  ),
                ),
                Container(
                  width: 256, height: 308,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(150),
                    border: Border.all(
                      color: _succeeded
                          ? Colors.green
                          : AppColors.primary.withOpacity(0.7),
                      width: 2.5,
                    ),
                  ),
                ),
                Positioned(top: 6,    left: 22,  child: _corner(true,  true)),
                Positioned(top: 6,    right: 22, child: _corner(false, true)),
                Positioned(bottom: 6, left: 22,  child: _corner(true,  false)),
                Positioned(bottom: 6, right: 22, child: _corner(false, false)),
              ]),
            ),

            const SizedBox(height: 16),

            // Enroll progress dots
            if (isEnroll)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_enrollTarget, (i) =>
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width:  i < _capturedEmbeddings.length ? 14 : 10,
                    height: i < _capturedEmbeddings.length ? 14 : 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _capturedEmbeddings.length
                          ? AppColors.primary
                          : Colors.white24,
                    ),
                  )),
              ),

            const SizedBox(height: 12),

            // ML Kit badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.30)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.face_retouching_natural,
                    color: AppColors.primary, size: 13),
                SizedBox(width: 5),
                Text('ML Kit Face Detection',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppColors.primary, letterSpacing: 0.4)),
              ]),
            ),

            const SizedBox(height: 10),

            // Status message
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _succeeded
                        ? Colors.green.withOpacity(0.12)
                        : _isError
                            ? Colors.red.withOpacity(0.10)
                            : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _succeeded
                        ? Colors.green.withOpacity(0.4)
                        : _isError
                            ? Colors.red.withOpacity(0.3)
                            : Colors.transparent),
                  ),
                  child: Row(children: [
                    Icon(
                      _succeeded
                          ? Icons.check_circle_outline
                          : _isError
                              ? Icons.error_outline
                              : Icons.info_outline,
                      color: _succeeded
                          ? Colors.greenAccent
                          : _isError ? Colors.redAccent : Colors.white54,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_message!,
                        style: TextStyle(
                          color: _succeeded
                              ? Colors.greenAccent
                              : _isError ? Colors.redAccent : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ))),
                  ]),
                ),
              ),

            const SizedBox(height: 14),

            // Main action button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: (_processing || !_camReady)
                      ? null
                      : (isEnroll ? _captureForEnroll : _verify),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withOpacity(0.35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _processing
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text(
                          isEnroll
                              ? (_capturedEmbeddings.isEmpty
                                  ? 'Capture Photo 1'
                                  : 'Capture Photo ${_capturedEmbeddings.length + 1}')
                              : 'Scan Face',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ),

            const SizedBox(height: 10),

            if (_showRegisterOption && !isEnroll)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: SizedBox(
                  width: double.infinity, height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _switchToEnroll,
                    icon: const Icon(Icons.face_retouching_natural,
                        color: AppColors.primary, size: 20),
                    label: const Text('Register Face Instead',
                        style: TextStyle(color: AppColors.primary,
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),

            TextButton(
              onPressed: widget.onSkip,
              child: Text(
                isEnroll ? '← Back to Login' : 'Use Password Instead',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }

  Widget _corner(bool left, bool top) => SizedBox(
    width: 24, height: 24,
    child: CustomPaint(
        painter: _CornerPainter(AppColors.primary, 2.5, left, top)),
  );
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thick;
  final bool left, top;
  const _CornerPainter(this.color, this.thick, this.left, this.top);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = thick
      ..strokeCap = StrokeCap.round;
    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final dx = left ? size.width : -size.width;
    final dy = top ? size.height : -size.height;
    canvas.drawLine(Offset(x, y), Offset(x + dx, y), p);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), p);
  }

  @override
  bool shouldRepaint(_) => false;
}
