import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:media_scanner/media_scanner.dart';
import 'package:http/http.dart' as http;
import 'background_remover.dart';

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
  Uint8List? _cachedScaledBytes;
  final ImagePicker _picker = ImagePicker();
  double _brightness = 0.0;
  double _contrast = 1.0;
  String? _selectedFilter;
  double _rotationAngle = 0.0;
  Timer? _debounceTimer;
  bool _hasChanges = false;
  bool _isRemovingBackground = false;

  static final List<ColorFilterOption> _colorFilters = [
    ColorFilterOption(name: 'None', applyFilter: (image) => image),
    ColorFilterOption(
      name: 'Grayscale',
      applyFilter: (image) => img.grayscale(image),
    ),
    ColorFilterOption(name: 'Sepia', applyFilter: (image) => img.sepia(image)),
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
      final scaledBytes = await _scaleDownImage(bytes, maxDimension: 600);
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
        _isRemovingBackground = false;
      });
    }
  }

  Future<Uint8List> _scaleDownImage(
    Uint8List bytes, {
    required int maxDimension,
  }) async {
    return compute((Uint8List inputBytes) {
      var image = img.decodeImage(inputBytes)!;
      if (image.width > maxDimension || image.height > maxDimension) {
        image = img.copyResize(
          image,
          width: image.width > image.height ? maxDimension : null,
          height: image.width <= image.height ? maxDimension : null,
          interpolation: img.Interpolation.linear,
        );
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
    if (rotation != 0.0) {
      image = img.copyRotate(image, angle: rotation);
    }
    final filter = _colorFilters.firstWhere((f) => f.name == filterName);
    if (filter.name != 'None') {
      image = filter.applyFilter(image);
    }
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
      final scaledBytes =
          _cachedScaledBytes ??
          await _scaleDownImage(_originalImageBytes!, maxDimension: 600);
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

  Future<void> _removeBackground() async {
    if (_imageFile == null || _originalImageBytes == null) return;
    setState(() {
      _isRemovingBackground = true;
    });
    try {
      final apiKey = 'DaUvpj4VYpacoj2DzCDiVbjf'; // Replace with your API key
      final result = await BackgroundRemover.removeBackground(
        _originalImageBytes!,
        apiKey,
      );
      final newFile = File(_imageFile!.path.replaceAll('.png', '_nobg.png'))
        ..writeAsBytesSync(result);
      setState(() {
        _imageFile = newFile;
        _originalImageBytes = result;
        _cachedScaledBytes = null;
        _previewImageBytes = null;
        _hasChanges = true;
      });
      await _updatePreview();
      await MediaScanner.loadMedia(path: newFile.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Background removed successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove background: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRemovingBackground = false;
        });
      }
    }
  }

  Future<void> _saveAllChanges() async {
    if (_imageFile == null || !_hasChanges || _originalImageBytes == null)
      return;
    final adjustedBytes = await compute(_applyAdjustmentsIsolate, {
      'bytes': _originalImageBytes!,
      'brightness': _brightness,
      'contrast': _contrast,
      'filter': _selectedFilter ?? 'None',
      'rotation': _rotationAngle,
    });
    final directory = Directory('/storage/emulated/0/Pictures/ImageConverter');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final newPath =
        '${directory.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png';
    final newFile = File(newPath)..writeAsBytesSync(adjustedBytes);
    setState(() {
      _imageFile = newFile;
      _originalImageBytes = adjustedBytes;
      _cachedScaledBytes = null;
      _previewImageBytes = null;
      _hasChanges = false;
    });
    await MediaScanner.loadMedia(path: newPath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Image saved successfully!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Widget _customButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool isLoading = false,
    bool isPrimary = false,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors:
                isPrimary
                    ? isDarkMode
                        ? [Colors.blue.shade700, Colors.blue.shade900]
                        : [Colors.blue.shade400, Colors.blue.shade600]
                    : isDarkMode
                    ? [Colors.indigo.shade800, Colors.purple.shade800]
                    : [Colors.deepPurple.shade400, Colors.indigo.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            isLoading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                : Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () => _applyFilter(filterName),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? (isDarkMode ? Colors.blue.shade700 : Colors.blue.shade400)
                    : (isDarkMode
                        ? Colors.grey.shade800.withOpacity(0.5)
                        : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(10),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                    : [],
          ),
          child: Text(
            filterName,
            style: TextStyle(
              color:
                  isSelected
                      ? Colors.white
                      : (isDarkMode ? Colors.white70 : Colors.black87),
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _customSlider(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${value.toStringAsFixed(1)}',
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor:
                isDarkMode ? Colors.blue.shade400 : Colors.blue.shade600,
            inactiveTrackColor:
                isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
            thumbColor: Colors.white,
            overlayColor: (isDarkMode
                    ? Colors.blue.shade400
                    : Colors.blue.shade600)
                .withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: (value) {
              setState(() {
                onChanged(value);
              });
              _updatePreview();
            },
          ),
        ),
      ],
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
              color:
                  isDarkMode
                      ? Colors.black.withOpacity(0.4)
                      : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/logo1.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        title: const Text(
          'Image Editor',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 20,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors:
                  isDarkMode
                      ? [Colors.blue.shade900, Colors.indigo.shade900]
                      : [Colors.blue.shade500, Colors.indigo.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors:
                    isDarkMode
                        ? [Colors.blue.shade900, Colors.indigo.shade900]
                        : [Colors.blue.shade50, Colors.indigo.shade50],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color:
                                isDarkMode
                                    ? Colors.grey.shade900.withOpacity(0.8)
                                    : Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  isDarkMode ? 0.2 : 0.1,
                                ),
                                blurRadius: 12,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 320,
                                decoration: BoxDecoration(
                                  color:
                                      isDarkMode
                                          ? Colors.grey.shade800
                                          : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(
                                        isDarkMode ? 0.2 : 0.1,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child:
                                      _previewImageBytes == null
                                          ? const Center(
                                            child: Text(
                                              "No Image Selected",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          )
                                          : Image.memory(
                                            _previewImageBytes!,
                                            fit: BoxFit.contain,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Center(
                                                      child: Text(
                                                        "Error loading image",
                                                        style: TextStyle(
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ),
                                          ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: _customButton(
                                      Icons.add_photo_alternate,
                                      "Pick Image",
                                      _pickImage,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _customButton(
                                      Icons.rotate_right,
                                      "Rotate",
                                      _rotateImage,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: _customButton(
                                  Icons.layers_clear,
                                  "Remove Background",
                                  _removeBackground,
                                  isLoading: _isRemovingBackground,
                                  isPrimary: true,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                "Color Filters",
                                style: TextStyle(
                                  color:
                                      isDarkMode
                                          ? Colors.white
                                          : Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children:
                                      _colorFilters
                                          .map(
                                            (filter) =>
                                                _filterButton(filter.name),
                                          )
                                          .toList(),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _customSlider(
                                "Brightness",
                                _brightness,
                                -1.0,
                                1.0,
                                (value) => _brightness = value,
                              ),
                              const SizedBox(height: 12),
                              _customSlider(
                                "Contrast",
                                _contrast,
                                0.0,
                                2.0,
                                (value) => _contrast = value,
                              ),
                              const SizedBox(height: 20),
                              Center(
                                child: _customButton(
                                  Icons.save,
                                  "Save Changes",
                                  _saveAllChanges,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isRemovingBackground)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Removing Background...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
