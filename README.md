# Data Batcher

Data batcher batches and de-dupes data fetched in the same cycle of the event loop.

```dart
final batcher = DataBatcher<String>(
  execute: (ids) async {
    print(ids) // ['1', '2', '3', '4']
    return Api.fetch(ids);
  },
);

batcher.add('1');
batcher.add('2');

batcher.addMany(['2', '3']);

await batcher.add('4');
```

When IDs are added to a batcher, they are grouped by the current cycle of the event loop and scheduled to be executed on a micro-task.
Once executed successfully, the batcher resolves each caller's future with its data as shown below:

```dart
final batcher = DataBatcher<String>(
  execute: (ids) async {
    return ['a', 'b', 'c'];
  },
);

batcher.add('1').then(((resp) => print(resp)); // 'a'
batcher.add('2').then(((resp) => print(resp)); // 'b'

batcher.addMany(['2', '3']).then(((resp) => print(resp)) // ['b', 'c']
```

Data added to a batcher across different ticks of the event loop is broken into separate batches:

```dart
final batcher = DataBatcher<String>(
  execute: (ids) async {
    print(ids);
    // ['1', '2']
    // ['3']
    return Api.fetch(ids);
  },
);

batcher.add('1');
await batcher.add('2');

batcher.add('3');
```

By default, data IDs that are still in-flight from a previous batch which are requested again are not re-fetched:

```dart
final batcher = DataBatcher<String>(
  execute: (ids) async {
    print(ids);
    // ['1', '2']
    return Future.delayed(Duration(seconds: 5));
  },
);

batcher.add('1');
batcher.add('2');

await Future.delayed(Duration(seconds: 1));

batcher.add('1');
```

The second attempt to request data with ID 1 is de-duped, since it is called while the in-flight request for '1' and '2' has not resolved. The Future returned by the second call to add ID 1 will resolve when the first original batch succeeds and with its returned value for ID 1.

If de-duping of in-flight data is not preferred, the `dedupeInFlight` flag can be set to false:

```dart
final batcher = DataBatcher<String>(
  dedupeInFlight: false,
  execute: (ids) async {
    print(ids);
    // ['1', '2']
    // ['1']
    return Future.delayed(Duration(seconds: 5), () {...});
  },
);

batcher.add('1');
batcher.add('2');

await Future.delayed(Duration(seconds: 1));

batcher.add('1');
```

IDs are mapped to data responses using the order of the returned data. If needed, an `idExtractor` can be specified instead in order to associated response data with its matching input ID:

```dart
final batcher = DataBatcher<DataModel>(
  idExtractor: (dataModel) => dataModel.id,
  execute: (ids) async {
    print(ids);
    // ['1', '2']
    return [DataModel('1'), DataModel('2')]
  },
);

batcher.add('1');
batcher.add('2');
```

