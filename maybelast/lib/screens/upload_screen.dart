import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';
import '../models/scan_result.dart';
import '../services/history_service.dart';
import '../services/ml_service.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _image;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
        });
        _showResultDialog();
      }
    } catch (e) {
      // Show error dialog if gallery fails
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          title: const Text('Gallery Error'),
          content: Text('Failed to pick image: $e'),
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
            _image != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_image!, height: 200, fit: BoxFit.cover),
                  )
                : const Icon(Icons.upload_file, size: 120, color: Colors.white24),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Upload from Gallery'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: _pickImage,
            ),
          ],
        ),
    );
  }
} 