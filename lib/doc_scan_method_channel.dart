import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'doc_scan_platform_interface.dart';

/// An implementation of [DocScanPlatform] that uses method channels.
class MethodChannelDocScan extends DocScanPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('doc_scan');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
