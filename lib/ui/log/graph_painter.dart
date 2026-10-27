import 'package:flutter/material.dart';

import '../../git/graph.dart';

const graphLaneWidth = 14.0;
const _graphPadding = 6.0;

double graphWidth(int lanes) => lanes.clamp(1, 40) * graphLaneWidth + _graphPadding * 2;

/// Paints one row of the commit graph.
class GraphPainter extends CustomPainter {
  GraphPainter(this.row, this.palette, {this.isHead = false, required this.background});

  final GraphRow row;
  final List<Color> palette;
  final bool isHead;
  final Color background;

  double _x(int lane) => _graphPadding + lane * graphLaneWidth + graphLaneWidth / 2;

  Color _color(int index) => palette[index % palette.length];

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final mid = h / 2;
    final paint = Paint()
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (final line in row.lines) {
      paint.color = _color(line.color);
      switch (line.part) {
        case GraphPart.full:
          canvas.drawLine(Offset(_x(line.from), 0), Offset(_x(line.to), h), paint);
        case GraphPart.top:
          canvas.drawLine(Offset(_x(line.from), 0), Offset(_x(line.to), mid), paint);
        case GraphPart.bottom:
          canvas.drawLine(Offset(_x(line.from), mid), Offset(_x(line.to), h), paint);
      }
    }

    final center = Offset(_x(row.lane), mid);
    final color = _color(row.color);
    if (isHead) {
      canvas.drawCircle(center, 5, Paint()..color = background);
      canvas.drawCircle(
          center,
          4.5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    } else {
      canvas.drawCircle(center, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(GraphPainter old) =>
      old.row != row || old.isHead != isHead || old.background != background ||
      old.palette != palette;
}
