import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native TextureView playback for live RTSP; independent of the VOD controller.
class NativeCameraView extends StatefulWidget {
  const NativeCameraView({
    super.key,
    required this.uri,
    required this.onStatus,
  });
  final Uri uri;
  final ValueChanged<String> onStatus;
  @override
  State<NativeCameraView> createState() => _NativeCameraViewState();
}

class _NativeCameraViewState extends State<NativeCameraView> {
  MethodChannel? _channel;
  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AndroidView(
    viewType: 'anju/rtsp-view',
    layoutDirection: TextDirection.ltr,
    creationParams: {'url': widget.uri.toString()},
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: (id) {
      _channel = MethodChannel('anju/rtsp/$id')
        ..setMethodCallHandler((call) async {
          if (mounted && call.method == 'status')
            widget.onStatus('${call.arguments}');
        });
    },
  );
}
