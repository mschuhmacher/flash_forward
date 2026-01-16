import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Represents a pending sync operation to be retried when online
class SyncOperation {
  final String id;
  final String type; // 'uploadSession', 'deleteSession', 'logSession', etc.
  final Map<String, dynamic> data;
  final DateTime createdAt;

  SyncOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
    id: json['id'],
    type: json['type'],
    data: json['data'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

/// Manages a queue of pending sync operations for offline support
class SyncQueueService {
  static const String _queueFileName = 'sync_queue.json';

  List<SyncOperation> _queue = [];
  bool _isProcessing = false;

  /// Load the queue from local storage
  Future<void> loadQueue() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_queueFileName');

      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(contents);
        _queue = jsonList.map((json) => SyncOperation.fromJson(json)).toList();
      }
    } catch (e) {
      print('Error loading sync queue: $e');
      _queue = [];
    }
  }

  /// Save the queue to local storage
  Future<void> _saveQueue() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_queueFileName');
      final jsonList = _queue.map((op) => op.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Error saving sync queue: $e');
    }
  }

  /// Add an operation to the queue
  Future<void> enqueue(SyncOperation operation) async {
    // Check if operation with same id already exists (avoid duplicates)
    _queue.removeWhere((op) => op.id == operation.id && op.type == operation.type);
    _queue.add(operation);
    await _saveQueue();
  }

  /// Remove an operation from the queue (after successful sync)
  Future<void> dequeue(String operationId) async {
    _queue.removeWhere((op) => op.id == operationId);
    await _saveQueue();
  }

  /// Get all pending operations
  List<SyncOperation> get pendingOperations => List.unmodifiable(_queue);

  /// Check if there are pending operations
  bool get hasPendingOperations => _queue.isNotEmpty;

  /// Get count of pending operations
  int get pendingCount => _queue.length;

  /// Check if device has internet connectivity
  Future<bool> hasConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.any((result) =>
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.mobile ||
      result == ConnectivityResult.ethernet
    );
  }

  /// Process the queue with a provided handler function
  /// Returns the number of successfully processed operations
  Future<int> processQueue(
    Future<bool> Function(SyncOperation operation) handler,
  ) async {
    if (_isProcessing || _queue.isEmpty) return 0;

    // Check connectivity first
    if (!await hasConnectivity()) {
      print('No connectivity, skipping queue processing');
      return 0;
    }

    _isProcessing = true;
    int successCount = 0;

    // Process a copy of the queue to avoid modification during iteration
    final queueCopy = List<SyncOperation>.from(_queue);

    for (final operation in queueCopy) {
      try {
        final success = await handler(operation);
        if (success) {
          await dequeue(operation.id);
          successCount++;
        }
      } catch (e) {
        print('Error processing queued operation ${operation.id}: $e');
        // Keep in queue for retry
      }
    }

    _isProcessing = false;
    return successCount;
  }

  /// Clear all pending operations
  Future<void> clearQueue() async {
    _queue.clear();
    await _saveQueue();
  }
}
