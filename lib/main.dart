import 'dart:convert';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart' as v64;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ThreeJSView(),
  ));
}

class ThreeJSView extends StatefulWidget {
  const ThreeJSView({super.key});

  @override
  State<ThreeJSView> createState() => _ThreeJSViewState();
}

class _ThreeJSViewState extends State<ThreeJSView> {
  late final WebViewController _controller;
  bool _isModelLoaded = false;
  bool _showControls = false;
  bool _isRigVisible = false;

  List<String> _animations = [];
  bool _isPaused = false;
  double _timeScale = 1.0;
  String _currentAnimName = "";

  int _vertexCount = 0;
  int _faceCount = 0;

  double _posX = 5.0;
  double _posY = 5.0;
  double _posZ = 5.0;
  double _intensity = 2.0;
  Color _selectedColor = Colors.white;

  List<dynamic> _boneList = [];
  final poseDetector = PoseDetector(options: PoseDetectorOptions(model: PoseDetectionModel.accurate));

  Map<String, v64.Vector3> _tPoseVectors = {};
  Map<String, v64.Vector3> _lastVectors = {};
  double _zImpact = 0.5;
  double _smoothing = 0.25;

  v64.Vector3 _smoothVector(String boneName, v64.Vector3 newDir) {
    if (!_lastVectors.containsKey(boneName)) {
      _lastVectors[boneName] = newDir;
      return newDir;
    }
    // Interpolação Linear de Movimentos (Menor = mais suave, Maior = mais abrupto).
    v64.Vector3 smoothed = _lastVectors[boneName]! + (newDir - _lastVectors[boneName]!) * _smoothing;
    _lastVectors[boneName] = smoothed.normalized();
    return _lastVectors[boneName]!;
  }

  Future<void> _fetchTPoseReferences() async {
    final result = await _controller.runJavaScriptReturningResult("window.getTPoseReferences()");
    final Map<String, dynamic> data = jsonDecode(result.toString().startsWith('"')
        ? jsonDecode(result.toString())
        : result.toString());

    _tPoseVectors = data.map((key, value) => MapEntry(
        key, v64.Vector3(value['x'], value['y'], value['z'])
    ));

    print("--- REFERÊNCIAS DE OSSOS DA POSE-T ---");
    print("Total de ossos mapeados: ${_tPoseVectors.length}");
    _tPoseVectors.forEach((boneName, vector) {
      print("Osso: $boneName | Vetor Base: [${vector.x.toStringAsFixed(2)}, ${vector.y.toStringAsFixed(2)}, ${vector.z.toStringAsFixed(2)}]");
    });
    print("--------------------------------------");
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF222222))
      ..addJavaScriptChannel(
        'FileHandler',
        onMessageReceived: (message) => _saveModel(message.message),
      )
      ..loadFlutterAsset('assets/index.html');
  }

  List<double> _getBoneRotation(String boneName, PoseLandmark start, PoseLandmark end, v64.Vector3 baseDir) {
    v64.Vector3 detectedDir = v64.Vector3(
      end.x - start.x,
      end.y - start.y,
      -(end.z - start.z) * _zImpact,
    ).normalized();
    v64.Vector3 smoothedDir = _smoothVector(boneName, detectedDir.normalized());
    v64.Quaternion q = v64.Quaternion.fromTwoVectors(baseDir, smoothedDir);
    return [q.x, q.y, q.z, q.w];
  }

  Future<void> _processVideoForPose() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null) return;

    _showLoadingDialog("Processando movimentos com IA...");

    try {
      final String videoPath = result.files.single.path!;
      final dir = await getTemporaryDirectory();
      final outPath = "${dir.path}/mocap_frames";
      if (Directory(outPath).existsSync()) Directory(outPath).deleteSync(recursive: true);
      await Directory(outPath).create(recursive: true);

      await FFmpegKit.execute('-i "$videoPath" -r 10 -q:v 2 "$outPath/f%03d.jpg"');
      List<FileSystemEntity> frames = Directory(outPath).listSync().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      List<Map<String, dynamic>> timeline = [];
      double currentTime = 0.0;

      for (var frame in frames) {
        final poses = await poseDetector.processImage(InputImage.fromFilePath(frame.path));
        if (poses.isNotEmpty) {
          final p = poses.first;
          Map<String, List<double>> rots = {};
          final hipCenter = PoseLandmark(
            type: PoseLandmarkType.nose,
            x: (p.landmarks[PoseLandmarkType.leftHip]!.x + p.landmarks[PoseLandmarkType.rightHip]!.x) / 2,
            y: (p.landmarks[PoseLandmarkType.leftHip]!.y + p.landmarks[PoseLandmarkType.rightHip]!.y) / 2,
            z: (p.landmarks[PoseLandmarkType.leftHip]!.z + p.landmarks[PoseLandmarkType.rightHip]!.z) / 2,
            likelihood: (p.landmarks[PoseLandmarkType.leftHip]!.likelihood + p.landmarks[PoseLandmarkType.rightHip]!.likelihood) / 2,
          );
          final shoulderCenter = PoseLandmark(
            type: PoseLandmarkType.nose,
            x: (p.landmarks[PoseLandmarkType.leftShoulder]!.x + p.landmarks[PoseLandmarkType.rightShoulder]!.x) / 2,
            y: (p.landmarks[PoseLandmarkType.leftShoulder]!.y + p.landmarks[PoseLandmarkType.rightShoulder]!.y) / 2,
            z: (p.landmarks[PoseLandmarkType.leftShoulder]!.z + p.landmarks[PoseLandmarkType.rightShoulder]!.z) / 2,
            likelihood: (p.landmarks[PoseLandmarkType.leftShoulder]!.likelihood + p.landmarks[PoseLandmarkType.rightShoulder]!.likelihood) / 2,
          );
          final mouthCenter = PoseLandmark(
            type: PoseLandmarkType.nose,
            x: (p.landmarks[PoseLandmarkType.leftMouth]!.x + p.landmarks[PoseLandmarkType.rightMouth]!.x) / 2,
            y: (p.landmarks[PoseLandmarkType.leftMouth]!.y + p.landmarks[PoseLandmarkType.rightMouth]!.y) / 2,
            z: (p.landmarks[PoseLandmarkType.leftMouth]!.z + p.landmarks[PoseLandmarkType.rightMouth]!.z) / 2,
            likelihood: (p.landmarks[PoseLandmarkType.leftMouth]!.likelihood + p.landmarks[PoseLandmarkType.rightMouth]!.likelihood) / 2,
          );
          final eyeCenter = PoseLandmark(
            type: PoseLandmarkType.leftEye,
            x: (p.landmarks[PoseLandmarkType.leftEye]!.x + p.landmarks[PoseLandmarkType.rightEye]!.x) / 2,
            y: (p.landmarks[PoseLandmarkType.leftEye]!.y + p.landmarks[PoseLandmarkType.rightEye]!.y) / 2,
            z: (p.landmarks[PoseLandmarkType.leftEye]!.z + p.landmarks[PoseLandmarkType.rightEye]!.z) / 2,
            likelihood: (p.landmarks[PoseLandmarkType.leftEye]!.likelihood + p.landmarks[PoseLandmarkType.rightEye]!.likelihood) / 2,
          );
          final neckCenter = PoseLandmark(
            type: PoseLandmarkType.nose,
            x: (shoulderCenter.x + mouthCenter.x) / 2,
            y: (shoulderCenter.y + mouthCenter.y) / 2,
            z: (shoulderCenter.z + mouthCenter.z) / 2,
            likelihood: (shoulderCenter.likelihood + mouthCenter.likelihood) / 2,
          );

          v64.Vector3 spineDir = v64.Vector3(
            shoulderCenter.x - hipCenter.x,
            hipCenter.y - shoulderCenter.y,
            -(shoulderCenter.z - hipCenter.z) * _zImpact,
          ).normalized();

          void trackSpinePart(String boneName, double gX, double gY, double gZ) {
            if (_tPoseVectors.containsKey(boneName)) {
              v64.Vector3 smoothed = _smoothVector(boneName, spineDir);
              v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors[boneName]!, smoothed);

              v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
              v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
              v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

              v64.Quaternion qFinal = qBase * offX * offZ * offY;
              rots[boneName] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
            }
          }

          trackSpinePart('Spine02', 0.0, 240.0, 140.0); //cintura
          trackSpinePart('Spine01', -30.0, 0.0, 0.0); //torso
          trackSpinePart('Spine', 0.0, 0.0, -37.0); //clavicula

          if (_tPoseVectors.containsKey('neck')) {
            v64.Vector3 neckDir = v64.Vector3(
              neckCenter.x - shoulderCenter.x,
              shoulderCenter.y - neckCenter.y,
              -(neckCenter.z - shoulderCenter.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('neck', neckDir);
            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors['neck']!, smoothedDir);

            double gX = -60.0;
            double gY = 0.0;
            double gZ = 0.0;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;
            rots['neck'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('Head')) {
            v64.Vector3 headDir = v64.Vector3(
              eyeCenter.x - mouthCenter.x,
              mouthCenter.y - eyeCenter.y,
              -(eyeCenter.z - mouthCenter.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('Head', headDir);
            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors['Head']!, smoothedDir);

            double gX = 0.0;
            double gY = 0.0;
            double gZ = 0.0;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;
            rots['Head'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('RightArm')) {
            v64.Vector3 armDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.rightElbow]!.x - p.landmarks[PoseLandmarkType.rightShoulder]!.x,
              p.landmarks[PoseLandmarkType.rightElbow]!.y - p.landmarks[PoseLandmarkType.rightShoulder]!.y,
              -(p.landmarks[PoseLandmarkType.rightElbow]!.z - p.landmarks[PoseLandmarkType.rightShoulder]!.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('RightArm', armDir);

            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(
                _tPoseVectors['RightArm']!,
                smoothedDir
            );

            double gX = 0.0;
            double gZ = 0.0;
            double gY = -30.0;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;

            rots['RightArm'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('RightForeArm')) {
            v64.Vector3 foreArmDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.rightWrist]!.x - p.landmarks[PoseLandmarkType.rightElbow]!.x,
              p.landmarks[PoseLandmarkType.rightWrist]!.y - p.landmarks[PoseLandmarkType.rightElbow]!.y,
              -(p.landmarks[PoseLandmarkType.rightWrist]!.z - p.landmarks[PoseLandmarkType.rightElbow]!.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('RightForeArm', foreArmDir);
            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors['RightForeArm']!, smoothedDir);

            double gX = 0.0;
            double gZ = 0.0;
            double gY = -15.0;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;
            rots['RightForeArm'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('LeftArm')) {
            v64.Vector3 armDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.leftElbow]!.x - p.landmarks[PoseLandmarkType.leftShoulder]!.x,
              p.landmarks[PoseLandmarkType.leftElbow]!.y - p.landmarks[PoseLandmarkType.leftShoulder]!.y,
              -(p.landmarks[PoseLandmarkType.leftElbow]!.z - p.landmarks[PoseLandmarkType.leftShoulder]!.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('LeftArm', armDir);
            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors['LeftArm']!, smoothedDir);

            double gX = 0.0;
            double gZ = 0.0;
            double gY = 30.0;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;
            rots['LeftArm'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('LeftForeArm')) {
            v64.Vector3 foreArmDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.leftWrist]!.x - p.landmarks[PoseLandmarkType.leftElbow]!.x,
              p.landmarks[PoseLandmarkType.leftWrist]!.y - p.landmarks[PoseLandmarkType.leftElbow]!.y,
              -(p.landmarks[PoseLandmarkType.leftWrist]!.z - p.landmarks[PoseLandmarkType.leftElbow]!.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('LeftForeArm', foreArmDir);
            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors['LeftForeArm']!, smoothedDir);

            double gX = 0.0;
            double gZ = 0.0;
            double gY = 15.0;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), gY * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;
            rots['LeftForeArm'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('RightLeg')) {
            v64.Vector3 legDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.rightAnkle]!.x - p.landmarks[PoseLandmarkType.rightKnee]!.x,
              p.landmarks[PoseLandmarkType.rightKnee]!.y - p.landmarks[PoseLandmarkType.rightAnkle]!.y,
              -(p.landmarks[PoseLandmarkType.rightAnkle]!.z - p.landmarks[PoseLandmarkType.rightKnee]!.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('RightLeg', legDir);
            v64.Quaternion q = v64.Quaternion.fromTwoVectors(_tPoseVectors['RightLeg']!, smoothedDir);
            rots['RightLeg'] = [q.x, q.y, q.z, q.w];
          }

          if (_tPoseVectors.containsKey('LeftLeg')) {
            v64.Vector3 legDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.leftAnkle]!.x - p.landmarks[PoseLandmarkType.leftKnee]!.x,
              p.landmarks[PoseLandmarkType.leftKnee]!.y - p.landmarks[PoseLandmarkType.leftAnkle]!.y,
              -(p.landmarks[PoseLandmarkType.leftAnkle]!.z - p.landmarks[PoseLandmarkType.leftKnee]!.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('LeftLeg', legDir);
            v64.Quaternion q = v64.Quaternion.fromTwoVectors(_tPoseVectors['LeftLeg']!, smoothedDir);
            rots['LeftLeg'] = [q.x, q.y, q.z, q.w];
          }

          if (_tPoseVectors.containsKey('RightUpLeg')) {
            final hip = p.landmarks[PoseLandmarkType.rightHip]!;
            final knee = p.landmarks[PoseLandmarkType.rightKnee]!;

            v64.Vector3 detectedDir = v64.Vector3(
              knee.x - hip.x,
              hip.y - knee.y,
              -(knee.z - hip.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('RightUpLeg', detectedDir);

            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(
                _tPoseVectors['RightUpLeg']!,
                smoothedDir
            );

            double grausX = -15.0;
            double grausZ = -60.0;
            double grausY = -30;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), grausX * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), grausZ * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), grausY * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;

            rots['RightUpLeg'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('LeftUpLeg')) {
            final hip = p.landmarks[PoseLandmarkType.leftHip]!;
            final knee = p.landmarks[PoseLandmarkType.leftKnee]!;

            v64.Vector3 detectedDir = v64.Vector3(
              knee.x - hip.x,
              hip.y - knee.y,
              -(knee.z - hip.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('LeftUpLeg', detectedDir);

            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(
                _tPoseVectors['LeftUpLeg']!,
                smoothedDir
            );

            double grausX = 0.0;
            double grausZ = -60.0;
            double grausY = -60.0;

            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), grausX * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), grausZ * 0.0174533);
            v64.Quaternion offY = v64.Quaternion.axisAngle(v64.Vector3(0, 1, 0), grausY * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ * offY;

            rots['LeftUpLeg'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('RightShoulder')) {
            v64.Vector3 shoulderDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.rightShoulder]!.x - shoulderCenter.x,
              shoulderCenter.y - p.landmarks[PoseLandmarkType.rightShoulder]!.y,
              -(p.landmarks[PoseLandmarkType.rightShoulder]!.z - shoulderCenter.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('RightShoulder', shoulderDir);
            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors['RightShoulder']!, smoothedDir);

            double gX = 90.0;
            double gZ = 90.0;
            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);

            v64.Quaternion qFinal = qBase * offX * offZ;
            rots['RightShoulder'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          if (_tPoseVectors.containsKey('LeftShoulder')) {
            v64.Vector3 shoulderDir = v64.Vector3(
              p.landmarks[PoseLandmarkType.leftShoulder]!.x - shoulderCenter.x,
              shoulderCenter.y - p.landmarks[PoseLandmarkType.leftShoulder]!.y,
              -(p.landmarks[PoseLandmarkType.leftShoulder]!.z - shoulderCenter.z) * _zImpact,
            ).normalized();

            v64.Vector3 smoothedDir = _smoothVector('LeftShoulder', shoulderDir);
            v64.Quaternion qBase = v64.Quaternion.fromTwoVectors(_tPoseVectors['LeftShoulder']!, smoothedDir);

            double gX = 90.0;
            double gZ = -90.0;
            v64.Quaternion offX = v64.Quaternion.axisAngle(v64.Vector3(1, 0, 0), gX * 0.0174533);
            v64.Quaternion offZ = v64.Quaternion.axisAngle(v64.Vector3(0, 0, 1), gZ * 0.0174533);
            v64.Quaternion qFinal = qBase * offX * offZ;
            rots['LeftShoulder'] = [qFinal.x, qFinal.y, qFinal.z, qFinal.w];
          }

          timeline.add({"time": currentTime, "rotations": rots});
        }
        currentTime += 0.1;
      }

      final animResult = await _controller.runJavaScriptReturningResult(
          "window.addNewAnimationFromPose('Mocap_${DateTime.now().millisecond}', '${jsonEncode(timeline)}')"
      );

      _handleAnimationListResult(animResult);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nova animação adicionada com sucesso!")));
    } catch (e) {
      Navigator.pop(context);
      print("Erro: $e");
    }
  }

  void _handleAnimationListResult(dynamic result) {
    try {
      String rawJson = result.toString();
      if (rawJson.startsWith('"') && rawJson.endsWith('"')) {
        rawJson = jsonDecode(rawJson);
      }
      setState(() {
        _animations = List<String>.from(jsonDecode(rawJson));
      });
    } catch (e) {
      print("Erro ao atualizar lista: $e");
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(height: 20),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Future<void> _saveModel(String base64Content) async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar Modelo GLB',
      fileName: 'modelo_editado.glb',
      bytes: base64Decode(base64Content),
    );

    if (outputFile != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Modelo exportado com sucesso!")),
      );
    }
  }

  void _updateJS() {
    _controller.runJavaScript("window.updateLightPosition($_posX, $_posY, $_posZ)");
    _controller.runJavaScript("window.updateLightIntensity($_intensity)");
    String hex = '#${_selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    _controller.runJavaScript("window.updateLightColor('$hex')");
  }

  Future<void> _pickAndLoadModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _animations = [];
        _isModelLoaded = false;
      });

      final bytes = await File(result.files.single.path!).readAsBytes();
      await _controller.runJavaScript("window.loadModel('${base64Encode(bytes)}')");

      await Future.delayed(const Duration(milliseconds: 1200));

      final dynamic resultAnims = await _controller.runJavaScriptReturningResult("window.getAnimationList()");
      final dynamic resultStats = await _controller.runJavaScriptReturningResult("window.getModelStats()");

      await _fetchTPoseReferences();

      setState(() {
        _isModelLoaded = true;
        _isRigVisible = false;
        _currentAnimName = "";

        try {
          var stats = jsonDecode(resultStats.toString());
          if (stats is String) stats = jsonDecode(stats);
          _vertexCount = stats['vertices'] ?? 0;
          _faceCount = stats['faces'] ?? 0;
        } catch (e) {
          _vertexCount = 0;
          _faceCount = 0;
        }

        _handleAnimationListResult(resultAnims);
      });
    }
  }

  Future<void> _showBoneInfo() async {
    final dynamic resultBones = await _controller.runJavaScriptReturningResult("window.getBoneList()");
    setState(() {
      try {
        String rawJson = resultBones.toString();
        if (rawJson.startsWith('"') && rawJson.endsWith('"')) rawJson = jsonDecode(rawJson);
        _boneList = jsonDecode(rawJson);
      } catch (e) {
        _boneList = [];
      }
    });

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("Estrutura Hierárquica", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: _boneList.isEmpty
              ? const Text("Nenhum osso encontrado.", style: TextStyle(color: Colors.white70))
              : ListView.builder(
            shrinkWrap: true,
            itemCount: _boneList.length,
            itemBuilder: (context, i) {
              final bone = _boneList[i];
              final String? parentName = bone['parent'];
              final bool isChild = parentName != null;
              return Padding(
                padding: EdgeInsets.only(left: isChild ? 24.0 : 0.0),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(isChild ? Icons.subdirectory_arrow_right : Icons.hub,
                      color: isChild ? Colors.orangeAccent : Colors.cyanAccent, size: 18),
                  title: Text(bone['name'], style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text(isChild ? "Pai: $parentName" : "Raiz", style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar"))],
      ),
    );
  }

  void _showAnimationMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withAlpha(220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Animações", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24),
                  if (_animations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text("Nenhuma animação disponível", style: TextStyle(color: Colors.white54)),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _animations.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: const Icon(Icons.movie, color: Colors.purpleAccent),
                        title: Text(_animations[i], style: const TextStyle(color: Colors.white)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () async {
                            final result = await _controller.runJavaScriptReturningResult("window.removeAnimation('${_animations[i]}')");
                            _handleAnimationListResult(result);
                            setModalState(() {});
                          },
                        ),
                        onTap: () {
                          setState(() {
                            _currentAnimName = _animations[i];
                            _isPaused = false;
                            _timeScale = 1.0;
                          });
                          _controller.runJavaScript("window.playAnimation('${_animations[i]}')");
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  _buildMocapSlider(
                    label: "Fator de Profundidade da Câmera: ${_zImpact.toStringAsFixed(2)}",
                    value: _zImpact,
                    min: 0.0,
                    max: 2.0,
                    color: Colors.cyanAccent,
                    onChanged: (v) {
                      setModalState(() => _zImpact = v);
                      setState(() => _zImpact = v);
                    },
                  ),
                  _buildMocapSlider(
                    label: "Suavização de Movimento dos Membros: ${_smoothing.toStringAsFixed(2)}",
                    value: _smoothing,
                    min: 0.01,
                    max: 1.0,
                    color: Colors.greenAccent,
                    onChanged: (v) {
                      setModalState(() => _smoothing = v);
                      setState(() => _smoothing = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _processVideoForPose();
                      },
                      icon: const Icon(Icons.video_camera_back, color: Colors.white),
                      label: const Text("Adicionar via Vídeo (.mp4)", style: TextStyle(color: Colors.white)),
                    ),
                  )
                ],
              ),
            );
          }
      ),
    );
  }

  Widget _buildMocapSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        SizedBox(
          height: 30,
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: color,
            inactiveColor: Colors.white10,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsPanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withAlpha(180), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statsRow(Icons.interests, "Vértices: $_vertexCount"),
          const SizedBox(height: 4),
          _statsRow(Icons.polyline, "Planos: $_faceCount"),
        ],
      ),
    );
  }

  Widget _statsRow(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.cyanAccent, size: 14), const SizedBox(width: 8), Text(text, style: const TextStyle(color: Colors.white, fontSize: 12))]);

  Widget _buildPlaybackControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white), onPressed: () {
            setState(() => _isPaused = !_isPaused);
            _controller.runJavaScript(_isPaused ? "window.pauseAnimation()" : "window.resumeAnimation()");
          }),
          IconButton(icon: const Icon(Icons.replay, color: Colors.white, size: 20), onPressed: () {
            setState(() => _isPaused = false);
            _controller.runJavaScript("window.resetAnimation()");
          }),
          const Icon(Icons.speed, color: Colors.white54, size: 16),
          SizedBox(width: 80, child: Slider(value: _timeScale, min: 0.1, max: 3.0, activeColor: Colors.purpleAccent, onChanged: (v) {
            setState(() => _timeScale = v);
            _controller.runJavaScript("window.setAnimationSpeed($_timeScale)");
          })),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      width: 260, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withAlpha(180), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _label("Luz Pos X", _posX), _slider((v) => _posX = v, -15, 15, _posX),
          _label("Luz Pos Y", _posY), _slider((v) => _posY = v, 0, 20, _posY),
          _label("Luz Pos Z", _posZ), _slider((v) => _posZ = v, -15, 15, _posZ),
          _label("Intensidade", _intensity), _slider((v) => _intensity = v, 0, 10, _intensity),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _colorBtn(Colors.white), _colorBtn(Colors.amber), _colorBtn(Colors.lightBlue), _colorBtn(Colors.redAccent),
          ]),
        ],
      ),
    );
  }

  Widget _label(String t, double v) => Text("$t: ${v.toStringAsFixed(1)}", style: const TextStyle(color: Colors.white, fontSize: 11));
  Widget _slider(Function(double) f, double min, double max, double c) => SizedBox(height: 35, child: Slider(value: c, min: min, max: max, activeColor: Colors.blueAccent, onChanged: (v) { setState(() => f(v)); _updateJS(); }));
  Widget _colorBtn(Color c) => GestureDetector(onTap: () { setState(() => _selectedColor = c); _updateJS(); }, child: Container(width: 35, height: 35, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _selectedColor == c ? Colors.white : Colors.transparent, width: 2))));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF222222),
      appBar: AppBar(
        title: const Text("Visualizador 3D"),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.upload_file), onPressed: _pickAndLoadModel)],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isModelLoaded) Positioned(top: 0, left: 0, child: _buildStatsPanel()),

          if (_isModelLoaded)
            Positioned(
              top: 12, right: 12,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: "btnInfo", backgroundColor: Colors.black54,
                    onPressed: _showBoneInfo, child: const Icon(Icons.info_outline, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: "btnExport", backgroundColor: Colors.green,
                    onPressed: () => _controller.runJavaScript("window.exportGLB()"),
                    child: const Icon(Icons.save, color: Colors.white),
                  ),
                ],
              ),
            ),

          if (!_isModelLoaded) const Center(child: Text("Nenhum modelo .glb carregado", style: TextStyle(color: Colors.white54))),

          if (_isModelLoaded && _showControls) Positioned(right: 100, bottom: 34, child: _buildControlPanel()),
          if (_isModelLoaded && _currentAnimName.isNotEmpty && !_showControls) Positioned(left: 20, bottom: 34, child: _buildPlaybackControls()),
        ],
      ),
      floatingActionButton: _isModelLoaded
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_animations.isNotEmpty) ...[
            FloatingActionButton(mini: true, heroTag: "btnAnim", backgroundColor: Colors.purple, onPressed: _showAnimationMenu, child: const Icon(Icons.play_arrow, color: Colors.white)),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(mini: true, heroTag: "btnRig", backgroundColor: Colors.orange, onPressed: () {
            setState(() => _isRigVisible = !_isRigVisible);
            _controller.runJavaScript("window.toggleRig($_isRigVisible)");
          }, child: const Icon(Icons.accessibility)),
          const SizedBox(height: 12),
          FloatingActionButton(heroTag: "btnLight", backgroundColor: _showControls ? Colors.redAccent : Colors.blueAccent, onPressed: () => setState(() => _showControls = !_showControls), child: Icon(_showControls ? Icons.close : Icons.lightbulb)),
        ],
      ) : null,
    );
  }
}