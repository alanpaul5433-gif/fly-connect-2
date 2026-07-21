import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import 'skeleton.dart';

/// Uniform "loading → error → data" wrapper for any [Future] or
/// [Stream]. Use this in place of hand-rolled
/// `if (snap.hasError) ... else if (!snap.hasData) ... else ...`
/// branches in every screen.
///
/// Why centralise:
///   • Loading state is consistent (skeleton or spinner — your call)
///   • Errors are reported to Crashlytics automatically
///   • Empty-data state is distinguishable from loading state
///   • A retry button is provided for free
///
/// Choose one of the constructors:
/// ```
/// // For a one-shot Future:
/// AsyncBoundary.future(
///   future: () => myRepository.fetch(),
///   builder: (data) => MyDataWidget(data),
/// )
///
/// // For a real-time Stream:
/// AsyncBoundary.stream(
///   stream: myRepository.watch(),
///   builder: (data) => MyDataWidget(data),
/// )
/// ```
class AsyncBoundary<T> extends StatefulWidget {
  /// Returns the Future to await. Wrapped in a function so the retry
  /// button can re-invoke it.
  final Future<T> Function()? futureBuilder;
  final Stream<T>? stream;

  /// Renders the success state with the resolved data.
  final Widget Function(T data) builder;

  /// Renders during loading. Default: a column of 3 skeleton blocks.
  final WidgetBuilder? loadingBuilder;

  /// Renders when [builder]'s data is treated as empty.
  /// Use this for "no results" UX. If null, [builder] is invoked
  /// with whatever data came back.
  final WidgetBuilder? emptyBuilder;

  /// Predicate that determines if [data] should be treated as "empty"
  /// for [emptyBuilder]. E.g. `(list) => list.isEmpty`.
  final bool Function(T data)? isEmpty;

  /// Renders on error. Receives the error and a retry callback.
  /// Default: a centred error card with a Retry button.
  final Widget Function(Object error, VoidCallback retry)? errorBuilder;

  /// If true, errors are forwarded to Firebase Crashlytics (default).
  /// Set false for fire-and-forget streams where errors are expected
  /// to be noisy.
  final bool reportToCrashlytics;

  const AsyncBoundary.future({
    super.key,
    required Future<T> Function() future,
    required this.builder,
    this.loadingBuilder,
    this.emptyBuilder,
    this.isEmpty,
    this.errorBuilder,
    this.reportToCrashlytics = true,
  })  : futureBuilder = future,
        stream = null;

  const AsyncBoundary.stream({
    super.key,
    required this.stream,
    required this.builder,
    this.loadingBuilder,
    this.emptyBuilder,
    this.isEmpty,
    this.errorBuilder,
    this.reportToCrashlytics = true,
  }) : futureBuilder = null;

  @override
  State<AsyncBoundary<T>> createState() => _AsyncBoundaryState<T>();
}

class _AsyncBoundaryState<T> extends State<AsyncBoundary<T>> {
  Future<T>? _future;
  int _retryNonce = 0;

  @override
  void initState() {
    super.initState();
    if (widget.futureBuilder != null) {
      _future = widget.futureBuilder!();
    }
  }

  void _retry() {
    setState(() {
      _retryNonce++;
      if (widget.futureBuilder != null) {
        _future = widget.futureBuilder!();
      }
    });
  }

  Widget _defaultLoading(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Skeleton(width: double.infinity, height: 80, radius: 12),
            SizedBox(height: 12),
            Skeleton(width: double.infinity, height: 80, radius: 12),
            SizedBox(height: 12),
            Skeleton(width: double.infinity, height: 80, radius: 12),
          ],
        ),
      );

  Widget _defaultError(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  color: AppColors.error, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              "Couldn't load",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: AppColors.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reportError(Object error, StackTrace? stack) {
    if (!widget.reportToCrashlytics) return;
    if (kIsWeb) {
      debugPrint('[AsyncBoundary] $error');
      return;
    }
    try {
      FirebaseCrashlytics.instance.recordError(error, stack ?? StackTrace.current);
    } catch (_) {/* silent */}
  }

  Widget _resolve(BuildContext context, AsyncSnapshot<T> snap) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return widget.loadingBuilder?.call(context) ?? _defaultLoading(context);
    }
    if (snap.hasError) {
      _reportError(snap.error!, snap.stackTrace);
      return widget.errorBuilder?.call(snap.error!, _retry) ??
          _defaultError(context, snap.error!);
    }
    if (!snap.hasData) {
      return widget.loadingBuilder?.call(context) ?? _defaultLoading(context);
    }
    final data = snap.data as T;
    if (widget.isEmpty != null &&
        widget.emptyBuilder != null &&
        widget.isEmpty!(data)) {
      return widget.emptyBuilder!(context);
    }
    return widget.builder(data);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.futureBuilder != null) {
      return FutureBuilder<T>(
        key: ValueKey(_retryNonce), // forces rebuild on retry
        future: _future,
        builder: _resolve,
      );
    }
    return StreamBuilder<T>(
      stream: widget.stream,
      builder: _resolve,
    );
  }
}
