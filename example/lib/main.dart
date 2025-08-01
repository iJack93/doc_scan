import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:doc_scan_flutter/doc_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart' as mlkit;
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:photo_view/photo_view.dart';
// **MODIFICATO**: Importa il pacchetto 'path' con un prefisso per evitare conflitti.
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// --------------------------------------------------
// WIDGET PRINCIPALE E PAGINA INIZIALE
// --------------------------------------------------

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
          primaryColor: Colors.blue,
          scaffoldBackgroundColor: const Color(0xFF121212),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1F1F1F),
            elevation: 0,
            centerTitle: false,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFa8c7fa), // Colore azzurro
              foregroundColor: Colors.black, // Testo scuro
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24), // Molto arrotondato
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              )
          )
      ),
      home: const DocScanPage(),
    );
  }
}

class DocScanPage extends StatefulWidget {
  const DocScanPage({super.key});
  @override
  State<DocScanPage> createState() => _DocScanPageState();
}

class _DocScanPageState extends State<DocScanPage> {
  List<String> _finalFilePaths = [];
  String? _errorMessage;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _startScanProcess(String source) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _finalFilePaths = [];
    });

    try {
      String? tempImagePath;
      List<String> resultPaths = [];

      if (Platform.isAndroid && source == 'camera') {
        final options = mlkit.DocumentScannerOptions(
          documentFormat: mlkit.DocumentFormat.jpeg,
          mode: mlkit.ScannerMode.filter,
          pageLimit: 5,
          isGalleryImport: false,
        );
        final documentScanner = mlkit.DocumentScanner(options: options);
        final mlkit.DocumentScanningResult result = await documentScanner.scanDocument();
        resultPaths = result.images;

        if (resultPaths.isNotEmpty) {
          tempImagePath = resultPaths.first;
        } else {
          setState(() => _isLoading = false);
          return;
        }

      } else {
        if (Platform.isAndroid && source == 'gallery') {
          final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
          if (pickedFile != null) {
            final File rotatedImage = await FlutterExifRotation.rotateImage(path: pickedFile.path);
            tempImagePath = rotatedImage.path;
          }
        } else if (Platform.isIOS) {
          tempImagePath = await DocumentScannerManager.getImage(source: source);
        }
      }

      if (tempImagePath == null) {
        setState(() => _isLoading = false);
        return;
      }

      final finalPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewPage(
            originalImagePath: tempImagePath!,
            format: DocScanFormat.pdf,
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

class PreviewPage extends StatefulWidget {
  final String originalImagePath;
  final DocScanFormat format;
  const PreviewPage({super.key, required this.originalImagePath, required this.format});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  Quadrilateral? _quad;
  DocScanFilter _filter = DocScanFilter.shadows; // Default a Ombre
  String? _previewImagePath;
  String? _errorMessage;
  bool _isProcessing = true;
  // Parametri non più usati dalla UI ma necessari per la chiamata
  bool _isCustomizing = false;
  double _brightness = 0.0;
  double _contrast = 1.0;
  double _threshold = 1.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _quad = await DocumentScannerManager.detectEdges(widget.originalImagePath);
      if (_quad != null) {
        await _regeneratePreview();
      } else {
        setState(() {
          _errorMessage = "Nessun documento rilevato.";
          _isProcessing = false;
        });
      }
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isProcessing = false;
      });
    }
  }

  Future<void> _regeneratePreview() async {
    if (_quad == null) return;
    setState(() => _isProcessing = true);
    try {
      final newPreviewPath = await DocumentScannerManager.applyCropAndSave(
        imagePath: widget.originalImagePath,
        quad: _quad!,
        format: DocScanFormat.jpeg,
        filter: _filter,
      );
      if (mounted) {
        setState(() {
          _previewImagePath = newPreviewPath;
          _isProcessing = false;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isProcessing = false;
        });
      }
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
          initialThreshold: _threshold,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _filter = result['filter'] as DocScanFilter;
        _isCustomizing = result['isCustomizing'] as bool;
        _brightness = result['brightness'] as double;
        _contrast = result['contrast'] as double;
        _threshold = result['threshold'] as double;
      });
      await _regeneratePreview();
    }
  }

  Future<void> _onSave() async {
    if (_quad == null) return;
    setState(() => _isProcessing = true);
    final finalPath = await DocumentScannerManager.applyCropAndSave(
      imagePath: widget.originalImagePath,
      quad: _quad!,
      format: widget.format,
      filter: _filter,
    );
    if (mounted) Navigator.pop(context, finalPath);
  }

  Future<bool> _onWillPop() async {
    return (await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annullare la scansione?'),
        content: const Text('Se esci, tutte le modifiche andranno perse.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Esci', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    )) ?? false;
  }

  void _deleteScan() => Navigator.of(context).pop();
  void _rescan() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
          primaryColor: Colors.blue,
          scaffoldBackgroundColor: const Color(0xFF121212),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1F1F1F),
            elevation: 0,
            centerTitle: false,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFa8c7fa),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
          textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Colors.white))
      ),
      child: WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                if (await _onWillPop()) {
                  Navigator.of(context).pop();
                }
              },
            ),
            title: const Text("Anteprima"),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                child: ElevatedButton(
                  onPressed: _previewImagePath == null ? null : _onSave,
                  child: const Text("Fine"),
                ),
              )
            ],
          ),
          body: _errorMessage != null
              ? Center(child: Text("Errore: $_errorMessage!", style: const TextStyle(color: Colors.red)))
              : _isProcessing
              ? const Center(child: CircularProgressIndicator())
              : Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: PhotoView(
                    imageProvider: FileImage(File(_previewImagePath!)),
                    backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                    minScale: PhotoViewComputedScale.contained,
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 100,
      decoration: BoxDecoration(color: Theme.of(context).appBarTheme.backgroundColor),
      child: SizedBox(
        height: 80,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          children: [
            _buildToolButton(Icons.crop_rotate, "Ritaglia e ruota", _editCrop),
            const SizedBox(width: 24),
            _buildToolButton(Icons.auto_fix_high, "Filtro", _editFilter),
            const SizedBox(width: 24),
            _buildToolButton(Icons.add_a_photo_outlined, "Nuovo scatto", _rescan),
            const SizedBox(width: 24),
            _buildToolButton(Icons.delete_outline, "Elimina", _deleteScan),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class CropPage extends StatefulWidget {
  final String imagePath;
  final Quadrilateral initialQuad;
  const CropPage({super.key, required this.imagePath, required this.initialQuad});

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  late Quadrilateral _quad;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _quad = widget.initialQuad;
  }

  Future<void> _resetToAutoCrop() async {
    setState(() => _isDetecting = true);
    try {
      final newQuad = await DocumentScannerManager.detectEdges(widget.imagePath);
      if (newQuad != null && mounted) {
        setState(() => _quad = newQuad);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore rilevamento bordi: ${e.message}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
    }
  }

  void _resetToFullCrop() {
    setState(() {
      _quad = Quadrilateral(
        topLeft: const Offset(0, 1),
        topRight: const Offset(1, 1),
        bottomLeft: const Offset(0, 0),
        bottomRight: const Offset(1, 0),
      );
    });
  }

  void _rotateCrop() {
    setState(() {
      _quad = Quadrilateral(
        topLeft: _quad.bottomLeft,
        topRight: _quad.topLeft,
        bottomRight: _quad.topRight,
        bottomLeft: _quad.bottomRight,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ritaglia e ruota")),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return CropEditor(
                      imagePath: widget.imagePath,
                      initialQuad: _quad,
                      onQuadChanged: (newQuad) {
                        if (!_isDetecting) _quad = newQuad;
                      },
                      scaffoldBodyConstraints: constraints,
                    );
                  },
                ),
              ),
              _buildBottomBar(),
            ],
          ),
          if (_isDetecting)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _buildToolButton(Icons.crop_free, "Ritaglia automatico", _isDetecting ? null : _resetToAutoCrop),
                const SizedBox(width: 28),
                _buildToolButton(Icons.fullscreen, "Nessun ritaglio", _isDetecting ? null : _resetToFullCrop),
                const SizedBox(width: 28),
                _buildToolButton(Icons.rotate_90_degrees_ccw_outlined, "Ruota", _isDetecting ? null : _rotateCrop),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: _isDetecting ? null : () => Navigator.pop(context, _quad),
                  child: const Text("Applica"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, VoidCallback? onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

class FilterPage extends StatefulWidget {
  final String originalImagePath;
  final Quadrilateral quad;
  final DocScanFilter initialFilter;
  final bool isCustomizing;
  final double initialBrightness;
  final double initialContrast;
  final double initialThreshold;

  const FilterPage({
    super.key,
    required this.originalImagePath,
    required this.quad,
    required this.initialFilter,
    required this.isCustomizing,
    required this.initialBrightness,
    required this.initialContrast,
    required this.initialThreshold,
  });

  @override
  State<FilterPage> createState() => _FilterPageState();
}

class _FilterPageState extends State<FilterPage> {
  late int _selectedFilterIndex;
  String? _previewImagePath;
  bool _isRendering = true;

  final List<Map<String, dynamic>> _filters = [
    {'name': 'Nessuno', 'icon': Icons.block, 'filter': DocScanFilter.none},
    {'name': 'Automatico', 'icon': Icons.auto_fix_high_outlined, 'filter': DocScanFilter.automatic},
    {'name': 'Colore', 'icon': Icons.color_lens_outlined, 'filter': DocScanFilter.color},
    {'name': 'Scala di grigi', 'icon': Icons.filter_b_and_w_outlined, 'filter': DocScanFilter.grayscale},
    {'name': 'B/N', 'icon': Icons.contrast_outlined, 'filter': DocScanFilter.blackAndWhite},
    {'name': 'Ombre', 'icon': Icons.nightlight_outlined, 'filter': DocScanFilter.shadows},
  ];

  @override
  void initState() {
    super.initState();
    _selectedFilterIndex = 0; // Default a "Nessuno"
    _regeneratePreview();
  }

  Future<void> _regeneratePreview() async {
    setState(() => _isRendering = true);
    try {
      final selectedFilter = _filters[_selectedFilterIndex]['filter'] as DocScanFilter;
      final newPath = await DocumentScannerManager.applyCropAndSave(
        imagePath: widget.originalImagePath,
        quad: widget.quad,
        format: DocScanFormat.jpeg,
        filter: selectedFilter,
      );
      if (mounted) {
        setState(() {
          _previewImagePath = newPath;
          _isRendering = false;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _isRendering = false);
    }
  }

  void _onApply() {
    final selectedFilter = _filters[_selectedFilterIndex]['filter'] as DocScanFilter;
    Navigator.pop(context, {
      'filter': selectedFilter,
      'isCustomizing': false,
      'brightness': 0.0,
      'contrast': 1.0,
      'threshold': 1.0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Filtro"),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isRendering
                ? const Center(child: CircularProgressIndicator())
                : _previewImagePath != null
                ? Padding(
              padding: const EdgeInsets.all(24.0),
              child: PhotoView(
                imageProvider: FileImage(File(_previewImagePath!)),
                backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                minScale: PhotoViewComputedScale.contained,
              ),
            )
                : const Center(child: Text("Errore anteprima")),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final Color selectedColor = Theme.of(context).elevatedButtonTheme.style?.backgroundColor?.resolve({}) ?? const Color(0xFFa8c7fa);
    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 70,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: _filters.length,
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final bool isSelected = index == _selectedFilterIndex;

                    final filterWidget = GestureDetector(
                      onTap: () {
                        setState(() => _selectedFilterIndex = index);
                        _regeneratePreview();
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12.0),
                        color: Colors.transparent,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              filter['icon'] as IconData,
                              color: isSelected ? selectedColor : Colors.white,
                              size: 28,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              filter['name'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? selectedColor : Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );

                    if (filter['name'] == 'Ombre') {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 40,
                            width: 1,
                            color: Colors.grey.shade700,
                            margin: const EdgeInsets.only(right: 12.0),
                          ),
                          filterWidget,
                        ],
                      );
                    }

                    return filterWidget;
                  },
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: _onApply,
                      child: const Text("Applica"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


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

  @override
  void didUpdateWidget(covariant CropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuad != oldWidget.initialQuad) {
      setState(() {
        _quad = widget.initialQuad;
      });
    }
  }

  Future<void> _loadImageDimensions() async {
    final image = FileImage(File(widget.imagePath));
    final completer = Completer<ui.Image>();
    image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        if (!completer.isCompleted) completer.complete(info.image);
      }),
    );
    final ui.Image imageInfo = await completer.future;
    if (mounted) {
      setState(() {
        _imageSize = Size(imageInfo.width.toDouble(), imageInfo.height.toDouble());
      });
    }
  }

  void _onPanStart(DragStartDetails details, Size containerSize) {
    double minDistance = double.infinity;
    int? closestCorner;
    final points = [_quad.topLeft, _quad.topRight, _quad.bottomRight, _quad.bottomLeft];

    for (int i = 0; i < points.length; i++) {
      final uiPoint = Offset(points[i].dx * containerSize.width, (1 - points[i].dy) * containerSize.height);
      final distance = (details.localPosition - uiPoint).distance;
      if (distance < 44) {
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
    if (_imageSize == null) return const Center(child: CircularProgressIndicator());
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
    final offsetInScaffold = Offset((scaffoldBodySize.width - imageContainerSize.width) / 2, (scaffoldBodySize.height - imageContainerSize.height) / 2);
    double magnifierTop = _dragPosition.dy - magnifierSize - verticalOffset;
    if (magnifierTop + offsetInScaffold.dy < 0) magnifierTop = _dragPosition.dy + verticalOffset;
    final finalLeft = (_dragPosition.dx - magnifierSize / 2 + offsetInScaffold.dx).clamp(0.0, scaffoldBodySize.width - magnifierSize) - offsetInScaffold.dx;
    final finalTop = (magnifierTop + offsetInScaffold.dy).clamp(0.0, scaffoldBodySize.height - magnifierSize) - offsetInScaffold.dy;
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
                          Image.file(File(widget.imagePath), fit: BoxFit.contain, alignment: Alignment.topLeft),
                          CustomPaint(size: imageContainerSize, painter: CropPainter(_quad)),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(width: magnifierSize, height: 1.5, color: Colors.blue.withOpacity(0.7)),
                Container(width: 1.5, height: magnifierSize, color: Colors.blue.withOpacity(0.7)),
                Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.blue, width: 1.5))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCornerHandles(Size containerSize) {
    final points = [_quad.topLeft, _quad.topRight, _quad.bottomRight, _quad.bottomLeft];
    return List.generate(4, (index) {
      final uiPoint = Offset(points[index].dx * containerSize.width, (1 - points[index].dy) * containerSize.height);
      return Positioned(
        left: uiPoint.dx - 22,
        top: uiPoint.dy - 22,
        child: IgnorePointer(
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
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
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0, iconTheme: const IconThemeData(color: Colors.white)),
      body: PhotoView(
        imageProvider: FileImage(File(imagePath)),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 2.5,
        heroAttributes: PhotoViewHeroAttributes(tag: imagePath),
      ),
    );
  }
}
