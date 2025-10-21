import 'dart:convert';
import 'package:flutter/material.dart';

enum BillStatus {
  real,
  counterfeit,
  invalid,
}

class ScanResult {
  final String id;
  final BillStatus status;
  final int confidence;
  final String denomination;
  final DateTime timestamp;
  final String? imagePath; // Path to the captured image

  ScanResult({
    required this.id,
    required this.status,
    required this.confidence,
    required this.denomination,
    required this.timestamp,
    this.imagePath,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status.name,
      'confidence': confidence,
      'denomination': denomination,
      'timestamp': timestamp.toIso8601String(),
      'imagePath': imagePath,
    };
  }

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      id: json['id'],
      status: BillStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => BillStatus.invalid,
      ),
      confidence: json['confidence'],
      denomination: json['denomination'],
      timestamp: DateTime.parse(json['timestamp']),
      imagePath: json['imagePath'],
    );
  }

  // Helper methods for backward compatibility
  bool get isReal => status == BillStatus.real;
  bool get isCounterfeit => status == BillStatus.counterfeit;
  bool get isInvalid => status == BillStatus.invalid;

  String get statusText {
    switch (status) {
      case BillStatus.real:
        return 'Real';
      case BillStatus.counterfeit:
        return 'Counterfeit';
      case BillStatus.invalid:
        return 'Invalid';
    }
  }

  Color get statusColor {
    switch (status) {
      case BillStatus.real:
        return Colors.green;
      case BillStatus.counterfeit:
        return Colors.red;
      case BillStatus.invalid:
        return Colors.orange;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case BillStatus.real:
        return Icons.check_circle;
      case BillStatus.counterfeit:
        return Icons.cancel;
      case BillStatus.invalid:
        return Icons.help_outline;
    }
  }
} 