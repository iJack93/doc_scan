import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:doc_scan_flutter/doc_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:photo_view/photo_view.dart';

// Prima di eseguire, aggiungi le dipendenze al tuo pubspec.yaml:
// flutter pub add open_file
// flutter

void main() => runApp(const MyApp());

// --------------------------------------------------
// 1. WIDGET PRINCIPALE E PAGINA INIZIALE
// --------------------------------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DocScanPage(),
    );
  }
}

class DocScanPage extends StatefulWidget {
  const DocScanPage({super.key});
  @override
  State<DocScanPage> createState() => _DocScanPageState();
}

class _DocScanPageState extends State<DocScanPage> {
  final DocScanFormat _format = DocScanFormat.jpeg;
  List<String> _finalFilePaths = [];
  String? _errorMessage;
  bool _isLoading = false;

  Future<void> _startScanProcess(String source) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _finalFilePaths = [];
    });

    try {
      final tempImagePath = await DocumentScanner.getImage(source: source);
      if (tempImagePath == null) {
        setState(() => _isLoading = false);
        return;
      }

      final finalPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewPage(
            originalImagePath: tempImagePath,
            format: _format,
          ),
        ),
      );

      if (finalPath != null) {
        setState(() => _finalFilePaths = [finalPath]);
      }
    } on PlatformException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Errore sconosciuto');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doc Scan Flutter')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _startScanProcess("camera"),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text("Camera"),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _startScanProcess("gallery"),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text("Galleria"),
                ),
              ],
            ),
            const Divider(height: 40),
            Expanded(child: _buildResultsWidget()),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsWidget() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Text("Errore: $_errorMessage", style: const TextStyle(color: Colors.red)));
    if (_finalFilePaths.isEmpty) return const Center(child: Text("I documenti scansionati appariranno qui."));

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: _finalFilePaths.length,
      itemBuilder: (context, index) {
        final path = _finalFilePaths[index];
        final isPdf = path.toLowerCase().endsWith('.pdf');
        return Card(
          clipBehavior: Clip.antiAlias,
          child: isPdf
              ? TextButton.icon(onPressed: () => OpenFile.open(path), icon: const Icon(Icons.picture_as_pdf), label: const Text("Apri PDF"))
              : GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ImageDetailPage(imagePath: path))),
            child: Image.file(File(path), fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}

// --------------------------------------------------
// 2. PAGINA DI ANTEPRIMA (PreviewPage)
// --------------------------------------------------

class PreviewPage extends StatefulWidget {
  final String originalImagePath;
  final DocScanFormat format;
  const PreviewPage({super.key, required this.originalImagePath, required this.format});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  Quadrilateral? _quad;
  DocScanFilter _filter = DocScanFilter.blackAndWhite;
  String? _previewImagePath;
  String? _errorMessage;
  bool _isCustomizing = false;
  double _brightness = 0.0;
  double _contrast = 1.0;
  double _threshold = 1.0; // **NUOVO**: Stato per la soglia B&N

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _quad = await DocumentScanner.detectEdges(widget.originalImagePath);
      if (_quad != null) {
        await _regeneratePreview();
      } else {
        setState(() => _errorMessage = "Nessun documento rilevato.");
      }
    } on PlatformException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _regeneratePreview() async {
    if (_quad == null) return;
    setState(() {
      _previewImagePath = null; // Mostra il loader
    });
    try {
      final newPreviewPath = await DocumentScanner.applyCropAndSave(
        imagePath: widget.originalImagePath,
        quad: _quad!,
        format: DocScanFormat.jpeg, // L'anteprima è sempre jpeg
        filter: _isCustomizing ? DocScanFilter.custom : _filter,
        brightness: _isCustomizing ? _brightness : null,
        contrast: _isCustomizing ? _contrast : null,
        threshold: _isCustomizing ? _threshold : null, // **NUOVO**
      );
      setState(() {
        _previewImagePath = newPreviewPath;
      });
    } on PlatformException catch (e) {
      setState(() => _errorMessage = e.message);
    }
  }

  Future<void> _editCrop() async {
    if (_quad == null) return;
    final newQuad = await Navigator.push<Quadrilateral>(
      context,
      MaterialPageRoute(
        builder: (context) => CropPage(
          imagePath: widget.originalImagePath,
          initialQuad: _quad!,
        ),
      ),
    );
    if (newQuad != null) {
      _quad = newQuad;
      await _regeneratePreview();
    }
  }

  Future<void> _editFilter() async {
    if (_quad == null) return;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => FilterPage(
          originalImagePath: widget.originalImagePath,
          quad: _quad!,
          initialFilter: _filter,
          isCustomizing: _isCustomizing,
          initialBrightness: _brightness,
          initialContrast: _contrast,
          initialThreshold: _threshold, // **NUOVO**
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _isCustomizing = result['isCustomizing'] as bool;
        _filter = result['filter'] as DocScanFilter;
        _brightness = result['brightness'] as double;
        _contrast = result['contrast'] as double;
        _threshold = result['threshold'] as double; // **NUOVO**
      });
      await _regeneratePreview();
    }
  }

  Future<void> _onSave() async {
    if (_quad == null) return;
    final finalPath = await DocumentScanner.applyCropAndSave(
      imagePath: widget.originalImagePath,
      quad: _quad!,
      format: widget.format,
      filter: _isCustomizing ? DocScanFilter.custom : _filter,
      brightness: _isCustomizing ? _brightness : null,
      contrast: _isCustomizing ? _contrast : null,
      threshold: _isCustomizing ? _threshold : null, // **NUOVO**
    );
    if (mounted) Navigator.pop(context, finalPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Anteprima Documento"),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _previewImagePath == null ? null : _onSave)],
      ),
      body: _errorMessage != null
          ? Center(child: Text("Errore: $_errorMessage!", style: const TextStyle(color: Colors.red)))
          : _previewImagePath == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(child: Center(child: Image.file(File(_previewImagePath!)))),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton.icon(
            onPressed: _editCrop,
            icon: const Icon(Icons.crop),
            label: const Text("Ritaglia"),
          ),
          TextButton.icon(
            onPressed: _editFilter,
            icon: const Icon(Icons.filter_vintage_outlined),
            label: const Text("Filtri"),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// 3. PAGINA DI RITAGLIO (CropPage)
// --------------------------------------------------

class CropPage extends StatefulWidget {
  final String imagePath;
  final Quadrilateral initialQuad;
  const CropPage({super.key, required this.imagePath, required this.initialQuad});

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  late Quadrilateral _quad;

  @override
  void initState() {
    super.initState();
    _quad = widget.initialQuad;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Modifica Bordi"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _quad),
          )
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return CropEditor(
            imagePath: widget.imagePath,
            initialQuad: _quad,
            onQuadChanged: (newQuad) {
              _quad = newQuad;
            },
            scaffoldBodyConstraints: constraints,
          );
        },
      ),
    );
  }
}

// --------------------------------------------------
// 4. PAGINA DEI FILTRI (FilterPage)
// --------------------------------------------------

class FilterPage extends StatefulWidget {
  final String originalImagePath;
  final Quadrilateral quad;
  final DocScanFilter initialFilter;
  final bool isCustomizing;
  final double initialBrightness;
  final double initialContrast;
  final double initialThreshold; // **NUOVO**

  const FilterPage({
    super.key,
    required this.originalImagePath,
    required this.quad,
    required this.initialFilter,
    required this.isCustomizing,
    required this.initialBrightness,
    required this.initialContrast,
    required this.initialThreshold, // **NUOVO**
  });

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  late DocScanFilter _selectedFilter;
  String? _previewImagePath;
  bool _isRendering = true;

  late bool _isCustomizing;
  late double _brightness;
  late double _contrast;
  late double _threshold; // **NUOVO**

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _isCustomizing = widget.isCustomizing;
    _brightness = widget.initialBrightness;
    _contrast = widget.initialContrast;
    _threshold = widget.initialThreshold; // **NUOVO**
    _regeneratePreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _regeneratePreview() async {
    setState(() => _isRendering = true);
    try {
      final newPath = await DocumentScanner.applyCropAndSave(
        imagePath: widget.originalImagePath,
        quad: widget.quad,
        format: DocScanFormat.jpeg,
        filter: _isCustomizing ? DocScanFilter.custom : _selectedFilter,
        brightness: _isCustomizing ? _brightness : null,
        contrast: _isCustomizing ? _contrast : null,
        threshold: _isCustomizing ? _threshold : null, // **NUOVO**
      );
      setState(() {
        _previewImagePath = newPath;
        _isRendering = false;
      });
    } on PlatformException {
      setState(() => _isRendering = false);
    }
  }

  void _onSliderChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _regeneratePreview();
    });
  }

  void _showCustomFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black12,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Luminosità", style: Theme.of(context).textTheme.titleMedium),
                  Slider(
                    value: _brightness,
                    min: -100.0,
                    max: 100.0,
                    divisions: 20,
                    label: _brightness.round().toString(),
                    onChanged: (value) {
                      setModalState(() => _brightness = value);
                      _onSliderChanged();
                    },
                  ),
                  const SizedBox(height: 16),
                  Text("Contrasto", style: Theme.of(context).textTheme.titleMedium),
                  Slider(
                    value: _contrast,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _contrast.toStringAsFixed(1),
                    onChanged: (value) {
                      setModalState(() => _contrast = value);
                      _onSliderChanged();
                    },
                  ),
                  const SizedBox(height: 16),
                  Text("Soglia B&N", style: Theme.of(context).textTheme.titleMedium), // **NUOVO**
                  Slider(
                    value: _threshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    label: _threshold.toStringAsFixed(2),
                    onChanged: (value) {
                      setModalState(() => _threshold = value);
                      _onSliderChanged();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Seleziona Filtro"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, {
              'filter': _selectedFilter,
              'isCustomizing': _isCustomizing,
              'brightness': _brightness,
              'contrast': _contrast,
              'threshold': _threshold, // **NUOVO**
            }),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isRendering
                ? const Center(child: CircularProgressIndicator())
                : _previewImagePath != null
                ? Center(child: Image.file(File(_previewImagePath!)))
                : const Center(child: Text("Errore anteprima")),
          ),
          _buildFilterBar(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFilterChip(DocScanFilter.none, "Originale", Icons.image_outlined, false),
          _buildFilterChip(DocScanFilter.grayscale, "Grigio", Icons.filter_b_and_w_outlined, false),
          _buildFilterChip(DocScanFilter.blackAndWhite, "B&N", Icons.contrast_outlined, false),
          _buildFilterChip(null, "Custom", Icons.tune_outlined, true),
        ],
      ),
    );
  }

  Widget _buildFilterChip(DocScanFilter? filter, String label, IconData icon, bool isCustom) {
    final bool isSelected = isCustom ? _isCustomizing : (_selectedFilter == filter && !_isCustomizing);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            if (isCustom) {
              setState(() {
                _isCustomizing = true;
              });
              _showCustomFilterSheet();
            } else {
              setState(() {
                _isCustomizing = false;
                _selectedFilter = filter!;
              });
              _regeneratePreview();
            }
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
            ),
            child: Icon(icon, color: isSelected ? Colors.white : Colors.grey.shade700),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade700)),
      ],
    );
  }
}


// --------------------------------------------------
// 5. WIDGET DI EDITING (CropEditor) CON LENTE CORRETTA
// --------------------------------------------------

class CropEditor extends StatefulWidget {
  final String imagePath;
  final Quadrilateral initialQuad;
  final ValueChanged<Quadrilateral> onQuadChanged;
  final BoxConstraints scaffoldBodyConstraints;

  const CropEditor({
    super.key,
    required this.imagePath,
    required this.initialQuad,
    required this.onQuadChanged,
    required this.scaffoldBodyConstraints,
  });

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  late Quadrilateral _quad;
  Size? _imageSize;
  int? _draggingCornerIndex;
  bool _showMagnifier = false;
  Offset _dragPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _quad = widget.initialQuad;
    _loadImageDimensions();
  }

  Future<void> _loadImageDimensions() async {
    final image = FileImage(File(widget.imagePath));
    final completer = Completer<ui.Image>();
    image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        if (!completer.isCompleted) {
          completer.complete(info.image);
        }
      }),
    );
    final ui.Image imageInfo = await completer.future;
    if (mounted) {
      setState(() {
        _imageSize = Size(
          imageInfo.width.toDouble(),
          imageInfo.height.toDouble(),
        );
      });
    }
  }

  void _onPanStart(DragStartDetails details, Size containerSize) {
    double minDistance = double.infinity;
    int? closestCorner;
    final points = [
      _quad.topLeft, _quad.topRight, _quad.bottomRight, _quad.bottomLeft
    ];

    for (int i = 0; i < points.length; i++) {
      final uiPoint = Offset(
        points[i].dx * containerSize.width,
        (1 - points[i].dy) * containerSize.height,
      );
      final distance = (details.localPosition - uiPoint).distance;
      if (distance < minDistance) {
        minDistance = distance;
        closestCorner = i;
      }
    }

    if (minDistance < 44) {
      _handleDrag(details.localPosition, containerSize, closestCorner!);
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size containerSize) {
    if (_draggingCornerIndex == null) return;
    _handleDrag(details.localPosition, containerSize, _draggingCornerIndex!);
  }

  void _handleDrag(Offset localPosition, Size containerSize, int cornerIndex) {
    final double dx = localPosition.dx.clamp(0, containerSize.width) / containerSize.width;
    final double dy = 1 - (localPosition.dy.clamp(0, containerSize.height) / containerSize.height);
    final Offset visionPoint = Offset(dx, dy);

    Quadrilateral newQuad;
    switch (cornerIndex) {
      case 0: newQuad = Quadrilateral(topLeft: visionPoint, topRight: _quad.topRight, bottomLeft: _quad.bottomLeft, bottomRight: _quad.bottomRight); break;
      case 1: newQuad = Quadrilateral(topLeft: _quad.topLeft, topRight: visionPoint, bottomLeft: _quad.bottomLeft, bottomRight: _quad.bottomRight); break;
      case 2: newQuad = Quadrilateral(topLeft: _quad.topLeft, topRight: _quad.topRight, bottomLeft: _quad.bottomLeft, bottomRight: visionPoint); break;
      case 3: newQuad = Quadrilateral(topLeft: _quad.topLeft, topRight: _quad.topRight, bottomLeft: visionPoint, bottomRight: _quad.bottomRight); break;
      default: return;
    }

    setState(() {
      _quad = newQuad;
      _dragPosition = localPosition;
      _draggingCornerIndex = cornerIndex;
      _showMagnifier = true;
    });
    widget.onQuadChanged(newQuad);
  }


  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _draggingCornerIndex = null;
      _showMagnifier = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_imageSize == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: AspectRatio(
          aspectRatio: _imageSize!.width / _imageSize!.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final containerSize = constraints.biggest;
              return Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  Image.file(File(widget.imagePath), fit: BoxFit.contain),
                  CustomPaint(painter: CropPainter(_quad), size: Size.infinite),
                  GestureDetector(
                    onPanStart: (details) => _onPanStart(details, containerSize),
                    onPanUpdate: (details) => _onPanUpdate(details, containerSize),
                    onPanEnd: _onPanEnd,
                    child: Container(color: Colors.transparent),
                  ),
                  ..._buildCornerHandles(containerSize),
                  if (_showMagnifier) _buildMagnifier(containerSize),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMagnifier(Size imageContainerSize) {
    const double magnifierSize = 120;
    const double zoomFactor = 2.0;
    const double verticalOffset = 40.0;

    if (_draggingCornerIndex == null) return const SizedBox.shrink();

    final scaffoldBodySize = widget.scaffoldBodyConstraints.biggest;
    final offsetInScaffold = Offset(
      (scaffoldBodySize.width - imageContainerSize.width) / 2,
      (scaffoldBodySize.height - imageContainerSize.height) / 2,
    );

    double magnifierTop = _dragPosition.dy - magnifierSize - verticalOffset;

    if (magnifierTop + offsetInScaffold.dy < 0) {
      magnifierTop = _dragPosition.dy + verticalOffset;
    }

    final finalLeft = (_dragPosition.dx - magnifierSize / 2 + offsetInScaffold.dx)
        .clamp(0.0, scaffoldBodySize.width - magnifierSize) - offsetInScaffold.dx;

    final finalTop = (magnifierTop + offsetInScaffold.dy)
        .clamp(0.0, scaffoldBodySize.height - magnifierSize) - offsetInScaffold.dy;

    final magnifierPosition = Offset(finalLeft, finalTop);

    final contentLeft = magnifierSize / 2 - _dragPosition.dx * zoomFactor;
    final contentTop = magnifierSize / 2 - _dragPosition.dy * zoomFactor;

    return Positioned(
      left: magnifierPosition.dx,
      top: magnifierPosition.dy,
      child: IgnorePointer(
        child: Container(
          width: magnifierSize,
          height: magnifierSize,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue, width: 2),
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))]
          ),
          child: ClipOval(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: contentLeft,
                  top: contentTop,
                  child: Transform.scale(
                    scale: zoomFactor,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: imageContainerSize.width,
                      height: imageContainerSize.height,
                      child: Stack(
                        children: [
                          Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.contain,
                            alignment: Alignment.topLeft,
                          ),
                          CustomPaint(
                            size: imageContainerSize,
                            painter: CropPainter(_quad),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  width: magnifierSize,
                  height: 1.5,
                  color: Colors.blue.withOpacity(0.7),
                ),
                Container(
                  width: 1.5,
                  height: magnifierSize,
                  color: Colors.blue.withOpacity(0.7),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue, width: 1.5)
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCornerHandles(Size containerSize) {
    final points = [
      _quad.topLeft,
      _quad.topRight,
      _quad.bottomRight,
      _quad.bottomLeft,
    ];

    return List.generate(4, (index) {
      final uiPoint = Offset(
        points[index].dx * containerSize.width,
        (1 - points[index].dy) * containerSize.height,
      );

      return Positioned(
        left: uiPoint.dx - 22,
        top: uiPoint.dy - 22,
        child: IgnorePointer(
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
            ),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.blue, width: 2.5),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2))]
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

// --------------------------------------------------
// 6. WIDGET AUSILIARI (CropPainter, ImageDetailPage)
// --------------------------------------------------

class CropPainter extends CustomPainter {
  final Quadrilateral quad;
  CropPainter(this.quad);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blue..strokeWidth = 2..style = PaintingStyle.stroke;
    final fillPaint = Paint()..color = Colors.blue.withOpacity(0.3);
    final path = Path();
    path.moveTo(quad.topLeft.dx * size.width, (1 - quad.topLeft.dy) * size.height);
    path.lineTo(quad.topRight.dx * size.width, (1 - quad.topRight.dy) * size.height);
    path.lineTo(quad.bottomRight.dx * size.width, (1 - quad.bottomRight.dy) * size.height);
    path.lineTo(quad.bottomLeft.dx * size.width, (1 - quad.bottomLeft.dy) * size.height);
    path.close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ImageDetailPage extends StatelessWidget {
  final String imagePath;

  const ImageDetailPage({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: PhotoView(
        imageProvider: FileImage(File(imagePath)),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2.5,
        heroAttributes: PhotoViewHeroAttributes(tag: imagePath),
      ),
    );
  }
}
