// COMPLETE REPLACEMENT FOR ml_service.dart
// This version adds critical debugging and handles potential quantization issues

import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../models/scan_result.dart';

const int PREPROCESSING_METHOD = 4;

class MLService {
  static Interpreter? _yoloInterpreter;
  static Interpreter? _efficientNetInterpreter;
  static bool _isInitialized = false;

  static const int _inputSize = 640;
  static const List<String> _yoloClasses = ['100', '1000', '50', '500'];
  static const List<String> _efficientNetClasses = [
    '1000_FAKE', '1000_REAL',
    '100_FAKE', '100_REAL',
    '500_FAKE', '500_REAL',
    '50_FAKE', '50_REAL'
  ];

  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      print('[ML] Loading YOLOv9s model...');
      _yoloInterpreter = await Interpreter.fromAsset('assets/yolov9s.tflite');
      
      print('[ML] Loading EfficientNetV2 model from assets/EfficientNetV2.tflite ...');
      _efficientNetInterpreter = await Interpreter.fromAsset('assets/EfficientNetV2.tflite');
      
      // CRITICAL: Check model details
      _printModelDetails();
      
      _isInitialized = true;
      print('✓ Models loaded successfully (YOLOv9s + EfficientNetV2)');
    } catch (e) {
      print('Error loading models: $e');
      _isInitialized = false;
    }
  }

  static void _printModelDetails() {
    if (_efficientNetInterpreter != null) {
      final inputDetails = _efficientNetInterpreter!.getInputTensor(0);
      final outputDetails = _efficientNetInterpreter!.getOutputTensor(0);
      
      print('[EFF] Model Details:');
      print('  Input shape: ${inputDetails.shape}');
      print('  Input type: ${inputDetails.type}');
      print('  Output shape: ${outputDetails.shape}');
      print('  Output type: ${outputDetails.type}');
      
      // Check for quantization - TfLiteType enum values
      // TfLiteType.float32, TfLiteType.int32, TfLiteType.uint8, TfLiteType.int64, TfLiteType.string, TfLiteType.bool, TfLiteType.int16, TfLiteType.complex64, TfLiteType.int8, TfLiteType.float16
      final inputTypeName = inputDetails.type.toString();
      final outputTypeName = outputDetails.type.toString();
      
      print('  Input type name: $inputTypeName');
      print('  Output type name: $outputTypeName');
      
      // Check if quantized (not float32)
      if (!inputTypeName.contains('float32')) {
        print('  ⚠️ WARNING: Input is QUANTIZED ($inputTypeName)');
        print('  ⚠️ This may require different preprocessing!');
      } else {
        print('  ✓ Input is FLOAT32 (correct for preprocessing)');
      }
      
      if (!outputTypeName.contains('float32')) {
        print('  ⚠️ WARNING: Output is QUANTIZED ($outputTypeName)');
        print('  ⚠️ Dequantization may be needed!');
      } else {
        print('  ✓ Output is FLOAT32 (correct)');
      }
    }
  }

  static Future<Map<String, dynamic>> predict(File imageFile) async {
    if (!_isInitialized || _yoloInterpreter == null || _efficientNetInterpreter == null) {
      await initialize();
      if (!_isInitialized) {
        throw Exception('Failed to initialize ML models');
      }
    }

    try {
      print('\n[ML] ===== PROCESS IMAGE =====');
      print('[ML] File: ${imageFile.path}');
      
      // Load original image for width/height
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final original = frame.image;
      print('[ML] Original size: ${original.width}x${original.height}');

      // 1) YOLO detection (denomination)
      final yoloInShape = _yoloInterpreter!.getInputTensor(0).shape;
      final yoloOutShape = _yoloInterpreter!.getOutputTensor(0).shape;
      print('[YOLO] Input tensor shape: $yoloInShape');
      print('[YOLO] Output tensor shape: $yoloOutShape');

      final yoloInput = await _preprocessRgbFloat32(imageFile, _inputSize, _inputSize);
      print('[YOLO] Preprocessed to ${_inputSize}x${_inputSize}, dtype=float32 [0,1]');
      
      final yoloOutput = _prepareYoloOutputBuffer();
      _yoloInterpreter!.run(yoloInput, yoloOutput);

      final detections = _parseYoloOutput(
        yoloOutput,
        original.width.toDouble(),
        original.height.toDouble(),
        minConf: 0.90,
        minAreaRatio: 0.02,
      );
      
      print('[YOLO] Detections (post-NMS): ${detections.length}');
      if (detections.isNotEmpty) {
        for (final d in detections) {
          print("[YOLO] -> class=${d['class']} conf=${(d['confidence'] as double).toStringAsFixed(3)} bbox=${d['bbox']}");
        }
      }

      if (detections.isEmpty) {
        print('[YOLO] ❌ No banknotes detected');
        return {
          'status': BillStatus.invalid,
          'confidence': 0,
          'denomination': '',
          'noDetection': true,
          'message': 'There is no Money Detected. Please try again.'
        };
      }

      // 2) EfficientNet classification - WITH DETAILED DEBUGGING
      final effInShape = _efficientNetInterpreter!.getInputTensor(0).shape;
      final effOutShape = _efficientNetInterpreter!.getOutputTensor(0).shape;
      final effInputType = _efficientNetInterpreter!.getInputTensor(0).type;
      final effOutputType = _efficientNetInterpreter!.getOutputTensor(0).type;
      
      print('[EFF] Input tensor shape: $effInShape');
      print('[EFF] Output tensor shape: $effOutShape');
      print('[EFF] Input type: $effInputType');
      print('[EFF] Output type: $effOutputType');

      print('[EFF] Preprocessing full image for EfficientNet...');
      
      // CRITICAL: Check if Python model was converted with different settings
      final effInput = await _preprocessImageForEfficientNet(imageFile, _inputSize, _inputSize);
      
      print('[EFF] Preprocessed full image to ${_inputSize}x${_inputSize}');
      
      final effOutput = List.filled(1 * _efficientNetClasses.length, 0.0)
          .reshape([1, _efficientNetClasses.length]);
      
      print('[EFF] Invoking EfficientNetV2.tflite...');
      final _effSw = Stopwatch()..start();
      _efficientNetInterpreter!.run(effInput, effOutput);
      _effSw.stop();
      print('[EFF] Inference completed in ${_effSw.elapsedMilliseconds} ms');

      // Extract raw vector
      final rawVec = _extractVector(effOutput);
      final sumRaw = _sum(rawVec);
      print('[EFF] Raw output vector length=${rawVec.length} sum=${sumRaw.toStringAsFixed(6)}');
      
      // CRITICAL CHECK: If sum is ~1.0 but all values are uniform, model may not be working
      final variance = _calculateVariance(rawVec);
      print('[EFF] Output variance: ${variance.toStringAsFixed(6)} (LOW variance = problem!)');
      
      for (int i = 0; i < rawVec.length; i++) {
        final label = (i < _efficientNetClasses.length) ? _efficientNetClasses[i] : 'idx_$i';
        print('[EFF]   raw[$i] $label = ${rawVec[i].toStringAsFixed(6)}');
      }

      // Apply softmax EXACTLY like Python
      List<double> effProbs;
      final sumDiff = (sumRaw - 1.0).abs();
      if (sumDiff > 0.1) {
        effProbs = _softmax(rawVec);
        print('[EFF] Applied softmax (sum diff = ${sumDiff.toStringAsFixed(3)})');
      } else {
        effProbs = List<double>.from(rawVec);
        print('[EFF] Using raw outputs as probabilities (sum diff = ${sumDiff.toStringAsFixed(3)})');
      }
      
      for (int i = 0; i < effProbs.length; i++) {
        final label = (i < _efficientNetClasses.length) ? _efficientNetClasses[i] : 'idx_$i';
        print('[EFF]   prob[$i] $label = ${effProbs[i].toStringAsFixed(6)}');
      }

      // CRITICAL WARNING: Check if model is producing uniform distribution
      if (variance < 0.001) {
        print('[EFF] ⚠️⚠️⚠️ CRITICAL WARNING ⚠️⚠️⚠️');
        print('[EFF] Model output is nearly UNIFORM distribution!');
        print('[EFF] This suggests the model is NOT processing the image correctly.');
        print('[EFF] Possible issues:');
        print('[EFF]   1. Wrong preprocessing (check Python preprocess_input)');
        print('[EFF]   2. Model quantization mismatch');
        print('[EFF]   3. Model file corrupted or wrong version');
        print('[EFF]   4. Input/output types mismatch');
      }

      // Top 2 for debugging
      final indexed = List<int>.generate(effProbs.length, (i) => i);
      indexed.sort((a, b) => effProbs[b].compareTo(effProbs[a]));
      final topIdx = indexed.isNotEmpty ? indexed[0] : -1;
      final secondIdx = indexed.length > 1 ? indexed[1] : -1;
      if (topIdx >= 0) {
        print('[EFF] Top1 -> idx=$topIdx label=${_efficientNetClasses[topIdx]} prob=${effProbs[topIdx].toStringAsFixed(6)}');
      }
      if (secondIdx >= 0) {
        print('[EFF] Top2 -> idx=$secondIdx label=${_efficientNetClasses[secondIdx]} prob=${effProbs[secondIdx].toStringAsFixed(6)}');
      }

      // Get top detection denomination
      detections.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
      final top = detections.first;
      final denomination = top['class'] as String;
      
      // Get EfficientNet's top prediction
      final effTopClass = _efficientNetClasses[topIdx];
      final effTopDenom = effTopClass.replaceAll('_FAKE', '').replaceAll('_REAL', '');
      
      print('[DECISION] YOLO says: $denomination, EfficientNet top class says: $effTopDenom');
      
      String finalDenomination = denomination;
      
      // Find corresponding FAKE/REAL probabilities for YOLO's denomination
      final fakeLabel = '${denomination}_FAKE';
      final realLabel = '${denomination}_REAL';

      final idxFake = _efficientNetClasses.indexOf(fakeLabel);
      final idxReal = _efficientNetClasses.indexOf(realLabel);
      
      double pFake = (idxFake >= 0 && idxFake < effProbs.length) ? effProbs[idxFake] : 0.0;
      double pReal = (idxReal >= 0 && idxReal < effProbs.length) ? effProbs[idxReal] : 0.0;
      
      print('[EFF] Pair($denomination): pFake=${pFake.toStringAsFixed(3)} pReal=${pReal.toStringAsFixed(3)}');
      
      // Check if EfficientNet strongly disagrees with YOLO
      final yoloPairSum = pFake + pReal;
      final effTopProb = effProbs[topIdx];
      
      print('[ANALYSIS] YOLO denomination pair sum: ${yoloPairSum.toStringAsFixed(3)}');
      print('[ANALYSIS] EfficientNet top prediction prob: ${effTopProb.toStringAsFixed(3)}');
      
      // If YOLO's denomination has very low probability, consider using EfficientNet's top pick
      if (yoloPairSum < 0.15 && effTopProb > 0.20 && effTopDenom != denomination) {
        print('[DECISION] ⚠️ EfficientNet strongly disagrees. Using EfficientNet\'s top prediction: $effTopDenom');
        finalDenomination = effTopDenom;
        
        final newFakeLabel = '${effTopDenom}_FAKE';
        final newRealLabel = '${effTopDenom}_REAL';
        final newIdxFake = _efficientNetClasses.indexOf(newFakeLabel);
        final newIdxReal = _efficientNetClasses.indexOf(newRealLabel);
        
        pFake = (newIdxFake >= 0 && newIdxFake < effProbs.length) ? effProbs[newIdxFake] : 0.0;
        pReal = (newIdxReal >= 0 && newIdxReal < effProbs.length) ? effProbs[newIdxReal] : 0.0;
        
        print('[EFF] Using new pair($effTopDenom): pFake=${pFake.toStringAsFixed(3)} pReal=${pReal.toStringAsFixed(3)}');
      } else {
        print('[DECISION] ✓ Using YOLO\'s denomination: $denomination');
      }

      final isRealHigher = pReal >= pFake;
      final chosenLabel = isRealHigher ? '${finalDenomination}_REAL' : '${finalDenomination}_FAKE';
      final status = isRealHigher ? BillStatus.real : BillStatus.counterfeit;
      final effConfPct = ((isRealHigher ? pReal : pFake) * 100).round().clamp(0, 100);
      
      print('[EFF] Chosen=$chosenLabel -> status=$status (${effConfPct}%)');
      print('[PIPELINE] Final -> denomination=₱$finalDenomination status=$status confidence=${effConfPct}%');

      return {
        'status': status,
        'confidence': effConfPct,
        'denomination': finalDenomination,
        'noDetection': false,
        'yoloDetections': detections,
      };
    } catch (e) {
      print('Error during prediction: $e');
      return {
        'status': BillStatus.invalid,
        'confidence': 0,
        'denomination': '',
        'noDetection': true,
        'error': e.toString(),
      };
    }
  }

  static Future<List<List<List<List<double>>>>> _preprocessRgbFloat32(
    File imageFile,
    int width,
    int height,
  ) async {
    print('[PRE] YOLO: Resize -> ${width}x${height}');
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width, targetHeight: height);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = byteData!.buffer.asUint8List();
    
    final tensor = List.generate(1, (batch) => 
      List.generate(height, (y) =>
        List.generate(width, (x) =>
          List.generate(3, (c) {
            final idx = (y * width + x) * 4;
            switch (c) {
              case 0: return pixels[idx] / 255.0;
              case 1: return pixels[idx + 1] / 255.0;
              case 2: return pixels[idx + 2] / 255.0;
              default: return 0.0;
            }
          })
        )
      )
    );

    return tensor;
  }

  static Future<List<List<List<List<double>>>>> _preprocessImageForEfficientNet(
    File imageFile,
    int targetW,
    int targetH,
  ) async {
    print('[PRE] EFF: Loading and resizing image -> ${targetW}x${targetH}');
    
    // CRITICAL FIX: Load original image first, THEN resize manually
    final bytes = await imageFile.readAsBytes();
    
    // Load original image WITHOUT resizing
    final originalCodec = await ui.instantiateImageCodec(bytes);
    final originalFrame = await originalCodec.getNextFrame();
    final originalImage = originalFrame.image;
    
    print('[PRE] EFF: Original image size: ${originalImage.width}x${originalImage.height}');
    
    // Now resize to target size
    final resizedCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetW,
      targetHeight: targetH
    );
    final resizedFrame = await resizedCodec.getNextFrame();
    final resized = resizedFrame.image;

    final byteData = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = byteData!.buffer.asUint8List();
    
    print('[PRE] EFF: Resized to: ${resized.width}x${resized.height}');

    print('[PRE] EFF: Applying EfficientNetV2 preprocess_input ([-1, 1] normalization)');
    
    List<List<List<List<double>>>> tensor;
    
    switch (PREPROCESSING_METHOD) {
      case 1:
        // Method 1: Standard EfficientNetV2 preprocessing ([-1, 1])
        print('[PRE] EFF: Method 1 - EfficientNetV2 standard ([-1, 1])');
        tensor = List.generate(1, (batch) =>
          List.generate(targetH, (y) =>
            List.generate(targetW, (x) {
              final baseIdx = (y * targetW + x) * 4;
              final r = pixels[baseIdx].toDouble();
              final g = pixels[baseIdx + 1].toDouble();
              final b = pixels[baseIdx + 2].toDouble();
              
              // CRITICAL: Apply preprocessing EXACTLY as Python
              // Python: (value / 127.5) - 1.0
              return [
                (r / 127.5) - 1.0,
                (g / 127.5) - 1.0,
                (b / 127.5) - 1.0,
              ];
            })
          )
        );
        break;
        
      case 2:
        // Method 2: Simple normalization [0, 1]
        print('[PRE] EFF: Method 2 - Simple [0, 1] normalization');
        tensor = List.generate(1, (batch) =>
          List.generate(targetH, (y) =>
            List.generate(targetW, (x) {
              final baseIdx = (y * targetW + x) * 4;
              return [
                pixels[baseIdx] / 255.0,
                pixels[baseIdx + 1] / 255.0,
                pixels[baseIdx + 2] / 255.0,
              ];
            })
          )
        );
        break;
        
      case 3:
        // Method 3: ImageNet standardization (mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        print('[PRE] EFF: Method 3 - ImageNet standardization');
        const mean = [0.485, 0.456, 0.406];
        const std = [0.229, 0.224, 0.225];
        tensor = List.generate(1, (batch) =>
          List.generate(targetH, (y) =>
            List.generate(targetW, (x) {
              final baseIdx = (y * targetW + x) * 4;
              return [
                ((pixels[baseIdx] / 255.0) - mean[0]) / std[0],
                ((pixels[baseIdx + 1] / 255.0) - mean[1]) / std[1],
                ((pixels[baseIdx + 2] / 255.0) - mean[2]) / std[2],
              ];
            })
          )
        );
        break;
        
      case 4:
        // Method 4: Raw pixel values [0, 255] - THIS IS CORRECT FOR YOUR MODEL!
        // Your Python model uses preprocess_input which does NOT normalize
        print('[PRE] EFF: Method 4 - Raw pixels [0, 255] (NO normalization)');
        tensor = List.generate(1, (batch) =>
          List.generate(targetH, (y) =>
            List.generate(targetW, (x) {
              final baseIdx = (y * targetW + x) * 4;
              // Keep raw pixel values, no transformation
              return [
                pixels[baseIdx].toDouble(),       // R: [0, 255]
                pixels[baseIdx + 1].toDouble(),   // G: [0, 255]
                pixels[baseIdx + 2].toDouble(),   // B: [0, 255]
              ];
            })
          )
        );
        break;
        
      default:
        throw Exception('Invalid preprocessing method');
    }

    // Verify preprocessing
    if (targetH > 320 && targetW > 320) {
      final samplePixel = tensor[0][320][320];
      print('[PRE] EFF: Sample center pixel after preprocessing:');
      print('  R=${samplePixel[0].toStringAsFixed(4)}');
      print('  G=${samplePixel[1].toStringAsFixed(4)}');
      print('  B=${samplePixel[2].toStringAsFixed(4)}');
      
      final allValues = <double>[];
      for (var row in tensor[0]) {
        for (var pixel in row) {
          allValues.addAll(pixel);
        }
      }
      final minVal = allValues.reduce((a, b) => a < b ? a : b);
      final maxVal = allValues.reduce((a, b) => a > b ? a : b);
      final meanVal = allValues.reduce((a, b) => a + b) / allValues.length;
      print('[PRE] EFF: Stats - min=${minVal.toStringAsFixed(4)}, max=${maxVal.toStringAsFixed(4)}, mean=${meanVal.toStringAsFixed(4)}');
    }

    return tensor;
  }

  static List<dynamic> _prepareYoloOutputBuffer() {
    try {
      final t = _yoloInterpreter!.getOutputTensor(0);
      final shape = t.shape;
      final total = shape.reduce((a, b) => a * b);
      return List.filled(total, 0.0).reshape(shape);
    } catch (_) {
      return List.filled(1 * 8400 * (5 + _yoloClasses.length), 0.0)
          .reshape([1, 8400, 5 + _yoloClasses.length]);
    }
  }

  static List<Map<String, dynamic>> _parseYoloOutput(
    dynamic outputs,
    double origW,
    double origH, {
    double minConf = 0.90,
    double minAreaRatio = 0.02,
  }) {
    List<List<double>> rows = [];
    try {
      final o = outputs;
      if (o is List && o.isNotEmpty && o[0] is List) {
        dynamic arr = o;
        if (arr.length == 1 && arr[0] is List) arr = arr[0];
        final tmp = <List<double>>[];
        for (final r in arr) {
          tmp.add(List<double>.from((r as List).map<double>((v) => (v as num).toDouble())));
        }
        rows = tmp;
      }
    } catch (e) {
      print('[YOLO] Error extracting rows: $e');
      return [];
    }

    if (rows.isEmpty) {
      print('[YOLO] No rows extracted from output');
      return [];
    }

    if (rows.length > 0 && rows[0].length > 0 && rows.length < rows[0].length) {
      print('[YOLO] Transposing output: ${rows.length}x${rows[0].length} -> ${rows[0].length}x${rows.length}');
      final transposed = <List<double>>[];
      for (int j = 0; j < rows[0].length; j++) {
        final r = <double>[];
        for (int i = 0; i < rows.length; i++) {
          r.add(rows[i][j]);
        }
        transposed.add(r);
      }
      rows = transposed;
    }

    final numClasses = _yoloClasses.length;
    final hasObj = rows[0].length == 5 + numClasses;
    final classStart = hasObj ? 5 : 4;
    final totalArea = origW * origH;
    final detections = <Map<String, dynamic>>[];

    print('[YOLO] Parsing ${rows.length} detections (hasObjectness=$hasObj, numClasses=$numClasses)');

    double sigmoid(double x) {
      final clamped = x.clamp(-10.0, 10.0);
      return 1.0 / (1.0 + math.exp(-clamped));
    }

    for (final det in rows) {
      if (det.length < classStart + numClasses) continue;

      final xCenter = det[0];
      final yCenter = det[1];
      final w = det[2];
      final h = det[3];
      
      if (w <= 0 || h <= 0) continue;
      if (w > 1.5 || h > 1.5) continue;
      if (xCenter < -0.5 || xCenter > 1.5 || yCenter < -0.5 || yCenter > 1.5) continue;

      double conf;
      List<double> classScores = det.sublist(classStart, classStart + numClasses);
      
      if (hasObj) {
        final objRaw = det[4];
        final obj = (objRaw < 0 || objRaw > 1) ? sigmoid(objRaw) : objRaw;
        if (obj < minConf) continue;
        
        if (_maxAbs(classScores) > 1.0) {
          classScores = _softmax(classScores);
        }
        
        final cid = _argMax(classScores);
        conf = obj * classScores[cid];
        if (conf < minConf) continue;
      } else {
        if (_maxAbs(classScores) > 1.0) {
          classScores = _softmax(classScores);
        }
        
        final cid = _argMax(classScores);
        conf = classScores[cid];
        if (conf < minConf) continue;
      }

      final x1Raw = (xCenter - w / 2) * origW;
      final y1Raw = (yCenter - h / 2) * origH;
      final x2Raw = (xCenter + w / 2) * origW;
      final y2Raw = (yCenter + h / 2) * origH;

      final cx = xCenter * origW;
      final cy = yCenter * origH;
      if (cx < 0 || cx > origW || cy < 0 || cy > origH) continue;

      final x1 = x1Raw.clamp(0.0, origW);
      final y1 = y1Raw.clamp(0.0, origH);
      final x2 = x2Raw.clamp(0.0, origW);
      final y2 = y2Raw.clamp(0.0, origH);

      final bw = x2 - x1;
      final bh = y2 - y1;
      if (bw <= 5 || bh <= 5) continue;

      final area = bw * bh;
      final areaRatio = area / totalArea;
      if (areaRatio < minAreaRatio) continue;

      final aspect = bw / bh;
      if (aspect < 0.3 || aspect > 4.0) continue;

      final origArea = (x2Raw - x1Raw) * (y2Raw - y1Raw);
      if (origArea > 0 && area < 0.7 * origArea) continue;

      final scores = hasObj ? _softmax(classScores) : classScores;
      final classId = _argMax(scores);
      if (classId >= numClasses) continue;

      final sortedScores = List<double>.from(scores)..sort((a, b) => b.compareTo(a));
      final diff = sortedScores[0] - (sortedScores.length > 1 ? sortedScores[1] : 0.0);
      if (diff < 0.15) continue;
      if (conf < 0.75 && diff < 0.25) continue;

      detections.add({
        'class': _yoloClasses[classId],
        'confidence': conf,
        'bbox': [x1, y1, x2, y2],
        'area_ratio': areaRatio,
        'aspect_ratio': aspect,
      });
    }

    print('[YOLO] Pre-NMS detections: ${detections.length}');

    detections.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));
    final kept = <Map<String, dynamic>>[];
    
    while (detections.isNotEmpty) {
      final current = detections.removeAt(0);
      kept.add(current);
      detections.removeWhere((d) => _iou(current['bbox'], d['bbox']) > 0.45);
    }
    
    print('[YOLO] After NMS kept: ${kept.length}');
    return kept.length > 3 ? kept.sublist(0, 3) : kept;
  }

  static double _iou(List bboxA, List bboxB) {
    final ax1 = (bboxA[0] as double);
    final ay1 = (bboxA[1] as double);
    final ax2 = (bboxA[2] as double);
    final ay2 = (bboxA[3] as double);
    final bx1 = (bboxB[0] as double);
    final by1 = (bboxB[1] as double);
    final bx2 = (bboxB[2] as double);
    final by2 = (bboxB[3] as double);

    final x1 = math.max(ax1, bx1);
    final y1 = math.max(ay1, by1);
    final x2 = math.min(ax2, bx2);
    final y2 = math.min(ay2, by2);
    
    final interW = math.max(0.0, x2 - x1);
    final interH = math.max(0.0, y2 - y1);
    final inter = interW * interH;
    
    final areaA = (ax2 - ax1) * (ay2 - ay1);
    final areaB = (bx2 - bx1) * (by2 - by1);
    final union = areaA + areaB - inter;
    
    if (union <= 0) return 0.0;
    return inter / union;
  }

  static List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / (sum == 0 ? 1 : sum)).toList();
  }

  static int _argMax(List<double> arr) {
    var maxIdx = 0;
    var maxVal = -1e9;
    for (int i = 0; i < arr.length; i++) {
      if (arr[i] > maxVal) {
        maxVal = arr[i];
        maxIdx = i;
      }
    }
    return maxIdx;
  }

  static double _maxAbs(List<double> arr) {
    double m = 0.0;
    for (final v in arr) {
      final a = v.abs();
      if (a > m) m = a;
    }
    return m;
  }

  static double _sum(List<double> arr) {
    double s = 0.0;
    for (final v in arr) {
      s += v;
    }
    return s;
  }

  static double _calculateVariance(List<double> arr) {
    if (arr.isEmpty) return 0.0;
    final mean = _sum(arr) / arr.length;
    double sumSquaredDiff = 0.0;
    for (final v in arr) {
      final diff = v - mean;
      sumSquaredDiff += diff * diff;
    }
    return sumSquaredDiff / arr.length;
  }

  static List<double> _extractVector(dynamic output) {
    if (output is List && output.isNotEmpty) {
      if (output[0] is List) {
        return List<double>.from((output[0] as List).map<double>((v) => (v as num).toDouble()));
      }
      return List<double>.from(output.map<double>((v) => (v as num).toDouble()));
    }
    return [];
  }

  static void dispose() {
    _yoloInterpreter?.close();
    _efficientNetInterpreter?.close();
    _yoloInterpreter = null;
    _efficientNetInterpreter = null;
    _isInitialized = false;
  }
}