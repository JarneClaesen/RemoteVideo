class FileTransferProgress {
  final int bytesTransferred;
  final int? totalBytes;
  final num speed; // bytes per second
  final DateTime lastUpdated;

  FileTransferProgress({
    required this.bytesTransferred,
    this.totalBytes,
    required this.speed,
    required this.lastUpdated,
  });

  double get progress =>
      totalBytes != null ? bytesTransferred / totalBytes! : 0.0;

  String get formattedProgress =>
      totalBytes != null ? '${(progress * 100).toStringAsFixed(1)}%' : 'Unknown';

  String get formattedSpeed {
    if (speed < 1024) {
      return '${speed.toStringAsFixed(1)} B/s';
    } else if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  String get formattedTransferred {
    if (bytesTransferred < 1024) {
      return '$bytesTransferred B';
    } else if (bytesTransferred < 1024 * 1024) {
      return '${(bytesTransferred / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytesTransferred / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  String get formattedTotal {
    if (totalBytes == null) return 'Unknown';
    if (totalBytes! < 1024) {
      return '$totalBytes B';
    } else if (totalBytes! < 1024 * 1024) {
      return '${(totalBytes! / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(totalBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}