import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';
import 'dart:ui';
import '../models/scan_result.dart';
import '../services/history_service.dart';
import '../services/ml_service.dart';
import 'package:camera/camera.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  XFile? _capturedFile;
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool _isFlashOn = false;
  bool _hasFlash = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.high, // Use high resolution for better quality
        enableAudio: false,
      );
      await _cameraController!.initialize();
      // Check if flash is supported by trying to set flash mode
      bool hasFlash = false;
      try {
        await _cameraController!.setFlashMode(FlashMode.torch);
        hasFlash = true;
        // Turn it back off
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        hasFlash = false;
      }
      setState(() {
        _isCameraInitialized = true;
        _hasFlash = hasFlash;
      });
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_hasFlash) return;
    try {
      if (_isFlashOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
      } else {
        await _cameraController!.setFlashMode(FlashMode.torch);
      }
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureImage() async {
    if (!_isCameraInitialized || _cameraController == null) return;
    try {
      final XFile file = await _cameraController!.takePicture();
      setState(() {
        _capturedFile = file;
        _image = File(file.path);
      });
      _showResultDialog();
    } catch (e) {
      // Show error dialog if camera fails
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Camera Error'),
          content: Text('Failed to capture image: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showResultDialog() async {
    if (_image == null) return;
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF222222),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.deepPurpleAccent),
            SizedBox(width: 16),
            Text('Analyzing image...'),
          ],
        ),
      ),
    );

    try {
      // Use ML models for detection + classification
      final result = await MLService.predict(_image!);
      if (result['noDetection'] == true) {
        Navigator.of(context).pop();
        _showNoDetectionDialog(result['message'] as String? ?? 'There is no Money Detected. Please try again.');
        return;
      }

      final status = result['status'] as BillStatus;
      final confidence = result['confidence'] as int;
      final denomination = (result['denomination'] as String?) ?? '';
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      // Show result dialog
      _showFinalResultDialog(status, confidence, denomination);
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();
      
      // Show error dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Error'),
          content: Text('Failed to analyze image: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showFinalResultDialog(BillStatus status, int confidence, String denomination) {
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              _getStatusIcon(status),
              color: _getStatusColor(status),
            ),
            const SizedBox(width: 8),
            Text('${_getStatusText(status)} ${denomination.isNotEmpty ? '• ₱$denomination' : ''}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Confidence Score: $confidence%'),
            const SizedBox(height: 16),
            _image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_image!, height: 120, fit: BoxFit.cover),
                  )
                : Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.image, size: 50, color: Colors.white54),
                  ),
          ],
        ),
        actions: [
                      TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _saveToHistory(status, confidence, denomination);
              },
              child: const Text('Confirm'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _saveToHistory(status, confidence, denomination);
                // Navigate to history tab
                if (context.mounted) {
                  DefaultTabController.of(context)?.animateTo(0);
                }
              },
              child: const Text('View in History'),
            ),
        ],
      ),
    );
  }

  Future<void> _saveToHistory(BillStatus status, int confidence, String denomination) async {
    final scan = ScanResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      status: status,
      confidence: confidence,
      denomination: denomination.isNotEmpty ? '₱$denomination' : '',
      timestamp: DateTime.now(),
      imagePath: _image?.path, // Save the image path
    );
    await HistoryService.addScan(scan);
  }

  void _showNoDetectionDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF222222),
        title: const Text('No Money Detected'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(BillStatus status) {
    switch (status) {
      case BillStatus.real:
        return Icons.check_circle;
      case BillStatus.counterfeit:
        return Icons.cancel;
      case BillStatus.invalid:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(BillStatus status) {
    switch (status) {
      case BillStatus.real:
        return Colors.green;
      case BillStatus.counterfeit:
        return Colors.red;
      case BillStatus.invalid:
        return Colors.orange;
    }
  }

  String _getStatusText(BillStatus status) {
    switch (status) {
      case BillStatus.real:
        return 'Real';
      case BillStatus.counterfeit:
        return 'Counterfeit';
      case BillStatus.invalid:
        return 'Invalid';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Stack(
              children: [
                _isCameraInitialized && _cameraController != null
                    ? AspectRatio(
                        aspectRatio: 9.0 / 16.0, // Force 9:16 aspect ratio
                        child: CameraPreview(_cameraController!),
                      )
                    : const Center(
                        child: Icon(Icons.qr_code_scanner, size: 120, color: Colors.white24),
                      ),
                // Scanning frame overlay
                if (_isCameraInitialized)
                  const Positioned.fill(
                    child: ScanningFrame(),
                  ),
                // Flash button (top right)
                if (_isCameraInitialized && _hasFlash)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: Icon(
                        _isFlashOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: _toggleFlash,
                      tooltip: _isFlashOn ? 'Turn flash off' : 'Turn flash on',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Capture'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurpleAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
            onPressed: _isCameraInitialized ? _captureImage : null,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class ScanningFrame extends StatelessWidget {
  const ScanningFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ScanningFramePainter(),
      child: Container(),
    );
  }
}

class ScanningFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    // Calculate frame dimensions with margins from edges
    final margin = size.width * 0.05; // 5% margin from edges (wider frame)
    final frameWidth = size.width - (margin * 2);
    final frameHeight = size.height * 0.95; // Use 70% of screen height (top to bottom)
    final frameLeft = margin;
    final frameTop = (size.height - frameHeight) / 2; // Center vertically
    final frameRight = frameLeft + frameWidth;
    final frameBottom = frameTop + frameHeight;

    // Corner marker dimensions
    final cornerLength = 30.0;
    final cornerThickness = 4.0;

    // Top-left corner
    canvas.drawLine(
      Offset(frameLeft, frameTop + cornerLength),
      Offset(frameLeft, frameTop),
      paint..strokeWidth = cornerThickness,
    );
    canvas.drawLine(
      Offset(frameLeft, frameTop),
      Offset(frameLeft + cornerLength, frameTop),
      paint..strokeWidth = cornerThickness,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(frameRight - cornerLength, frameTop),
      Offset(frameRight, frameTop),
      paint..strokeWidth = cornerThickness,
    );
    canvas.drawLine(
      Offset(frameRight, frameTop),
      Offset(frameRight, frameTop + cornerLength),
      paint..strokeWidth = cornerThickness,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(frameLeft, frameBottom - cornerLength),
      Offset(frameLeft, frameBottom),
      paint..strokeWidth = cornerThickness,
    );
    canvas.drawLine(
      Offset(frameLeft, frameBottom),
      Offset(frameLeft + cornerLength, frameBottom),
      paint..strokeWidth = cornerThickness,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(frameRight - cornerLength, frameBottom),
      Offset(frameRight, frameBottom),
      paint..strokeWidth = cornerThickness,
    );
    canvas.drawLine(
      Offset(frameRight, frameBottom),
      Offset(frameRight, frameBottom - cornerLength),
      paint..strokeWidth = cornerThickness,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 