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

  // Estados dos Sliders
  double _posX = 5.0;
  double _posY = 5.0;
  double _posZ = 5.0;
  double _intensity = 2.0;
  Color _selectedColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF222222))
      ..loadFlutterAsset('assets/index.html');
  }

  // Envia todos os estados atuais para o JavaScript
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

      // Aguarda o processamento do modelo para capturar as animações
      await Future.delayed(const Duration(milliseconds: 1000));
      final dynamic resultAnims = await _controller.runJavaScriptReturningResult("window.getAnimationList()");

      setState(() {
        _isModelLoaded = true;
        _isRigVisible = false;
        try {
          // Trata o retorno do JS que pode vir como string escapada
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

          if (!_isModelLoaded)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 64,
                    color: Colors.white.withAlpha(155),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Nenhum modelo .glb carregado\nToque no canto superior direito da tela para carregar",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withAlpha(190),
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),

          // Painel de Controle Sticky
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

  Widget _buildControlPanel() {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(127),
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
          const Text("Cor da Fonte", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
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
}