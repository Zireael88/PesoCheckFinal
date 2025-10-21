import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/scan_result.dart';

class HistoryService {
  static const String _key = 'scan_history';

  static Future<List<ScanResult>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString(_key);
    if (historyJson == null) return [];
    
    final List<dynamic> historyList = json.decode(historyJson);
    return historyList.map((json) => ScanResult.fromJson(json)).toList();
  }

  static Future<void> addScan(ScanResult scan) async {
    final prefs = await SharedPreferences.getInstance();
    final List<ScanResult> history = await getHistory();
    history.insert(0, scan); // Add to beginning
    
    final List<Map<String, dynamic>> historyJson = history.map((s) => s.toJson()).toList();
    await prefs.setString(_key, json.encode(historyJson));
  }

  static Future<void> deleteScan(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<ScanResult> history = await getHistory();
    history.removeWhere((scan) => scan.id == id);
    
    final List<Map<String, dynamic>> historyJson = history.map((s) => s.toJson()).toList();
    await prefs.setString(_key, json.encode(historyJson));
  }
} 