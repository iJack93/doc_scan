import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'doc_scan_method_channel.dart';

abstract class DocScanPlatform extends PlatformInterface {
  /// Constructs a DocScanPlatform.
  DocScanPlatform() : super(token: _token);

  static final Object _token = Object();

  static DocScanPlatform _instance = MethodChannelDocScan();

  /// The default instance of [DocScanPlatform] to use.
  ///
  /// Defaults to [MethodChannelDocScan].
  static DocScanPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DocScanPlatform] when
  /// they register themselves.
  static set instance(DocScanPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
