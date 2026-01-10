import 'dart:math';
import 'dart:ui';

class RecognitionResult {
  final String name;
  final double score;
  RecognitionResult(this.name, this.score);
}

class Point {
  final double x;
  final double y;
  Point(this.x, this.y);
}

class OneDollarRecognizer {
  static const int numPoints = 64;
  static const double squareSize = 250.0;
  static const double diagonal = 353.55; // sqrt(250^2 + 250^2)
  static const double halfDiagonal = 176.775;
  static const double angleRange = 45.0;
  static const double anglePrecision = 2.0;
  static const double phi = 0.618033988749895; // Golden Ratio

  // Pre-defined templates
  final List<_Template> _templates = [];

  OneDollarRecognizer() {
    // Add templates here. 
    // Points are simplified coordinates. (0,0) top-left.
    
    // UP: Line up
    _addTemplate('UP', [Point(0, 100), Point(0, 0)]);
    // DOWN: Line down
    _addTemplate('DOWN', [Point(0, 0), Point(0, 100)]);
    
    // L: Down then Right
    _addTemplate('L', [Point(0, 0), Point(0, 100), Point(50, 100)]);
    
    // R: Vertical line, then loop, then leg
    _addTemplate('R', [
      Point(0, 100), Point(0, 0), Point(50, 0), 
      Point(50, 50), Point(0, 50), Point(50, 100)
    ]);

    // P: Vertical line, then loop
    _addTemplate('P', [
      Point(0, 100), Point(0, 0), Point(50, 0), 
      Point(50, 50), Point(0, 50)
    ]);

    // C: C shape (right to left arc)
    _addTemplate('C', [
       Point(100, 0), Point(0, 50), Point(100, 100)
    ]);
    
    // S: S shape
    _addTemplate('S', [
      Point(100, 0), Point(0, 30), Point(100, 70), Point(0, 100)
    ]);

    // M: Up, Down-Right, Up-Right, Down
    _addTemplate('M', [
       Point(0, 100), Point(0, 0), Point(50, 50), Point(100, 0), Point(100, 100)
    ]);

    // H: Two verticals and a bar
    _addTemplate('H', [
      Point(0, 0), Point(0, 100), Point(0, 50), Point(100, 50), Point(100, 0), Point(100, 100)
    ]);
    
    // K: Down, Up-Mid, Up-Right, Back-Mid, Down-Right
    _addTemplate('K', [
       Point(0, 0), Point(0, 100), Point(0, 50), Point(50, 0), Point(0, 50), Point(50, 100)
    ]);
  }

  void _addTemplate(String name, List<Point> points) {
    _templates.add(_Template(name, _resample(points, numPoints)));
  }

  RecognitionResult? recognize(List<Offset> stroke) {
    if (stroke.isEmpty) return null;

    List<Point> points = stroke.map((o) => Point(o.dx, o.dy)).toList();
    points = _resample(points, numPoints);
    points = _rotateToZero(points);
    points = _scaleToSquare(points, squareSize);
    points = _translateToOrigin(points);
    
    double bestDistance = double.infinity;
    String bestTemplate = '';
    
    for (final template in _templates) {
      final distance = _distanceAtBestAngle(points, template, -angleRange, angleRange, anglePrecision);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestTemplate = template.name;
      }
    }
    
    double score = 1.0 - (bestDistance / halfDiagonal);
    return RecognitionResult(bestTemplate, score);
  }

  // --- Static Helpers to avoid recursion during Template instantiation ---

  static List<Point> _resample(List<Point> points, int n) {
    double I = _pathLength(points) / (n - 1);
    double D = 0.0;
    List<Point> newPoints = [points[0]];
    
    for (int i = 1; i < points.length; i++) {
        double d = _distance(points[i - 1], points[i]);
        if (D + d >= I) {
            double qx = points[i - 1].x + ((I - D) / d) * (points[i].x - points[i - 1].x);
            double qy = points[i - 1].y + ((I - D) / d) * (points[i].y - points[i - 1].y);
            Point q = Point(qx, qy);
            newPoints.add(q);
            points.insert(i, q);
            D = 0.0;
        } else {
            D += d;
        }
    }
    
    if (newPoints.length == n - 1) {
        newPoints.add(points.last);
    }
    return newPoints;
  }

  static List<Point> _rotateToZero(List<Point> points) {
    Point c = _centroid(points);
    double theta = atan2(c.y - points[0].y, c.x - points[0].x);
    return _rotateBy(points, -theta);
  }

  static List<Point> _rotateBy(List<Point> points, double radians) {
    Point c = _centroid(points);
    double cosT = cos(radians);
    double sinT = sin(radians);
    
    List<Point> newPoints = [];
    for (final p in points) {
       double qx = (p.x - c.x) * cosT - (p.y - c.y) * sinT + c.x;
       double qy = (p.x - c.x) * sinT + (p.y - c.y) * cosT + c.y;
       newPoints.add(Point(qx, qy));
    }
    return newPoints;
  }

  static List<Point> _scaleToSquare(List<Point> points, double size) {
    _Box b = _boundingBox(points);
    List<Point> newPoints = [];
    for (final p in points) {
        double qx = p.x * (size / b.width);
        double qy = p.y * (size / b.height);
        newPoints.add(Point(qx, qy));
    }
    return newPoints;
  }

  static List<Point> _translateToOrigin(List<Point> points) {
    Point c = _centroid(points);
    List<Point> newPoints = [];
    for (final p in points) {
        newPoints.add(Point(p.x - c.x, p.y - c.y));
    }
    return newPoints;
  }

  static double _distanceAtBestAngle(List<Point> points, _Template T, double fromAngle, double toAngle, double threshold) {
    double x1 = phi * fromAngle + (1.0 - phi) * toAngle;
    double f1 = _distanceAtAngle(points, T, x1);
    double x2 = (1.0 - phi) * fromAngle + phi * toAngle;
    double f2 = _distanceAtAngle(points, T, x2);
    
    while ((toAngle - fromAngle).abs() > threshold * (pi / 180.0)) {
        if (f1 < f2) {
            toAngle = x2;
            x2 = x1;
            f2 = f1;
            x1 = phi * fromAngle + (1.0 - phi) * toAngle;
            f1 = _distanceAtAngle(points, T, x1);
        } else {
            fromAngle = x1;
            x1 = x2;
            f1 = f2;
            x2 = (1.0 - phi) * fromAngle + phi * toAngle;
            f2 = _distanceAtAngle(points, T, x2);
        }
    }
    return min(f1, f2);
  }

  static double _distanceAtAngle(List<Point> points, _Template T, double radians) {
     List<Point> newPoints = _rotateBy(points, radians);
     return _pathDistance(newPoints, T.points);
  }
  
  static double _pathDistance(List<Point> pts1, List<Point> pts2) {
      double d = 0.0;
      for (int i = 0; i < pts1.length && i < pts2.length; i++) {
          d += _distance(pts1[i], pts2[i]);
      }
      return d / pts1.length;
  }

  static double _pathLength(List<Point> points) {
    double d = 0.0;
    for (int i = 1; i < points.length; i++) {
        d += _distance(points[i - 1], points[i]);
    }
    return d;
  }

  static double _distance(Point p1, Point p2) {
    double dx = p1.x - p2.x;
    double dy = p1.y - p2.y;
    return sqrt(dx * dx + dy * dy);
  }

  static Point _centroid(List<Point> points) {
    double x = 0.0, y = 0.0;
    for (final p in points) {
        x += p.x;
        y += p.y;
    }
    return Point(x / points.length, y / points.length);
  }

  static _Box _boundingBox(List<Point> points) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    
    for (final p in points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
    }
    return _Box(maxX - minX, maxY - minY);
  }
}

class _Template {
    final String name;
    final List<Point> points;
    
    _Template(String name, List<Point> points) : 
        name = name, 
        points = _normalize(points);

    static List<Point> _normalize(List<Point> points) {
        return OneDollarRecognizer._translateToOrigin(
            OneDollarRecognizer._scaleToSquare(
                OneDollarRecognizer._rotateToZero(
                    OneDollarRecognizer._resample(points, OneDollarRecognizer.numPoints)
                ), 
                OneDollarRecognizer.squareSize
            )
        );
    }
}

class _Box {
    final double width;
    final double height;
    _Box(this.width, this.height);
}

OneDollarRecognizer buildDefaultRecognizer() {
  return OneDollarRecognizer();
}
