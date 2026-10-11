import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:cam_scanner/features/scanner/data/models/three_d_scan_models.dart';
import 'package:cam_scanner/features/scanner/data/three_d_reconstruction_service.dart';
import 'package:cam_scanner/features/scanner/presentation/three_d_maker_studio_screen.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.createTempSync('app_doc_').path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.createTempSync('app_temp_').path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProviderPlatform();

  const channel = MethodChannel('ismart/doc_scanner');

  group('3D Product Reconstruction - Offline Pipeline Tests', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'reconstruct3DModel') {
          final args = call.arguments as Map<dynamic, dynamic>;
          final outPath = args['outPath'] as String;
          final imagePaths = (args['imagePaths'] as List<dynamic>).cast<String>();

          // Write a valid dummy binary STL file to outPath
          final file = File(outPath);
          file.parent.createSync(recursive: true);
          final buffer = ByteData(84 + 50); // 80 header + 4 count + 1 triangle (50 bytes)
          buffer.setUint32(80, 1, Endian.little); // 1 triangle
          file.writeAsBytesSync(buffer.buffer.asUint8List());

          return {
            'stlPath': outPath,
            'vertexCount': 3,
            'triangleCount': 1,
            'dimX': 65.5,
            'dimY': 42.0,
            'dimZ': 88.0,
            'isWatertight': true,
            'durationMs': 1250,
          };
        } else if (call.method == 'generateSilhouettePreview') {
          return {
            'previewPath': '/tmp/preview.jpg',
            'coveragePercent': 45.0,
            'isClean': true,
            'message': 'تم عزل المنتج بنجاح من الشفافية (PNG) بدقة 100%',
          };
        } else if (call.method == 'generate3DCalibrationSpecimen') {
          final args = call.arguments as Map<dynamic, dynamic>;
          final outPath = args['outPath'] as String;
          final file = File(outPath);
          file.parent.createSync(recursive: true);
          final buffer = ByteData(84);
          buffer.setUint32(80, 0, Endian.little);
          file.writeAsBytesSync(buffer.buffer.asUint8List());

          return {
            'stlPath': outPath,
            'vertexCount': 36,
            'triangleCount': 12,
            'dimX': 50.0,
            'dimY': 50.0,
            'dimZ': 50.0,
            'isWatertight': true,
            'durationMs': 320,
          };
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reconstructFromImageFiles distributes camera orbit angles uniformly across 360°', () async {
      final capturedCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        capturedCalls.add(call);
        if (call.method == 'reconstruct3DModel') {
          final args = call.arguments as Map<dynamic, dynamic>;
          final outPath = args['outPath'] as String;
          final file = File(outPath);
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(Uint8List(84));
          return {
            'stlPath': outPath,
            'vertexCount': 300,
            'triangleCount': 100,
            'dimX': 50.0,
            'dimY': 50.0,
            'dimZ': 50.0,
            'isWatertight': true,
            'durationMs': 800,
          };
        }
        return null;
      });

      // Test 4 product photos
      final testPaths4 = [
        '/storage/img1.png',
        '/storage/img2.png',
        '/storage/img3.png',
        '/storage/img4.png',
      ];

      final progressUpdates = <double>[];
      final res4 = await ThreeDReconstructionService.reconstructFromImageFiles(
        filePaths: testPaths4,
        title: 'منتج_سماعات',
        voxelSizeMm: 1.4,
        onProgress: (status, progress) {
          progressUpdates.add(progress);
        },
      );

      expect(res4.title, equals('منتج_سماعات'));
      expect(res4.triangleCount, equals(100));
      expect(res4.isWatertight, isTrue);
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last, equals(1.0));

      expect(capturedCalls.length, equals(1));
      final callArgs = capturedCalls.first.arguments as Map<dynamic, dynamic>;
      final azimuths = (callArgs['azimuthsDeg'] as List<dynamic>).cast<double>();
      final elevations = (callArgs['elevationsDeg'] as List<dynamic>).cast<double>();

      expect(azimuths.length, equals(4));
      expect(azimuths[0], closeTo(0.0, 0.01));
      expect(azimuths[1], closeTo(90.0, 0.01));
      expect(azimuths[2], closeTo(180.0, 0.01));
      expect(azimuths[3], closeTo(270.0, 0.01));

      for (final elev in elevations) {
        expect(elev, closeTo(30.0, 0.01));
      }
    });

    test('reconstructFromImageFiles with 6 product photos calculates 60° increments', () async {
      final capturedCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        capturedCalls.add(call);
        if (call.method == 'reconstruct3DModel') {
          final args = call.arguments as Map<dynamic, dynamic>;
          final outPath = args['outPath'] as String;
          final file = File(outPath);
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(Uint8List(84));
          return {
            'stlPath': outPath,
            'vertexCount': 600,
            'triangleCount': 200,
            'dimX': 45.0,
            'dimY': 45.0,
            'dimZ': 60.0,
            'isWatertight': true,
            'durationMs': 950,
          };
        }
        return null;
      });

      final testPaths6 = List.generate(6, (i) => '/storage/item_$i.png');
      await ThreeDReconstructionService.reconstructFromImageFiles(
        filePaths: testPaths6,
        title: 'منتج_ستة_صور',
      );

      expect(capturedCalls.length, equals(1));
      final callArgs = capturedCalls.first.arguments as Map<dynamic, dynamic>;
      final azimuths = (callArgs['azimuthsDeg'] as List<dynamic>).cast<double>();

      expect(azimuths.length, equals(6));
      expect(azimuths[0], closeTo(0.0, 0.01));
      expect(azimuths[1], closeTo(60.0, 0.01));
      expect(azimuths[2], closeTo(120.0, 0.01));
      expect(azimuths[3], closeTo(180.0, 0.01));
      expect(azimuths[4], closeTo(240.0, 0.01));
      expect(azimuths[5], closeTo(300.0, 0.01));
    });

    test('Silhouette quality preview verifies PNG alpha ground truth mask', () async {
      final previewResult =
          await ThreeDReconstructionService.checkSilhouetteQuality('/storage/shoe.png');

      expect(previewResult['isClean'], isTrue);
      expect(previewResult['coveragePercent'], equals(45.0));
      expect(previewResult['message'], contains('تم عزل المنتج بنجاح من الشفافية (PNG)'));
    });

    test('ThreeDScanPhoto and ThreeDReconstructionConfig hold correct properties', () {
      final photo = ThreeDScanPhoto(
        path: '/storage/sample.png',
        elevationDeg: 35.0,
        azimuthDeg: 90.0,
        timestamp: DateTime.now(),
      );

      expect(photo.path, equals('/storage/sample.png'));
      expect(photo.elevationDeg, equals(35.0));
      expect(photo.azimuthDeg, equals(90.0));
      expect(photo.ringLabel, contains('35°'));

      const config = ThreeDReconstructionConfig(
        voxelSizeMm: 1.2,
        consensusRatio: 0.65,
      );

      expect(config.voxelSizeMm, equals(1.2));
      expect(config.consensusRatio, equals(0.65));
    });
  });

  group('3D Maker Studio Screen Widget Tests', () {
    testWidgets('Renders Hero Card with Live Scan and Product Image Convert CTA buttons',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ThreeDMakerStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title and studio elements
      expect(find.text('استوديو الطباعة ثلاثية الأبعاد (3D)'), findsOneWidget);
      expect(find.text('مسح ثلاثي الأبعاد هندسي عالي الدقة'), findsOneWidget);
      expect(find.text('أوفلاين 100% • مقياس متري 1:1'), findsOneWidget);

      // Verify Primary CTA
      expect(find.text('بدء مسح قطعة جديدة (الكاميرا الحية)'), findsOneWidget);

      // Verify New Secondary CTA for product images
      expect(find.text('تحويل صور المنتج (PNG / JPG) إلى مجسم 3D'), findsOneWidget);

      // Verify Quick Actions
      expect(find.text('ورقة المعايرة'), findsOneWidget);
      expect(find.text('مكعب تجريبي'), findsOneWidget);
      expect(find.text('استيراد STL'), findsOneWidget);
    });
  });
}
