import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Placeholder tile for an attached image.
class MediaThumb extends StatelessWidget {
  const MediaThumb(this.name, {this.onRemove, super.key});

  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 92,
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFD5DFDF), Color(0xFFE6E3EC)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.image_outlined, size: 20, color: AppColors.body),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.ink),
              ),
            ],
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Remove $name',
              onPressed: onRemove,
              icon: const Icon(Icons.cancel, size: 20, color: AppColors.body),
            ),
          ),
      ],
    );
  }
}

/// Two-column grid of media tiles.
class MediaGrid extends StatelessWidget {
  const MediaGrid(this.names, {this.onRemove, super.key});

  final List<String> names;
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
            for (final name in names)
              SizedBox(
                width: width,
                child: MediaThumb(
                  name,
                  onRemove: removal == null ? null : () => removal(name),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Dashed drop zone. In the UI phase, tapping it adds a sample attachment
/// instead of opening the device gallery or camera.
class MediaPickerField extends StatefulWidget {
  const MediaPickerField({
    required this.label,
    this.initial = const [],
    this.onChanged,
    super.key,
  });

  final String label;
  final List<String> initial;
  final ValueChanged<List<String>>? onChanged;

  @override
  State<MediaPickerField> createState() => _MediaPickerFieldState();
}

class _MediaPickerFieldState extends State<MediaPickerField> {
  late final List<String> _media = [...widget.initial];
  var _added = 0;

  void _add() {
    setState(() {
      _added++;
      _media.add('Photo-$_added.jpg');
    });
    widget.onChanged?.call(List.unmodifiable(_media));
  }

  void _remove(String name) {
    setState(() => _media.remove(name));
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
                        'Tap to add images',
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
