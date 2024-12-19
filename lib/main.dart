import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class Vector2D {
  double x, y;

  Vector2D(this.x, this.y);

  Vector2D operator +(Vector2D other) => Vector2D(x + other.x, y + other.y);

  Vector2D operator *(double scalar) => Vector2D(x * scalar, y * scalar);

  double get magnitude => math.sqrt(x * x + y * y);

  Vector2D normalized() {
    double mag = magnitude;
    return mag > 0 ? Vector2D(x / mag, y / mag) : Vector2D(0, 0);
  }
}

class Vector3D {
  double x, y, z;

  Vector3D(this.x, this.y, this.z);

  Vector3D rotateX(double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector3D(x, y * cos - z * sin, y * sin + z * cos);
  }

  Vector3D rotateY(double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector3D(x * cos + z * sin, y, -x * sin + z * cos);
  }

  Vector3D rotateZ(double angle) {
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Vector3D(x * cos - y * sin, x * sin + y * cos, z);
  }

  Vector3D rotate(Vector3D rotation) {
    return rotateX(rotation.x).rotateY(rotation.y).rotateZ(rotation.z);
  }
}

class Asteroid {
  // Position and movement
  Vector2D position;
  Vector2D velocity;
  Vector3D rotation = Vector3D(0, 0, 0);
  Vector3D rotationVelocity;

  // Physical properties
  final double size;
  final double depth;
  Color _color;
  final List<Vector3D> vertices;

  // Visual properties
  final double glowIntensity;
  final double pulseRate;
  double pulsePhase = 0;

  // Caching
  Path? _cachedPath;
  List<Offset>? _cachedVertices;
  Rect? _cachedBounds;
  List<Color>? _cachedColors;
  bool _isDirty = true;

  double _colorChangeTime = 0;
  Color? _targetColor;
  Color? _startColor; // Store the original color
  double _colorTransitionProgress = 1.0;
  static const double colorTransitionDuration = 2; // seconds
  static const double colorChangeIntervalInSeconds = 2; // seconds

  // Use getter and setter for color to manage cache
  Color get color => _color;

  set color(Color newColor) {
    if (_color != newColor) {
      _color = newColor;
      _cachedColors = null; // Invalidate color cache
    }
  }

  Asteroid({
    required this.position,
    required this.velocity,
    required this.rotationVelocity,
    required this.size,
    required this.depth,
    required Color color,
    required this.glowIntensity,
    required this.pulseRate,
  })  : _color = color,
        vertices = _generateVertices(size),
        _colorChangeTime = -math.Random().nextDouble() * 2;

  List<Color> getColors() {
    // Return cached colors if available
    if (_cachedColors != null) return _cachedColors!;

    // Create new colors list
    _cachedColors = List<Color>.filled(3, color);
    return _cachedColors!;
  }

  void invalidateCache() {
    _isDirty = true;
    _cachedPath = null;
    _cachedVertices = null;
    _cachedBounds = null;
    // Don't invalidate _cachedColors here as they're managed separately
  }

  void updateColor(double currentTime) {
    final phase = ((currentTime - _colorChangeTime) * 1 / colorChangeIntervalInSeconds).floor();
    if (phase > 0 && depth >= farDepthThreshold) {
      if (_targetColor == null) {
        // Only start new transition if not already transitioning
        final newColor = backColors[math.Random().nextInt(backColors.length)];
        if (newColor != color) {
          _startColor = color; // Store the starting color
          _targetColor = newColor;
          _colorTransitionProgress = 0.0;
          _colorChangeTime = currentTime;
        }
      }
    }
  }

  static List<Vector3D> _generateVertices(double size) {
    final random = math.Random();

    // Randomly choose a shard type
    final shardType = random.nextInt(4); // 0: acute, 1: obtuse, 2: needle, 3: wide

    final zVariation = size * 0.2;
    late double baseWidth;
    late double height;
    late double baseOffset;

    switch (shardType) {
      case 0: // Acute shard (pointy)
        baseWidth = size * (0.3 + random.nextDouble() * 0.3);
        height = size * (1.2 + random.nextDouble() * 0.4);
        baseOffset = size * (random.nextDouble() - 0.5) * 0.3;
        break;

      case 1: // Obtuse shard (wide angle)
        baseWidth = size * (1.0 + random.nextDouble() * 0.5); // Wider base
        height = size * (0.6 + random.nextDouble() * 0.3); // Shorter height
        baseOffset = size * (random.nextDouble() - 0.5) * 0.5;
        break;

      case 2: // Needle-like
        baseWidth = size * (0.1 + random.nextDouble() * 0.2); // Very narrow
        height = size * (1.5 + random.nextDouble() * 0.5); // Extra tall
        baseOffset = size * (random.nextDouble() - 0.5) * 0.1;
        break;

      case 3: // Wide shard
        baseWidth = size * (0.8 + random.nextDouble() * 0.4);
        height = size * (0.8 + random.nextDouble() * 0.3);
        baseOffset = size * (random.nextDouble() - 0.5) * 0.4;
        break;
    }

    return [
      Vector3D(baseOffset, 0, (random.nextDouble() - 0.5) * zVariation),
      Vector3D(baseOffset + baseWidth, 0, (random.nextDouble() - 0.5) * zVariation),
      Vector3D(
          baseOffset + (baseWidth * (0.3 + random.nextDouble() * 0.4)), // Asymmetric tip position
          -height,
          (random.nextDouble() - 0.5) * zVariation * 1.5),
    ];
  }

  List<Offset> getBaseVertices() {
    // Convert 3D vertices to 2D base positions
    return vertices.map((v) => Offset(v.x, v.y)).toList();
  }

  void update(double deltaTime, Size bounds) {
    invalidateCache();

    position = position + velocity * deltaTime;
    rotation = Vector3D(
      rotation.x + rotationVelocity.x * deltaTime,
      rotation.y + rotationVelocity.y * deltaTime,
      rotation.z + rotationVelocity.z * deltaTime,
    );

    final padding = size * 0.2;
    if (position.x < (0 - padding) || position.x > (bounds.width + padding)) {
      velocity.x = -velocity.x * 0.8;
      position.x = position.x.clamp(0.0 - padding, bounds.width + padding);
    }

    if (position.y < (0 - padding) || position.y > (bounds.height + padding)) {
      velocity.y = -velocity.y * 0.8;
      position.y = position.y.clamp(0.0 - padding, bounds.height + padding);
    }

    pulsePhase += pulseRate * deltaTime;

    // Update color transition
    if (_targetColor != null && _startColor != null) {
      _colorTransitionProgress += deltaTime / colorTransitionDuration;
      if (_colorTransitionProgress >= 1.0) {
        color = _targetColor!;
        _targetColor = null;
        _startColor = null;
        _colorTransitionProgress = 1.0;
      } else {
        color = Color.lerp(_startColor!, _targetColor!, _colorTransitionProgress)!;
      }
    }
  }

  List<Offset> getProjectedVertices({double gyroOffsetX = 0}) {
    if (!_isDirty && _cachedVertices != null) return _cachedVertices!;

    final horizontalOffset = gyroOffsetX * math.pow(1.1 - depth, 3);

    _cachedVertices = vertices.map((vertex) {
      final rotated = vertex.rotate(rotation);
      final scale = 1 + (rotated.z / 200);
      return Offset(
        position.x + rotated.x * scale + horizontalOffset,
        position.y + rotated.y * scale,
      );
    }).toList();

    return _cachedVertices!;
  }

  Path getPath({double gyroOffsetX = 0}) {
    if (!_isDirty && _cachedPath != null) return _cachedPath!;

    final vertices = getProjectedVertices(gyroOffsetX: gyroOffsetX);
    _cachedPath = Path()..moveTo(vertices[0].dx, vertices[0].dy);

    for (int i = 1; i < vertices.length; i++) {
      _cachedPath!.lineTo(vertices[i].dx, vertices[i].dy);
    }
    _cachedPath!.close();

    _isDirty = false;
    return _cachedPath!;
  }

  Rect getBounds({double gyroOffsetX = 0}) {
    if (!_isDirty && _cachedBounds != null) return _cachedBounds!;

    final vertices = getProjectedVertices(gyroOffsetX: gyroOffsetX);
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final vertex in vertices) {
      minX = math.min(minX, vertex.dx);
      minY = math.min(minY, vertex.dy);
      maxX = math.max(maxX, vertex.dx);
      maxY = math.max(maxY, vertex.dy);
    }

    _cachedBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    return _cachedBounds!;
  }
}

// Color definitions
final List<Color> colors = [
  const Color(0xFFFFFAF0), // Antique white
  const Color(0xFFFFFDD0), // Cream
  const Color(0xFFFFFACD), // Lemon chiffon
  const Color(0xFFF0F8FF), // Alice blue
  const Color(0xFFF0FFFF), // Azure
  const Color(0xFFE6E6FA), // Lavender
  const Color(0xFFFFFAF0), // Floral white
  const Color(0xFFFFE4E1), // Misty rose
  const Color(0xFFF5F5F5), // White smoke
  const Color(0xFFFDF5E6), // Old lace
  const Color(0xFFFFFFF0), // Ivory
];

final List<Color> backColors = [
  Colors.red,
  Colors.green,
  Colors.blue,
  Colors.yellow,
  Colors.purple,
  Colors.orange,
  Colors.pink,
  Colors.teal,
  Colors.cyan,
  Colors.lime,
  Colors.indigo,
  Colors.amber,
  Colors.brown,
  Colors.grey,
  Colors.lightBlue,
  Colors.lightGreen,
  Colors.deepOrange,
];
const double farDepthThreshold = 0.45;

// Cached vertex data structure
class VertexCache {
  final List<Offset> positions;
  final List<int> indices;
  final List<Color> colors;

  VertexCache({
    required this.positions,
    required this.indices,
    required this.colors,
  });
}

// Viewport for frustum culling
class Viewport {
  final Rect bounds;

  Viewport({
    required this.bounds,
  });

  bool isVisible(Rect objectBounds) {
    // Simple 2D bounds intersection check
    return bounds.overlaps(objectBounds);
  }
}

class AsteroidField extends StatefulWidget {
  final int asteroidCount;
  final double maxDepth;

  const AsteroidField({
    super.key,
    this.asteroidCount = 20,
    required this.maxDepth,
  });

  @override
  AsteroidFieldState createState() => AsteroidFieldState();
}

class AsteroidFieldState extends State<AsteroidField> with SingleTickerProviderStateMixin {
  List<Asteroid> asteroidsNotifier = [];
  final Map<int, VertexCache> vertexCache = {};
  late final AnimationController _controller;
  double lastUpdateTime = 0;
  final random = math.Random();

  double cameraX = 0;
  double cameraY = 0;
  static const double cameraSensitivity = 30.0;
  static const double cameraInertia = 0.95;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_updateAsteroids);
    _controller.repeat();
    lastUpdateTime = DateTime.now().millisecondsSinceEpoch / 1000;

    gyroscopeEventStream().listen((GyroscopeEvent event) {
      if (mounted) {
        setState(() {
          cameraX = (cameraX * cameraInertia) - (event.y * cameraSensitivity);
          cameraY = (cameraY * cameraInertia) + (event.x * cameraSensitivity);
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initAsteroids();
  }

  void _initAsteroids() {
    final asteroids = <Asteroid>[];
    final size = MediaQuery.of(context).size;
    final spawnArea = Rect.fromLTWH(-size.width * 0.5, -size.height * 0.5, size.width * 2, size.height * 2);

    for (int i = 0; i < widget.asteroidCount; i++) {
      asteroids.add(_createAsteroid(spawnArea));
    }
    asteroidsNotifier = asteroids;
    _initializeVertexCache(asteroids);
  }

  void _initializeVertexCache(List<Asteroid> asteroids) {
    vertexCache.clear();
    for (var asteroid in asteroids) {
      _cacheAsteroidVertices(asteroid);
    }
  }

  void _cacheAsteroidVertices(Asteroid asteroid) {
    final basePositions = asteroid.getBaseVertices();
    final indices = List<int>.generate(3, (i) => i);
    final colors = List<Color>.filled(3, asteroid.color);

    vertexCache[asteroid.hashCode] = VertexCache(
      positions: basePositions,
      indices: indices,
      colors: colors,
    );
  }

  Asteroid _createAsteroid(Rect spawnArea) {
    final depth = (0.1 + random.nextDouble() * 0.9).clamp(0, widget.maxDepth).toDouble();
    final baseSize = 10 + random.nextDouble() * 5;

    return Asteroid(
      position: Vector2D(
        spawnArea.left + random.nextDouble() * spawnArea.width,
        spawnArea.top + random.nextDouble() * spawnArea.height,
      ),
      velocity: Vector2D(
        (random.nextDouble() - 0.5) * 20,
        (random.nextDouble() - 0.5) * 20,
      ),
      rotationVelocity: Vector3D(
        (random.nextDouble() - 0.5) * random.nextDouble() * 5,
        (random.nextDouble() - 0.5) * random.nextDouble() * 5,
        (random.nextDouble() - 0.5) * random.nextDouble() * 2,
      ),
      size: baseSize * (1.2 - depth * 0.7),
      depth: depth,
      color: depth < farDepthThreshold
          ? colors[random.nextInt(colors.length)]
          : backColors[random.nextInt(backColors.length)],
      glowIntensity: 0.6 + random.nextDouble() * 0.4,
      pulseRate: 0.5 + random.nextDouble() * 2,
    );
  }

  void _updateAsteroids() {
    if (!mounted) return;

    final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
    final deltaTime = currentTime - lastUpdateTime;
    lastUpdateTime = currentTime;

    final size = MediaQuery.of(context).size;

    final asteroids = asteroidsNotifier;
    for (var asteroid in asteroids) {
      asteroid.update(deltaTime, size);
      asteroid.updateColor(currentTime);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    vertexCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final viewport = Viewport(
      bounds: Rect.fromLTWH(
        -size.width * 0.1,
        -size.height * 0.1,
        size.width * 1.2,
        size.height * 1.2,
      ),
    );

    return RepaintBoundary(
      child: CustomPaint(
        painter: AsteroidPainter(
          asteroids: asteroidsNotifier,
          vertexCache: vertexCache,
          viewport: viewport,
          canvasSize: size,
          cameraX: cameraX,
          cameraY: cameraY,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class AsteroidPainter extends CustomPainter {
  final List<Asteroid> asteroids;
  final Map<int, VertexCache> vertexCache;
  final Viewport viewport;
  final Size canvasSize;
  final double cameraX;
  final double cameraY;

  AsteroidPainter({
    required this.asteroids,
    required this.vertexCache,
    required this.viewport,
    required this.canvasSize,
    required this.cameraX,
    required this.cameraY,
  });

  List<Offset> transformVertices(List<Offset> baseVertices, Asteroid asteroid) {
    final parallaxStrength = math.pow(1 - asteroid.depth, 2).toDouble();
    final cameraOffset = Offset(
      cameraX * parallaxStrength,
      cameraY * parallaxStrength,
    );

    return baseVertices.map((vertex) {
      // Apply rotation
      final rotated = Vector3D(
        vertex.dx,
        vertex.dy,
        0,
      ).rotate(asteroid.rotation);

      // Apply position, scale and camera offset
      return Offset(
        asteroid.position.x + rotated.x + cameraOffset.dx,
        asteroid.position.y + rotated.y + cameraOffset.dy,
      );
    }).toList();
  }

  Offset applyCamera(Offset position, double depth) {
    final parallaxStrength = math.pow(1 - depth, 2).toDouble();
    return Offset(position.dx + (cameraX * parallaxStrength), position.dy + (cameraY * parallaxStrength));
  }

  bool isAsteroidVisible(Asteroid asteroid) {
    final visibleBounds = Rect.fromLTWH(
      -asteroid.size * 2,
      -asteroid.size * 2,
      canvasSize.width + asteroid.size * 4,
      canvasSize.height + asteroid.size * 4,
    );

    final asteroidBounds = asteroid.getBounds();
    final transformedBounds = Rect.fromPoints(
      applyCamera(asteroidBounds.topLeft, asteroid.depth),
      applyCamera(asteroidBounds.bottomRight, asteroid.depth),
    );

    return visibleBounds.overlaps(transformedBounds);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    final sortedAsteroids = [...asteroids]..sort((a, b) => b.depth.compareTo(a.depth));

    // Group asteroids by color for batching
    final batchedVertices = <Color, List<Offset>>{};
    final batchedIndices = <Color, List<int>>{};
    final batchedColors = <Color, List<Color>>{};

    for (var asteroid in sortedAsteroids) {
      if (!isAsteroidVisible(asteroid) || asteroid.depth > 0.95) continue;

      final transformedVertices = asteroid.getProjectedVertices().map((v) => applyCamera(v, asteroid.depth)).toList();

      final currentColor = asteroid.color;

      // Add to batch
      batchedVertices.putIfAbsent(currentColor, () => []).addAll(transformedVertices);

      final indexOffset = (batchedVertices[currentColor]!.length - transformedVertices.length) ~/ 3 * 3;
      batchedIndices.putIfAbsent(currentColor, () => []).addAll(
            List<int>.generate(3, (i) => i + indexOffset),
          );

      batchedColors.putIfAbsent(currentColor, () => []).addAll(asteroid.getColors());
    }

    // Draw batched vertices
    batchedVertices.forEach((color, vertices) {
      if (vertices.isEmpty) return;

      final verticesObject = Vertices(
        VertexMode.triangles,
        vertices,
        indices: batchedIndices[color],
        colors: batchedColors[color],
      );

      canvas.drawVertices(
        verticesObject,
        BlendMode.srcOver,
        Paint(),
      );
    });

    canvas.restore();
  }

  @override
  bool shouldRepaint(AsteroidPainter oldDelegate) {
    return true;
  }
}

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
              child: const AsteroidField(
                asteroidCount: 90,
                maxDepth: farDepthThreshold,
              ),
            ),
            const AsteroidField(
              asteroidCount: 40,
              maxDepth: 0,
            )
          ],
        ),
      ),
    ),
  ));
}
