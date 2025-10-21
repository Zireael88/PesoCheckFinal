import '../models/scan_result.dart';
import 'dart:convert';

class ExportService {
  static String exportToCSV(List<ScanResult> scans) {
    final StringBuffer csv = StringBuffer();
    
    // CSV Header
    csv.writeln('ID,Status,Confidence,Denomination,Date,Time');
    
    // CSV Data
    for (final scan in scans) {
      final status = scan.statusText;
      final date = '${scan.timestamp.day}/${scan.timestamp.month}/${scan.timestamp.year}';
      final time = '${scan.timestamp.hour}:${scan.timestamp.minute.toString().padLeft(2, '0')}';
      
      csv.writeln('${scan.id},$status,${scan.confidence}%,${scan.denomination},$date,$time');
    }
    
    return csv.toString();
  }

  static String exportToJSON(List<ScanResult> scans) {
    final List<Map<String, dynamic>> jsonData = scans.map((scan) => scan.toJson()).toList();
    return json.encode(jsonData);
  }

  static Map<String, dynamic> generateReport(List<ScanResult> scans) {
    final totalScans = scans.length;
    final realScans = scans.where((scan) => scan.status == BillStatus.real).length;
    final counterfeitScans = scans.where((scan) => scan.status == BillStatus.counterfeit).length;
    final invalidScans = scans.where((scan) => scan.status == BillStatus.invalid).length;
    final avgConfidence = totalScans > 0 
        ? scans.map((scan) => scan.confidence).reduce((a, b) => a + b) / totalScans 
        : 0.0;

    return {
      'summary': {
        'totalScans': totalScans,
        'realBills': realScans,
        'counterfeitBills': counterfeitScans,
        'invalidBills': invalidScans,
        'realPercentage': totalScans > 0 ? (realScans / totalScans * 100) : 0,
        'counterfeitPercentage': totalScans > 0 ? (counterfeitScans / totalScans * 100) : 0,
        'invalidPercentage': totalScans > 0 ? (invalidScans / totalScans * 100) : 0,
        'averageConfidence': avgConfidence,
      },
      'scans': scans.map((scan) => scan.toJson()).toList(),
      'exportDate': DateTime.now().toIso8601String(),
    };
  }
} 