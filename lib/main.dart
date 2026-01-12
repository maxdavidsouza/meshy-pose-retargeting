import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:file_picker/file_picker.dart';

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

  // Estados das Animações
  List<String> _animations = [];
  bool _isPaused = false;
  double _timeScale = 1.0;
  String _currentAnimName = "";

  // Estados das Estatísticas
  int _vertexCount = 0;
  int _faceCount = 0;

  // Estados dos Sliders de Luz
  double _posX = 5.0;
  double _posY = 5.0;
  double _posZ = 5.0;
  double _intensity = 2.0;
  Color _selectedColor = Colors.white;

  // Estado da Lista de Ossos (Rig)
  List<dynamic> _boneList = [];

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF222222))
      ..loadFlutterAsset('assets/index.html');
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

        try {
          String rawJson = resultAnims.toString();
          if (rawJson.startsWith('"') && rawJson.endsWith('"')) {
            rawJson = jsonDecode(rawJson);
          }
          _animations = List<String>.from(jsonDecode(rawJson));
        } catch (e) {
          _animations = [];
        }
      });
    }
  }

  // Hierarquia de Ossos do Rig
  Future<void> _showBoneInfo() async {
    final dynamic resultBones = await _controller.runJavaScriptReturningResult("window.getBoneList()");

    setState(() {
      try {
        String rawJson = resultBones.toString();
        if (rawJson.startsWith('"') && rawJson.endsWith('"')) {
          rawJson = jsonDecode(rawJson);
        }
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
                  leading: Icon(
                    isChild ? Icons.subdirectory_arrow_right : Icons.hub,
                    color: isChild ? Colors.orangeAccent : Colors.cyanAccent,
                    size: 18,
                  ),
                  title: Text(
                    bone['name'],
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    isChild ? "Pai: $parentName (ID: ${bone['uuid']})" : "Raiz (ID: ${bone['uuid']})",
                    style: TextStyle(color: isChild ? Colors.white38 : Colors.cyanAccent.withAlpha(150), fontSize: 10),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fechar"))
        ],
      ),
    );
  }

  void _showAnimationMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withAlpha(220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Animações", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),
            if (_animations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text("Nenhuma animação encontrada", style: TextStyle(color: Colors.white54)),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _animations.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(Icons.movie, color: Colors.purpleAccent),
                  title: Text(_animations[i], style: const TextStyle(color: Colors.white)),
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatsPanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
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

  Widget _statsRow(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 14),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white),
            onPressed: () {
              setState(() => _isPaused = !_isPaused);
              _controller.runJavaScript(_isPaused ? "window.pauseAnimation()" : "window.resumeAnimation()");
            },
          ),
          IconButton(
            icon: const Icon(Icons.replay, color: Colors.white, size: 20),
            onPressed: () {
              setState(() => _isPaused = false);
              _controller.runJavaScript("window.resetAnimation()");
            },
          ),
          const SizedBox(width: 8),
          const Icon(Icons.speed, color: Colors.white54, size: 16),
          SizedBox(
            width: 80,
            child: Slider(
              value: _timeScale,
              min: 0.1,
              max: 3.0,
              onChanged: (v) {
                setState(() => _timeScale = v);
                _controller.runJavaScript("window.setAnimationSpeed($_timeScale)");
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label("Luz Pos X", _posX),
          _slider((v) => _posX = v, -15, 15, _posX),
          _label("Luz Pos Y", _posY),
          _slider((v) => _posY = v, 0, 20, _posY),
          _label("Luz Pos Z", _posZ),
          _slider((v) => _posZ = v, -15, 15, _posZ),
          _label("Intensidade", _intensity),
          _slider((v) => _intensity = v, 0, 10, _intensity),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _colorBtn(Colors.white),
              _colorBtn(Colors.amber),
              _colorBtn(Colors.lightBlue),
              _colorBtn(Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text, double val) => Text("$text: ${val.toStringAsFixed(1)}",
      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold));

  Widget _slider(Function(double) onChange, double min, double max, double current) {
    return SizedBox(
      height: 35,
      child: Slider(
        value: current,
        min: min,
        max: max,
        onChanged: (v) {
          setState(() => onChange(v));
          _updateJS();
        },
      ),
    );
  }

  Widget _colorBtn(Color color) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedColor = color);
        _updateJS();
      },
      child: Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: _selectedColor == color ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF222222),
      appBar: AppBar(
        title: const Text("Visualizador 3D"),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _pickAndLoadModel),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),

          // Painel de Estatísticas
          if (_isModelLoaded)
            Positioned(
              top: 0,
              left: 0,
              child: _buildStatsPanel(),
            ),

          // Botão Informativo (Rig/Hierarquia)
          if (_isModelLoaded)
            Positioned(
              top: 12,
              right: 12,
              child: FloatingActionButton.small(
                heroTag: "btnInfo",
                backgroundColor: Colors.black54,
                onPressed: _showBoneInfo,
                child: const Icon(Icons.info_outline, color: Colors.white),
              ),
            ),

          if (!_isModelLoaded)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 64, color: Colors.white.withAlpha(155)),
                  const SizedBox(height: 16),
                  Text("Nenhum modelo .glb carregado", style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 16)),
                ],
              ),
            ),

          // Painel de Luzes
          if (_isModelLoaded)
            Positioned(
              right: 100,
              bottom: 34,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _showControls ? _buildControlPanel() : const SizedBox(),
              ),
            ),

          // Painel de Reprodução
          if (_isModelLoaded && _currentAnimName.isNotEmpty && !_showControls)
            Positioned(
              left: 20,
              bottom: 34,
              child: _buildPlaybackControls(),
            ),
        ],
      ),
      floatingActionButton: _isModelLoaded
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_animations.isNotEmpty) ...[
            FloatingActionButton(
              mini: true,
              heroTag: "btnAnim",
              backgroundColor: Colors.purple,
              onPressed: _showAnimationMenu,
              child: const Icon(Icons.play_arrow, color: Colors.white),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            mini: true,
            heroTag: "btnRig",
            backgroundColor: Colors.orange,
            onPressed: () {
              setState(() => _isRigVisible = !_isRigVisible);
              _controller.runJavaScript("window.toggleRig($_isRigVisible)");
            },
            child: const Icon(Icons.accessibility),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: "btnLight",
            backgroundColor: _showControls ? Colors.redAccent : Colors.blueAccent,
            onPressed: () => setState(() => _showControls = !_showControls),
            child: Icon(_showControls ? Icons.close : Icons.lightbulb),
          ),
        ],
      )
          : null,
    );
  }
}