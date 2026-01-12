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

  List<double> _getBoneRotation(PoseLandmark start, PoseLandmark end, v64.Vector3 baseDir) {
    v64.Vector3 detectedDir = v64.Vector3(
      end.x - start.x,
      -(end.y - start.y),
      end.z - start.z,
    ).normalized();
    v64.Quaternion q = v64.Quaternion.fromTwoVectors(baseDir, detectedDir);
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

          // Mapeamento usando sua hierarquia de ossos
          rots['RightArm'] = _getBoneRotation(p.landmarks[PoseLandmarkType.rightShoulder]!, p.landmarks[PoseLandmarkType.rightElbow]!, v64.Vector3(1, 0, 0));
          rots['RightForeArm'] = _getBoneRotation(p.landmarks[PoseLandmarkType.rightElbow]!, p.landmarks[PoseLandmarkType.rightWrist]!, v64.Vector3(1, 0, 0));
          rots['LeftArm'] = _getBoneRotation(p.landmarks[PoseLandmarkType.leftShoulder]!, p.landmarks[PoseLandmarkType.leftElbow]!, v64.Vector3(-1, 0, 0));
          rots['LeftForeArm'] = _getBoneRotation(p.landmarks[PoseLandmarkType.leftElbow]!, p.landmarks[PoseLandmarkType.leftWrist]!, v64.Vector3(-1, 0, 0));
          rots['RightUpLeg'] = _getBoneRotation(p.landmarks[PoseLandmarkType.rightHip]!, p.landmarks[PoseLandmarkType.rightKnee]!, v64.Vector3(0, -1, 0));
          rots['LeftUpLeg'] = _getBoneRotation(p.landmarks[PoseLandmarkType.leftHip]!, p.landmarks[PoseLandmarkType.leftKnee]!, v64.Vector3(0, -1, 0));

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
    String hex = '#${_selectedColor.value.toRadixString(16).substring(2)}';
    _controller.runJavaScript("window.updateLightColor('$hex')");
  }

  Future<void> _pickAndLoadModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final bytes = await File(result.files.single.path!).readAsBytes();
      await _controller.runJavaScript("window.loadModel('${base64Encode(bytes)}')");

      await Future.delayed(const Duration(milliseconds: 1200));

      final dynamic resultAnims = await _controller.runJavaScriptReturningResult("window.getAnimationList()");
      final dynamic resultStats = await _controller.runJavaScriptReturningResult("window.getModelStats()");

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