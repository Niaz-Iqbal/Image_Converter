import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/image_editor.dart' as editor;
import 'package:media_scanner/media_scanner.dart';

class ColorFilterOption {
  final String name;
  final Function(img.Image) applyFilter;

  ColorFilterOption({required this.name, required this.applyFilter});
}

class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({super.key});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  File? _imageFile;
  Uint8List? _originalImageBytes;
  Uint8List? _previewImageBytes;
  Uint8List? _cachedScaledBytes; // Cache for scaled preview image
  final ImagePicker _picker = ImagePicker();
  double _brightness = 0.0;
  double _contrast = 1.0;
  String? _selectedFilter;
  double _rotationAngle = 0.0;
  Timer? _debounceTimer;
  bool _hasChanges = false;

  // List of color filter options (defined once for efficiency)
  static final List<ColorFilterOption> _colorFilters = [
    ColorFilterOption(
      name: 'None',
      applyFilter: (image) => image,
    ),
    ColorFilterOption(
      name: 'Grayscale',
      applyFilter: (image) => img.grayscale(image),
    ),
    ColorFilterOption(
      name: 'Sepia',
      applyFilter: (image) => img.sepia(image),
    ),
    ColorFilterOption(
      name: 'Invert',
      applyFilter: (image) {
        for (var pixel in image) {
          pixel.r = 255 - pixel.r;
          pixel.g = 255 - pixel.g;
          pixel.b = 255 - pixel.b;
        }
        return image;
      },
    ),
    ColorFilterOption(
      name: 'Vintage',
      applyFilter: (image) {
        for (var pixel in image) {
          pixel.r = (pixel.r * 0.9 + pixel.g * 0.1).clamp(0, 255).toInt();
          pixel.g = (pixel.g * 0.7 + pixel.b * 0.2).clamp(0, 255).toInt();
          pixel.b = (pixel.b * 0.8 + pixel.r * 0.1).clamp(0, 255).toInt();
        }
        return image;
      },
    ),
    ColorFilterOption(
      name: 'Cool Tone',
      applyFilter: (image) {
        for (var pixel in image) {
          pixel.b = (pixel.b * 1.2).clamp(0, 255).toInt();
          pixel.r = (pixel.r * 0.9).clamp(0, 255).toInt();
        }
        return image;
      },
    ),
    ColorFilterOption(
      name: 'Warm Tone',
      applyFilter: (image) {
        for (var pixel in image) {
          pixel.r = (pixel.r * 1.2).clamp(0, 255).toInt();
          pixel.g = (pixel.g * 1.1).clamp(0, 255).toInt();
          pixel.b = (pixel.b * 0.9).clamp(0, 255).toInt();
        }
        return image;
      },
    ),
  ];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _originalImageBytes = null;
    _previewImageBytes = null;
    _cachedScaledBytes = null;
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final scaledBytes = await _scaleDownImage(bytes, maxDimension: 600); // Higher resolution for preview
      setState(() {
        _imageFile = file;
        _originalImageBytes = bytes;
        _cachedScaledBytes = scaledBytes;
        _previewImageBytes = scaledBytes;
        _brightness = 0.0;
        _contrast = 1.0;
        _selectedFilter = 'None';
        _rotationAngle = 0.0;
        _hasChanges = false;
      });
    }
  }

  Future<Uint8List> _scaleDownImage(Uint8List bytes, {required int maxDimension}) async {
    return compute((Uint8List inputBytes) {
      var image = img.decodeImage(inputBytes)!;
      if (image.width > maxDimension || image.height > maxDimension) {
        image = img.copyResize(image,
            width: image.width > image.height ? maxDimension : null,
            height: image.width <= image.height ? maxDimension : null,
            interpolation: img.Interpolation.linear); // Smooth resizing
      }
      return img.encodePng(image, level: 4);
    }, bytes);
  }

  static Uint8List _applyAdjustmentsIsolate(Map<String, dynamic> params) {
    final bytes = params['bytes'] as Uint8List;
    final brightness = params['brightness'] as double;
    final contrast = params['contrast'] as double;
    final filterName = params['filter'] as String;
    final rotation = params['rotation'] as double;

    var image = img.decodeImage(bytes)!;

    // Apply rotation
    if (rotation != 0.0) {
      image = img.copyRotate(image, angle: rotation);
    }

    // Apply color filter
    final filter = _colorFilters.firstWhere((f) => f.name == filterName);
    if (filter.name != 'None') {
      image = filter.applyFilter(image);
    }

    // Apply brightness and contrast only if needed
    if (brightness != 0.0 || contrast != 1.0) {
      final brightnessOffset = brightness * 255;
      final contrastFactor = contrast;
      for (var pixel in image) {
        var r = pixel.r;
        var g = pixel.g;
        var b = pixel.b;

        if (brightness != 0.0) {
          r = (r + brightnessOffset).clamp(0, 255).toInt();
          g = (g + brightnessOffset).clamp(0, 255).toInt();
          b = (b + brightnessOffset).clamp(0, 255).toInt();
        }

        if (contrast != 1.0) {
          r = ((r - 128) * contrastFactor + 128).clamp(0, 255).toInt();
          g = ((g - 128) * contrastFactor + 128).clamp(0, 255).toInt();
          b = ((b - 128) * contrastFactor + 128).clamp(0, 255).toInt();
        }

        pixel.r = r;
        pixel.g = g;
        pixel.b = b;
      }
    }

    return img.encodePng(image, level: 4);
  }

  Future<void> _updatePreview() async {
    if (_originalImageBytes == null) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () async {
      final scaledBytes = _cachedScaledBytes ?? await _scaleDownImage(_originalImageBytes!, maxDimension: 600);
      if (_cachedScaledBytes == null) {
        _cachedScaledBytes = scaledBytes;
      }
      final adjustedBytes = await compute(_applyAdjustmentsIsolate, {
        'bytes': scaledBytes,
        'brightness': _brightness,
        'contrast': _contrast,
        'filter': _selectedFilter ?? 'None',
        'rotation': _rotationAngle,
      });
      if (mounted) {
        setState(() {
          _previewImageBytes = adjustedBytes;
          _hasChanges = true;
        });
      }
    });
  }

  Future<void> _applyFilter(String filterName) async {
    if (_imageFile == null) return;
    setState(() {
      _selectedFilter = filterName;
    });
    await _updatePreview();
  }

  Future<void> _rotateImage() async {
    if (_imageFile == null) return;
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
    });
    await _updatePreview();
  }

  Future<void> _saveAllChanges() async {
    if (_imageFile == null || !_hasChanges || _originalImageBytes == null) return;
    final adjustedBytes = await compute(_applyAdjustmentsIsolate, {
      'bytes': _originalImageBytes!, // Use original high-resolution image
      'brightness': _brightness,
      'contrast': _contrast,
      'filter': _selectedFilter ?? 'None',
      'rotation': _rotationAngle,
    });
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final newPath = '${directory.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png';
    final newFile = File(newPath)..writeAsBytesSync(adjustedBytes);
    setState(() {
      _imageFile = newFile;
      _originalImageBytes = adjustedBytes;
      _cachedScaledBytes = null;
      _previewImageBytes = null; // Clear preview to force re-scale
      _hasChanges = false;
    });
    await MediaScanner.loadMedia(path: newPath);
  }

  Widget _customButton(IconData icon, String label, VoidCallback onPressed) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDarkMode
                ? [Colors.indigo.shade800, Colors.purple.shade800]
                : [Colors.deepPurpleAccent, Colors.indigoAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.4 : 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterButton(String filterName) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isSelected = _selectedFilter == filterName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: GestureDetector(
        onTap: () => _applyFilter(filterName),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode ? Colors.indigo.shade600 : Colors.indigoAccent)
                : (isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : (isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400),
            ),
          ),
          child: Text(
            filterName,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : (isDarkMode ? Colors.white70 : Colors.black87),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo1.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        title: const Text(
          'Image Editor',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDarkMode
                  ? [Colors.indigo.shade900, Colors.purple.shade900]
                  : [Colors.indigoAccent, Colors.deepPurpleAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: false,
        elevation: 4,
        shadowColor: Colors.black45,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDarkMode
                ? [Colors.indigo.shade900, Colors.purple.shade900]
                : [Colors.indigoAccent, Colors.purpleAccent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDarkMode
                            ? [
                                theme.colorScheme.surfaceContainerHighest
                                    .withOpacity(0.7),
                                theme.colorScheme.surfaceContainerLow
                                    .withOpacity(0.7)
                              ]
                            : [
                                theme.colorScheme.surfaceContainerHighest
                                    .withOpacity(0.9),
                                theme.colorScheme.surfaceContainerLow
                                    .withOpacity(0.9)
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                          blurRadius: 15,
                          spreadRadius: 2,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _previewImageBytes == null
                            ? Container(
                                height: 300, // Increased for better preview
                                alignment: Alignment.center,
                                child: const Text(
                                  "No Image Selected",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : Image.memory(
                                _previewImageBytes!,
                                height: 300, // Increased for better preview
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Text("Error loading image"),
                              ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                                child: _customButton(
                                    Icons.image, "Image", _pickImage)),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _customButton(
                                    Icons.rotate_right, "Rotate", _rotateImage)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Color Filters",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _colorFilters
                                .map((filter) => _filterButton(filter.name))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Brightness: ${_brightness.toStringAsFixed(1)}",
                          style:
                              TextStyle(color: theme.colorScheme.onSurface),
                        ),
                        Slider(
                          value: _brightness,
                          min: -1.0,
                          max: 1.0,
                          onChanged: (value) {
                            setState(() {
                              _brightness = value;
                            });
                            _updatePreview();
                          },
                        ),
                        Text(
                          "Contrast: ${_contrast.toStringAsFixed(1)}",
                          style:
                              TextStyle(color: theme.colorScheme.onSurface),
                        ),
                        Slider(
                          value: _contrast,
                          min: 0.0,
                          max: 2.0,
                          onChanged: (value) {
                            setState(() {
                              _contrast = value;
                            });
                            _updatePreview();
                          },
                        ),
                        const SizedBox(height: 16),
                        _customButton(Icons.save, "Save", _saveAllChanges),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}