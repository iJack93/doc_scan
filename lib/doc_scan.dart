import 'dart:async';
import 'package:flutter/services.dart';

/// Represents the format in which the document will be scanned.
enum DocScanFormat {
  /// Scans the document and saves it as a PDF file.
  pdf,

  /// Scans the document and saves it as a JPEG file.
  jpeg,
}

/// The main class for scanning documents.
class DocScan {
  static const MethodChannel _channel = MethodChannel('doc_scan');

  /// Scans a document and returns the file path(s) of the scanned document(s).
  ///
  /// Throws a [DocScanException] if the scan fails.
  static Future<List<String>?> scan({
    DocScanFormat format = DocScanFormat.jpeg,
  }) async {
    try {
      final result = await _channel.invokeMethod('scanDocument', {
        'format': format == DocScanFormat.pdf ? 'pdf' : 'jpeg',
      });

      if (result == null || result is! List) {
        throw DocScanException(
          'Invalid response from native code, expected a List, got $result',
        );
      }

      return result.cast<String>();
    } on PlatformException catch (e) {
      throw DocScanException(e.message ?? 'Unknown error');
    }
  }
}

/// Exception thrown when the document scanning fails.
class DocScanException implements Exception {
  /// Creates a [DocScanException] with the given message.
  DocScanException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'DocScanException: $message';
}
