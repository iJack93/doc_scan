import 'package:flutter_test/flutter_test.dart';
import 'package:doc_scan/doc_scan.dart';
import 'package:doc_scan/doc_scan_platform_interface.dart';
import 'package:doc_scan/doc_scan_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDocScanPlatform
    with MockPlatformInterfaceMixin
    implements DocScanPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DocScanPlatform initialPlatform = DocScanPlatform.instance;

  test('$MethodChannelDocScan is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDocScan>());
  });

  test('getPlatformVersion', () async {
    DocScan docScanPlugin = DocScan();
    MockDocScanPlatform fakePlatform = MockDocScanPlatform();
    DocScanPlatform.instance = fakePlatform;

    expect(await docScanPlugin.getPlatformVersion(), '42');
  });
}
