import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Monchi intro (assets/intro/monchi_intro.mp4, 5 s, no sound) over the app
/// on every launch. The app is built underneath, so it is ready when the
/// video fades out. A tap skips it; any error or a stall just shows the app.
/// Android only (widget tests run without the plugin) and never with
/// "remove animations" on.
class IntroVideo extends StatefulWidget {
  const IntroVideo({super.key, required this.child});

  final Widget child;

  @override
  State<IntroVideo> createState() => _IntroVideoState();
}

class _IntroVideoState extends State<IntroVideo> {
  VideoPlayerController? _controller;
  Timer? _safety;
  bool _done = !Platform.isAndroid;
  bool _gone = !Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_done) return;
    final c = VideoPlayerController.asset(
      'assets/intro/monchi_intro.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller = c;
    c.addListener(_onTick);
    c.initialize().then((_) {
      if (!mounted || _done) return;
      setState(() {});
      c.play();
    }, onError: (Object _) => _finish());
    // Never keep people waiting if the video stalls.
    _safety = Timer(const Duration(seconds: 8), _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _finish();
  }

  void _onTick() {
    final v = _controller?.value;
    if (v == null) return;
    if (v.hasError || (v.isInitialized && v.duration > Duration.zero && v.position >= v.duration)) _finish();
  }

  void _finish() {
    if (_done || !mounted) return;
    _safety?.cancel();
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _safety?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    // Same Stack shape before and after, so the app below keeps its state.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_gone)
          const SizedBox.shrink()
        else
          IgnorePointer(
            ignoring: _done,
            child: AnimatedOpacity(
              opacity: _done ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              onEnd: () {
                if (!_done || !mounted) return;
                setState(() => _gone = true);
                c?.dispose();
                _controller = null;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _finish,
                child: ColoredBox(
                  color: const Color(0xFF131B2E), // same as the native splash
                  child: c != null && c.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: c.value.size.width,
                            height: c.value.size.height,
                            child: VideoPlayer(c),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
