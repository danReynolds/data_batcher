library data_batcher;

import 'dart:async';
import 'dart:collection';

part 'extensions/list.dart';

/// A batch of IDs grouped together in the current tick of the event loop.
class _DataBatch<T> {
  final Future<List<T>> Function(List<String> ids) execute;
  final String Function(T item)? idExtractor;

  final LinkedHashSet<String> _ids = LinkedHashSet<String>();
  final Map<String, T> _itemsById = {};

  final _completer = Completer<void>();

  _DataBatch({
    required this.execute,
    this.idExtractor,
  });

  Future<void> get completed {
    return _completer.future;
  }

  /// Adds an ID to the batch, ignoring duplicates.
  void add(String id) {
    _ids.add(id);
  }

  List<T> get _items {
    return _ids.map((id) => _itemsById[id]!).toList();
  }

  /// Executes the batch by calling the provided [execute] function to fetch the data for the added batch IDs.
  /// The batch is completed with a map of IDs->items when the batcher function completes.
  Future<void> _execute() async {
    final items = await execute(_ids.toList());

    assert(
      items.length == _ids.length,
      'Batch error: Items returned length ${items.length} which is not equal to IDs length ${_ids.length}.',
    );

    for (int i = 0; i < items.length; i++) {
      // By default it is assumed that the items are returned in the same order as the list of input IDs provided
      // to the [execute] function and the IDs of the items are extracted using that ordering. If the ordering is not stable,
      // then an [idExtractor] can be used.
      final id = idExtractor?.call(items[i]) ?? _ids.elementAt(i);
      _itemsById[id] = items[i];
    }

    assert(
      _itemsById.length == _ids.length,
      'Batch error: Expected ${_ids.length} unique IDs extracted by idExtractor but it extracted ${_itemsById.length}.',
    );

    _completer.complete();
  }
}

class DataBatcher<T> {
  final Future<List<T>> Function(List<String> ids) execute;
  final String Function(T item)? idExtractor;

  /// IDs are batched together in the current tick of the event loop. If an ID is attempted
  /// to be batched again on a subsequent tick of the event loop while still in-flight from a previous
  /// batch, then by default it is not batched again the value returned for that ID is the value returned
  /// by the already in-flight batch.
  final bool dedupeInFlight;

  /// A map used to de-dupe requesting an ID again while another previous batch that contains that ID is in-flight.
  /// The map is not used if [dedupeInFlight] is false.
  final Map<String, _DataBatch<T>> _inFlightBatchMap = {};

  _DataBatch<T>? _eventBatch;

  static final Map<String, DataBatcher> _globalBatchers = {};

  DataBatcher({
    required this.execute,
    this.idExtractor,
    this.dedupeInFlight = true,
  });

  _DataBatch<T> _getBatchById(String id) {
    if (dedupeInFlight && _inFlightBatchMap.containsKey(id)) {
      return _inFlightBatchMap[id]!;
    }

    _DataBatch<T>? batch = _eventBatch;

    // If there is no batch yet for the current event loop, then create a new batch
    // and mark it to execute on the next microtask.
    if (batch == null) {
      batch = _eventBatch = _DataBatch<T>(
        execute: execute,
        idExtractor: idExtractor,
      );

      // The batch for the current event loop is scheduled to be executed on a micro-task, batching
      // all IDs added in the current event loop together.
      scheduleMicrotask(() async {
        _eventBatch = null;

        batch!._execute();
        await batch.completed;

        // After the batch is completed, if IDs are being de-duped, clear them from the in flight batch map.
        if (dedupeInFlight) {
          for (id in batch._ids) {
            _inFlightBatchMap.remove(id);
          }
        }
      });
    }

    // If [dedupeInFlight] is enabled, then the current ID's batch is recorded so that
    // subsequent attempts to batch that ID can be de-duped and pointed to this batch.
    if (dedupeInFlight && !_inFlightBatchMap.containsKey(id)) {
      _inFlightBatchMap[id] = batch;
    }

    return batch;
  }

  Future<List<T>> addMany(List<String> ids) async {
    final List<T> items = [];
    final List<_DataBatch<T>> batches = [];

    for (final id in ids) {
      final batch = _getBatchById(id);
      batch.add(id);
      batches.add(batch);
    }

    for (int i = 0; i < ids.length; i++) {
      final id = ids[i];
      final batch = batches[i];

      await batch.completed;
      items.add(batch._itemsById[id] as T);
    }

    return items;
  }

  Future<T> add(String id) async {
    final batch = _getBatchById(id);
    batch.add(id);

    await batch.completed;
    return batch._itemsById[id]!;
  }

  /// Creates and executes a global batcher
  static Future<T> run<T>(String id, Future<T> Function() executeFn) {
    final globalBatcher = (
      _globalBatchers[id] ??
          DataBatcher<T>(
            execute: (_) async {
              final result = await executeFn();
              return [result];
            },
          ),
    ) as DataBatcher<T>;

    return globalBatcher.add(id);
  }

  Future<List<T>> complete() async {
    final batch = _eventBatch;

    if (batch == null) {
      return Future.value([]);
    }

    await batch.completed;
    return batch._items;
  }
}
