import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// /// Rappresenta il formato in cui il documento verrà salvato.
// enum DocScanFormat {
//   /// Salva il documento scansionato come file PDF.
//   pdf,
//
//   /// Salva il documento scansionato come file JPEG.
//   jpeg,
// }

/// La classe principale per la scansione di documenti.
// class DocumentScanner {
//   static const MethodChannel _channel = MethodChannel('doc_scan');
//
//   /// Scansiona un documento utilizzando la fotocamera del dispositivo.
//   ///
//   /// Restituisce un elenco di percorsi dei file scansionati.
//   /// Solleva una [DocumentScannerException] se la scansione fallisce o viene annullata.
//   static Future<List<String>> scanFromCamera({
//     DocScanFormat format = DocScanFormat.jpeg,
//   }) async {
//     try {
//       final result = await _channel.invokeMethod('scanFromCamera', {
//         'format': format.name,
//       });
//
//       // Se il risultato è nullo, significa che l'utente ha annullato l'operazione.
//       // Restituisce una lista vuota per coerenza.
//       if (result == null) {
//         return [];
//       }
//
//       if (result is! List) {
//         throw DocumentScannerException(
//           'Risposta non valida dal codice nativo, attesa una Lista, ricevuto ${result.runtimeType}',
//         );
//       }
//
//       return result.cast<String>();
//     } on PlatformException catch (e) {
//       // Gestisce l'errore specifico per la galleria non disponibile su iOS < 14
//       if (e.code == 'UNAVAILABLE') {
//         throw DocumentScannerException(
//           'Funzionalità non disponibile: ${e.message}',
//         );
//       }
//       throw DocumentScannerException(e.message ?? 'Errore sconosciuto');
//     }
//   }
//
//   /// Importa un'immagine dalla galleria del dispositivo.
//   ///
//   /// Restituisce un elenco di percorsi dei file importati.
//   /// Solleva una [DocumentScannerException] se l'importazione fallisce o viene annullata.
//   /// **Nota:** Su iOS, questa funzione è disponibile solo da iOS 14 in poi.
//   static Future<List<String>> scanFromGallery({
//     DocScanFormat format = DocScanFormat.jpeg,
//   }) async {
//     try {
//       final result = await _channel.invokeMethod('scanFromGallery', {
//         'format': format.name,
//       });
//
//       // Se il risultato è nullo, significa che l'utente ha annullato l'operazione.
//       // Restituisce una lista vuota per coerenza.
//       if (result == null) {
//         return [];
//       }
//
//       if (result is! List) {
//         throw DocumentScannerException(
//           'Risposta non valida dal codice nativo, attesa una Lista, ricevuto ${result.runtimeType}',
//         );
//       }
//
//       return result.cast<String>();
//     } on PlatformException catch (e) {
//       // Gestisce l'errore specifico per la galleria non disponibile su iOS < 14
//       if (e.code == 'UNAVAILABLE') {
//         throw DocumentScannerException(
//           'Funzionalità non disponibile: ${e.message}',
//         );
//       }
//       throw DocumentScannerException(e.message ?? 'Errore sconosciuto');
//     }
//   }
// }

/// Formati di file supportati per il salvataggio.
enum DocScanFormat { pdf, jpeg }

/// Filtri colore applicabili all'immagine.
enum DocScanFilter { none, grayscale, blackAndWhite, custom }

/// Eccezione sollevata durante le operazioni di scansione.
class DocumentScannerException implements Exception {
  final String message;
  DocumentScannerException(this.message);
  @override
  String toString() => 'DocumentScannerException: $message';
}

/// Rappresenta le coordinate normalizzate (0-1) dei quattro angoli di un documento.
class Quadrilateral {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomLeft;
  final Offset bottomRight;

  Quadrilateral({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  factory Quadrilateral.fromMap(Map<dynamic, dynamic> map) {
    return Quadrilateral(
      topLeft: Offset(map['topLeftX'] as double, map['topLeftY'] as double),
      topRight: Offset(map['topRightX'] as double, map['topRightY'] as double),
      bottomLeft: Offset(map['bottomLeftX'] as double, map['bottomLeftY'] as double),
      bottomRight: Offset(map['bottomRightX'] as double, map['bottomRightY'] as double),
    );
  }

  Map<String, double> toMap() {
    return {
      'topLeftX': topLeft.dx, 'topLeftY': topLeft.dy,
      'topRightX': topRight.dx, 'topRightY': topRight.dy,
      'bottomLeftX': bottomLeft.dx, 'bottomLeftY': bottomLeft.dy,
      'bottomRightX': bottomRight.dx, 'bottomRightY': bottomRight.dy,
    };
  }
}

/// Classe principale per interagire con il motore di scansione nativo.
class DocumentScanner {
  static const MethodChannel _channel = MethodChannel('doc_scan');

  /// 1. Ottiene un'immagine dalla fotocamera o dalla galleria.
  static Future<String?> getImage({required String source}) async {
    return await _channel.invokeMethod('getImage', {'source': source});
  }

  /// 2. Rileva i bordi di un'immagine.
  static Future<Quadrilateral?> detectEdges(String imagePath) async {
    final result = await _channel.invokeMethod('detectEdges', {'imagePath': imagePath});
    if (result == null) return null;
    return Quadrilateral.fromMap(result as Map<dynamic, dynamic>);
  }

  /// 3. Applica il ritaglio, i filtri e salva l'immagine finale.
  static Future<String?> applyCropAndSave({
    required String imagePath,
    required Quadrilateral quad,
    required DocScanFormat format,
    required DocScanFilter filter,
    double? brightness, // Parametro opzionale per la luminosità
    double? contrast,   // Parametro opzionale per il contrasto
    double? threshold,
  }) async {
    return await _channel.invokeMethod('applyCropAndSave', {
      'imagePath': imagePath,
      'quad': quad.toMap(),
      'format': format.name,
      'filter': filter.name,
      'brightness': brightness,
      'contrast': contrast,
      'threshold': threshold
    });
  }
}