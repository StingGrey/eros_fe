import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

class TabScrollPositionStore {
  TabScrollPositionStore._();

  static final TabScrollPositionStore instance = TabScrollPositionStore._();
  static const double _lowerOffsetTolerance = 24;
  static const Duration _defaultProtectionDuration =
      Duration(milliseconds: 3200);
  static const List<Duration> _restoreDelays = [
    Duration(milliseconds: 80),
    Duration(milliseconds: 180),
    Duration(milliseconds: 350),
    Duration(milliseconds: 700),
    Duration(milliseconds: 1100),
    Duration(milliseconds: 1700),
    Duration(milliseconds: 2500),
  ];

  final Map<String, double> _offsets = {};
  final Map<String, VoidCallback> _restorers = {};
  final Map<String, double? Function()> _offsetReaders = {};

  int _recordingPauseCount = 0;
  int _restorePassGeneration = 0;
  DateTime? _lowerOffsetProtectionExpiresAt;

  bool get canRecord => _recordingPauseCount == 0;

  bool get isProtectingLowerOffsets {
    final expiresAt = _lowerOffsetProtectionExpiresAt;
    return expiresAt != null && DateTime.now().isBefore(expiresAt);
  }

  double? offsetFor(String key) => _offsets[key];

  void saveOffset(String key, double offset, {bool userScroll = false}) {
    if (!canRecord || !offset.isFinite) {
      return;
    }
    final normalized = _normalizeOffset(offset);
    if (!userScroll && _shouldKeepCurrentOffset(key, normalized)) {
      return;
    }
    _saveOffset(key, normalized);
  }

  void registerRestorer(String key, VoidCallback callback) {
    _restorers[key] = callback;
  }

  void registerOffsetReader(String key, double? Function() callback) {
    _offsetReaders[key] = callback;
  }

  void unregisterRestorer(String key, VoidCallback callback) {
    if (_restorers[key] == callback) {
      _restorers.remove(key);
    }
  }

  void unregisterOffsetReader(String key, double? Function() callback) {
    if (_offsetReaders[key] == callback) {
      _offsetReaders.remove(key);
    }
  }

  void pauseRecording() {
    snapshotRegisteredOffsets();
    _recordingPauseCount += 1;
  }

  void _resumeRecording() {
    if (_recordingPauseCount > 0) {
      _recordingPauseCount -= 1;
    }
  }

  void restoreRegistered() {
    final restorers = List<VoidCallback>.from(_restorers.values);
    for (final restorer in restorers) {
      restorer();
    }
  }

  void handleUserScroll() {
    _restorePassGeneration += 1;
    _lowerOffsetProtectionExpiresAt = null;
    _recordingPauseCount = 0;
  }

  void restoreAfterRoutePop() {
    _protectLowerOffsetsFor(_defaultProtectionDuration);
    snapshotRegisteredOffsets(keepLargerOffsets: true);
    _scheduleRestorePasses();
  }

  void snapshotRegisteredOffsets({bool keepLargerOffsets = false}) {
    final readers = Map<String, double? Function()>.from(_offsetReaders);
    for (final entry in readers.entries) {
      final offset = entry.value();
      if (offset != null && offset.isFinite) {
        final normalized = _normalizeOffset(offset);
        if (keepLargerOffsets &&
            _shouldKeepCurrentOffset(entry.key, normalized)) {
          continue;
        }
        _saveOffset(entry.key, normalized);
      }
    }
  }

  void _saveOffset(String key, double offset) {
    _offsets[key] = _normalizeOffset(offset);
  }

  double _normalizeOffset(double offset) => offset < 0 ? 0 : offset;

  bool _shouldKeepCurrentOffset(String key, double newOffset) {
    if (!isProtectingLowerOffsets) {
      return false;
    }
    final current = _offsets[key];
    return current != null && newOffset + _lowerOffsetTolerance < current;
  }

  void _protectLowerOffsetsFor(Duration duration) {
    final nextExpiresAt = DateTime.now().add(duration);
    final currentExpiresAt = _lowerOffsetProtectionExpiresAt;
    if (currentExpiresAt == null || nextExpiresAt.isAfter(currentExpiresAt)) {
      _lowerOffsetProtectionExpiresAt = nextExpiresAt;
    }
  }

  void _scheduleRestorePasses() {
    final generation = ++_restorePassGeneration;
    _restoreRegisteredForGeneration(generation);
    for (final delay in _restoreDelays) {
      Future<void>.delayed(
        delay,
        () => _restoreRegisteredForGeneration(generation),
      );
    }
  }

  void _restoreRegisteredForGeneration(int generation) {
    if (generation == _restorePassGeneration) {
      restoreRegistered();
    }
  }

  Future<T?> preserveDuring<T>(Future<T?>? Function() action) async {
    pauseRecording();
    try {
      final future = action();
      if (future == null) {
        return null;
      }
      return await future;
    } finally {
      restoreAfterRoutePop();
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        _resumeRecording();
      });
    }
  }
}

class TabScrollPositionKeeper extends StatefulWidget {
  const TabScrollPositionKeeper({
    super.key,
    required this.storageKey,
    required this.child,
  });

  final String storageKey;
  final Widget child;

  @override
  State<TabScrollPositionKeeper> createState() =>
      _TabScrollPositionKeeperState();
}

class _TabScrollPositionKeeperState extends State<TabScrollPositionKeeper> {
  TabScrollPositionStore get _store => TabScrollPositionStore.instance;

  late final VoidCallback _restorer;
  late final double? Function() _offsetReader;
  ScrollPosition? _position;
  bool _restoring = false;
  bool _userScrollActive = false;
  int _restoreGeneration = 0;
  int _userScrollGeneration = 0;

  @override
  void initState() {
    super.initState();
    _restorer = _restore;
    _offsetReader = _currentOffset;
    _store.registerRestorer(widget.storageKey, _restorer);
    _store.registerOffsetReader(widget.storageKey, _offsetReader);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void didUpdateWidget(TabScrollPositionKeeper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageKey != widget.storageKey) {
      _store.unregisterRestorer(oldWidget.storageKey, _restorer);
      _store.unregisterOffsetReader(oldWidget.storageKey, _offsetReader);
      _restoreGeneration += 1;
      _store.registerRestorer(widget.storageKey, _restorer);
      _store.registerOffsetReader(widget.storageKey, _offsetReader);
      WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
    }
  }

  @override
  void dispose() {
    _restoreGeneration += 1;
    _store.unregisterRestorer(widget.storageKey, _restorer);
    _store.unregisterOffsetReader(widget.storageKey, _offsetReader);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.child,
      ),
    );
  }

  bool _onScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _updatePosition(notification.context);
      _restore();
    }
    return false;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    _updatePosition(notification.context);
    _updateUserScrollState(notification);

    if (_restoring || !_store.canRecord || !_shouldRecord(notification)) {
      return false;
    }

    _store.saveOffset(
      widget.storageKey,
      notification.metrics.pixels,
      userScroll: _userScrollActive,
    );
    return false;
  }

  void _updatePosition(BuildContext? notificationContext) {
    if (notificationContext != null) {
      _position = Scrollable.maybeOf(notificationContext)?.position;
    }
  }

  double? _currentOffset() {
    final position = _scrollPosition;
    if (position == null || !position.hasPixels) {
      return null;
    }
    return position.pixels;
  }

  void _restore() {
    if (!mounted || _userScrollActive) {
      return;
    }

    final offset = _store.offsetFor(widget.storageKey);
    if (offset == null || offset <= 0) {
      return;
    }

    final generation = ++_restoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreWithRetry(offset, 0, generation);
    });
  }

  void _restoreWithRetry(double offset, int attempt, int generation) {
    if (!mounted || _userScrollActive || generation != _restoreGeneration) {
      return;
    }

    final position = _scrollPosition;
    if (position == null) {
      if (attempt < 8) {
        Future<void>.delayed(
          const Duration(milliseconds: 80),
          () => _restoreWithRetry(offset, attempt + 1, generation),
        );
      }
      return;
    }

    if (!position.hasContentDimensions && attempt < 8) {
      Future<void>.delayed(
        const Duration(milliseconds: 80),
        () => _restoreWithRetry(offset, attempt + 1, generation),
      );
      return;
    }

    if (position.maxScrollExtent <= 0 && offset > 0 && attempt < 8) {
      Future<void>.delayed(
        const Duration(milliseconds: 80),
        () => _restoreWithRetry(offset, attempt + 1, generation),
      );
      return;
    }

    _restoring = true;
    try {
      final target = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.jumpTo(target);
    } catch (_) {
      if (_position == position) {
        _position = null;
      }
      if (attempt < 8) {
        Future<void>.delayed(
          const Duration(milliseconds: 80),
          () => _restoreWithRetry(offset, attempt + 1, generation),
        );
      }
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted) {
          _restoring = false;
        }
      });
    }
  }

  bool _shouldRecord(ScrollNotification notification) {
    return notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is UserScrollNotification ||
        (notification is ScrollEndNotification && _userScrollActive);
  }

  void _updateUserScrollState(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _markUserScrollActive();
      return;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _markUserScrollActive();
      return;
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _markUserScrollActive();
      return;
    }

    if (notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle)) {
      _releaseUserScrollSoon();
    }
  }

  void _markUserScrollActive() {
    _userScrollActive = true;
    _userScrollGeneration += 1;
    _store.handleUserScroll();
  }

  void _releaseUserScrollSoon() {
    final generation = ++_userScrollGeneration;
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && generation == _userScrollGeneration) {
        _userScrollActive = false;
      }
    });
  }

  ScrollPosition? get _scrollPosition {
    if (_position != null &&
        _position!.hasPixels &&
        (_position!.context.notificationContext?.mounted ?? true)) {
      return _position;
    }

    _position = null;

    final controller = PrimaryScrollController.maybeOf(context);
    if (controller != null && controller.hasClients) {
      return controller.positions.last;
    }

    return null;
  }
}
