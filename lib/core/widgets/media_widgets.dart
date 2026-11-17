import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../media/photo_service.dart';
import '../theme/app_colors.dart';

PhotoService? _photos(BuildContext context) {
  try {
    return context.read<PhotoService>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// The picture for [photo]: a local file, a stored photo, or a placeholder
/// showing the name (sample data, or a photo that can't load).
class _PhotoImage extends StatelessWidget {
  const _PhotoImage(this.photo, {this.fit = BoxFit.cover});

  final String photo;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (isLocalPhoto(photo)) {
      return Image.file(
        File(photo),
        fit: fit,
        errorBuilder: (_, _, _) => _Placeholder(photo),
      );
    }
    final photos = _photos(context);
    if (!isStoredPhoto(photo) || photos == null) return _Placeholder(photo);
    return FutureBuilder<String?>(
      future: photos.downloadUrl(photo),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) {
          return snapshot.connectionState == ConnectionState.done
              ? _Placeholder(photo)
              : const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
        }
        return Image.network(
          url,
          fit: fit,
          errorBuilder: (_, _, _) => _Placeholder(photo),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.photo);

  final String photo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD5DFDF), Color(0xFFE6E3EC)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.image_outlined, size: 20, color: AppColors.body),
          const SizedBox(height: 4),
          Text(
            photoName(photo),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// One attached image. Tapping it opens it full screen.
class MediaThumb extends StatelessWidget {
  const MediaThumb(this.photo, {this.onRemove, super.key});

  final String photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Semantics(
          button: true,
          label: 'Open photo ${photoName(photo)}',
          child: GestureDetector(
            onTap: () => showPhoto(context, photo),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 92,
                width: double.infinity,
                child: _PhotoImage(photo),
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Remove ${photoName(photo)}',
              onPressed: onRemove,
              icon: const Icon(Icons.cancel, size: 20, color: AppColors.body),
            ),
          ),
      ],
    );
  }
}

/// Shows [photo] full screen, with pinch to zoom.
Future<void> showPhoto(BuildContext context, String photo) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          title: const Text('Photo'),
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: _PhotoImage(photo, fit: BoxFit.contain),
          ),
        ),
      ),
    ),
  );
}

/// Two-column grid of images.
class MediaGrid extends StatelessWidget {
  const MediaGrid(this.photos, {this.onRemove, super.key});

  final List<String> photos;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final removal = onRemove;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final photo in photos)
              SizedBox(
                width: width,
                child: MediaThumb(
                  photo,
                  onRemove: removal == null ? null : () => removal(photo),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Dashed drop zone that adds photos from the camera or the gallery.
class MediaPickerField extends StatefulWidget {
  const MediaPickerField({
    required this.label,
    this.initial = const [],
    this.max = 4,
    this.onChanged,
    super.key,
  });

  final String label;
  final List<String> initial;

  /// Most photos allowed, matching firestore.rules.
  final int max;
  final ValueChanged<List<String>>? onChanged;

  @override
  State<MediaPickerField> createState() => _MediaPickerFieldState();
}

class _MediaPickerFieldState extends State<MediaPickerField> {
  late final List<String> _media = [...widget.initial];

  Future<void> _add() async {
    final photos = _photos(context);
    if (photos == null) return;
    final room = widget.max - _media.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can add up to ${widget.max} photos.')),
      );
      return;
    }
    final source = photos.asksForSource
        ? await _chooseSource()
        : PhotoSource.gallery;
    if (source == null) return;
    try {
      final picked = await photos.pick(source, max: room);
      if (picked.isEmpty || !mounted) return;
      setState(() => _media.addAll(picked.take(room)));
      widget.onChanged?.call(List.unmodifiable(_media));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == PhotoSource.camera
                ? 'The camera couldn’t open. Check the app’s camera permission.'
                : 'Your photos couldn’t open. Check the app’s photo permission.',
          ),
        ),
      );
    }
  }

  Future<PhotoSource?> _chooseSource() => showModalBottomSheet<PhotoSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, PhotoSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, PhotoSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  void _remove(String photo) {
    setState(() => _media.remove(photo));
    widget.onChanged?.call(List.unmodifiable(_media));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomPaint(
            painter: const _DashedBorderPainter(),
            child: Material(
              color: const Color(0xFFFDF8FB),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _add,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 22,
                    horizontal: 16,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to add images · up to ${widget.max}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_media.isNotEmpty) ...[
            const SizedBox(height: 10),
            MediaGrid(_media, onRemove: _remove),
          ],
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD9A9CB)
      ..style = PaintingStyle.stroke;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      );
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
