import 'package:flutter/material.dart';

class DeviceIllustration extends StatelessWidget {
  const DeviceIllustration({
    super.key,
    required this.artworkKey,
    this.modelId,
    this.compact = false,
  });

  final String artworkKey;
  final String? modelId;
  final bool compact;

  static const _editorArtworkKeys = {
    '6b023',
    '6b023_ext1',
    '6b023_ext2',
    '6b023_ext3',
    '2b034',
    '2b034_ext1',
    '2b034_ext2',
    '2b034_ext3',
    '2b034_ext4',
    '2b034_ext10',
    '2b034_ext11',
    '2b034_ext12',
    '2b034_ext13',
    '2b043',
    '2b043_ext10',
    '2b043_ext11',
    '2b043_ext12',
    '2b043_ext13',
  };

  @override
  Widget build(BuildContext context) {
    final catalogKey = _catalogKey;
    final fallback = CustomPaint(
      painter: _DevicePainter(
        artworkKey: artworkKey,
        colorScheme: Theme.of(context).colorScheme,
      ),
      size: compact ? const Size(42, 50) : Size.infinite,
    );
    if (catalogKey == null) return fallback;

    final useEditor = !compact && _editorArtworkKeys.contains(catalogKey);
    final assetPath = useEditor
        ? 'assets/devices/editor/$catalogKey.png'
        : 'assets/devices/catalog/$catalogKey.png';
    final baseKey = catalogKey.split('_ext').first;

    Widget image(String path, {required Widget errorFallback}) => Image.asset(
      path,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => errorFallback,
    );

    final coreFallback = catalogKey == baseKey
        ? fallback
        : image('assets/devices/catalog/$baseKey.png', errorFallback: fallback);
    return Semantics(
      image: true,
      label: 'Logitech device',
      child: image(assetPath, errorFallback: coreFallback),
    );
  }

  String? get _catalogKey {
    if (artworkKey.startsWith('model_')) {
      return artworkKey.substring('model_'.length).toLowerCase();
    }
    final normalizedModel = modelId?.toLowerCase();
    if (normalizedModel != null &&
        normalizedModel.isNotEmpty &&
        normalizedModel != 'unknown') {
      return normalizedModel;
    }
    return null;
  }
}

class _DevicePainter extends CustomPainter {
  const _DevicePainter({required this.artworkKey, required this.colorScheme});

  final String artworkKey;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final scale = size.shortestSide;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * .035);
    final body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surfaceContainerHighest,
          colorScheme.surfaceContainer,
        ],
      ).createShader(bounds)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = colorScheme.outline.withValues(alpha: .65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = maxOf(1.2, scale * .009);
    final detail = Paint()
      ..color = colorScheme.onSurfaceVariant.withValues(alpha: .72)
      ..style = PaintingStyle.fill;

    switch (artworkKey) {
      case 'trackball':
        _paintTrackball(canvas, size, shadow, body, outline, detail);
      case 'vertical':
        _paintVertical(canvas, size, shadow, body, outline, detail);
      case 'mx_anywhere':
        _paintMouse(canvas, size, .62, shadow, body, outline, detail);
      case 'mx_master_4':
        _paintMaster(
          canvas,
          size,
          shadow,
          body,
          outline,
          detail,
          hapticPanel: true,
        );
      case 'mx_master':
        _paintMaster(canvas, size, shadow, body, outline, detail);
      default:
        _paintMouse(canvas, size, .72, shadow, body, outline, detail);
    }
  }

  void _paintMouse(
    Canvas canvas,
    Size size,
    double widthFactor,
    Paint shadow,
    Paint body,
    Paint outline,
    Paint detail,
  ) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .52),
        width: size.width * widthFactor,
        height: size.height * .88,
      ),
      Radius.elliptical(size.width * .25, size.height * .25),
    );
    canvas.drawRRect(rect.shift(Offset(0, size.height * .015)), shadow);
    canvas.drawRRect(rect, body);
    canvas.drawRRect(rect, outline);
    canvas.drawLine(
      Offset(size.width * .5, size.height * .09),
      Offset(size.width * .5, size.height * .44),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .5, size.height * .27),
          width: size.width * .085,
          height: size.height * .17,
        ),
        Radius.circular(size.width * .04),
      ),
      detail,
    );
  }

  void _paintMaster(
    Canvas canvas,
    Size size,
    Paint shadow,
    Paint body,
    Paint outline,
    Paint detail, {
    bool hapticPanel = false,
  }) {
    final path = Path()
      ..moveTo(size.width * .29, size.height * .08)
      ..cubicTo(
        size.width * .70,
        size.height * .02,
        size.width * .84,
        size.height * .25,
        size.width * .78,
        size.height * .62,
      )
      ..cubicTo(
        size.width * .73,
        size.height * .91,
        size.width * .43,
        size.height * .98,
        size.width * .22,
        size.height * .79,
      )
      ..cubicTo(
        size.width * .08,
        size.height * .66,
        size.width * .13,
        size.height * .42,
        size.width * .17,
        size.height * .25,
      )
      ..close();
    canvas.drawPath(path.shift(Offset(0, size.height * .015)), shadow);
    canvas.drawPath(path, body);
    canvas.drawPath(path, outline);
    canvas.drawLine(
      Offset(size.width * .49, size.height * .07),
      Offset(size.width * .52, size.height * .42),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .53, size.height * .24),
          width: size.width * .09,
          height: size.height * .16,
        ),
        Radius.circular(size.width * .035),
      ),
      detail,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .28, size.height * .49),
        width: size.width * .12,
        height: size.height * .28,
      ),
      outline,
    );
    if (hapticPanel) {
      final panel = Paint()
        ..color = colorScheme.primary.withValues(alpha: .34)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * .17,
            size.height * .57,
            size.width * .16,
            size.height * .20,
          ),
          Radius.circular(size.width * .055),
        ),
        panel,
      );
    }
  }

  void _paintTrackball(
    Canvas canvas,
    Size size,
    Paint shadow,
    Paint body,
    Paint outline,
    Paint detail,
  ) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width * .52, size.height * .56),
        width: size.width * .83,
        height: size.height * .72,
      ),
      Radius.elliptical(size.width * .28, size.height * .25),
    );
    canvas.drawRRect(rect.shift(Offset(0, size.height * .015)), shadow);
    canvas.drawRRect(rect, body);
    canvas.drawRRect(rect, outline);
    canvas.drawCircle(
      Offset(size.width * .29, size.height * .53),
      size.width * .17,
      Paint()..color = colorScheme.primary.withValues(alpha: .68),
    );
    canvas.drawCircle(
      Offset(size.width * .29, size.height * .53),
      size.width * .17,
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .61, size.height * .34),
          width: size.width * .07,
          height: size.height * .14,
        ),
        Radius.circular(size.width * .03),
      ),
      detail,
    );
  }

  void _paintVertical(
    Canvas canvas,
    Size size,
    Paint shadow,
    Paint body,
    Paint outline,
    Paint detail,
  ) {
    final path = Path()
      ..moveTo(size.width * .24, size.height * .84)
      ..cubicTo(
        size.width * .13,
        size.height * .55,
        size.width * .24,
        size.height * .18,
        size.width * .55,
        size.height * .08,
      )
      ..cubicTo(
        size.width * .76,
        size.height * .17,
        size.width * .83,
        size.height * .54,
        size.width * .70,
        size.height * .87,
      )
      ..close();
    canvas.drawPath(path.shift(Offset(0, size.height * .015)), shadow);
    canvas.drawPath(path, body);
    canvas.drawPath(path, outline);
    canvas.drawLine(
      Offset(size.width * .55, size.height * .09),
      Offset(size.width * .50, size.height * .67),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * .56, size.height * .28),
          width: size.width * .07,
          height: size.height * .15,
        ),
        Radius.circular(size.width * .03),
      ),
      detail,
    );
  }

  @override
  bool shouldRepaint(covariant _DevicePainter oldDelegate) =>
      oldDelegate.artworkKey != artworkKey ||
      oldDelegate.colorScheme != colorScheme;
}

double maxOf(double a, double b) => a > b ? a : b;
