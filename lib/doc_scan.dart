
import 'doc_scan_platform_interface.dart';

class DocScan {
  Future<String?> getPlatformVersion() {
    return DocScanPlatform.instance.getPlatformVersion();
  }
}
