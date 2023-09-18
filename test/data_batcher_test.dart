import 'package:data_batcher/data_batcher.dart';
import 'package:flutter_test/flutter_test.dart';

class TestModel {
  final String id;
  final int value;

  TestModel({
    required this.id,
    required this.value,
  });
}

Future<void> delay([Duration duration = const Duration(milliseconds: 10)]) {
  return Future.delayed(duration);
}

void main() {
  test('batches multiple IDs added individually', () async {
    final batcher = DataBatcher<TestModel>(
      execute: (inputs) async {
        return inputs.map((input) => TestModel(id: input, value: 0)).toList();
      },
    );

    batcher.add('1');
    batcher.add('2');

    final items = await batcher.complete();

    expect(items.length, 2);
    expect(items.first.id, '1');
    expect(items.last.id, '2');
  });

  test('batches multiple IDs added together', () async {
    final batcher = DataBatcher<TestModel>(
      execute: (inputs) async {
        return inputs.map((input) => TestModel(id: input, value: 0)).toList();
      },
    );

    batcher.addMany(['1', '2']);

    final items = await batcher.complete();

    expect(items.length, 2);
    expect(items.first.id, '1');
    expect(items.last.id, '2');
  });

  test('Separates batches across event ticks', () async {
    final batcher = DataBatcher<TestModel>(
      execute: (inputs) async {
        return inputs.map((input) => TestModel(id: input, value: 0)).toList();
      },
    );

    final firstTickItems = await batcher.addMany(['1', '2']);

    await delay();

    batcher.add('3');

    final secondTickItems = await batcher.complete();

    expect(firstTickItems.length, 2);
    expect(secondTickItems.length, 1);

    expect(firstTickItems.first.id, '1');
    expect(firstTickItems.last.id, '2');
    expect(secondTickItems.first.id, '3');
  });

  test('De-dupes in flight IDs by default', () async {
    int i = 0;

    final batcher = DataBatcher<TestModel>(
      execute: (inputs) async {
        await delay(const Duration(milliseconds: 50));
        return inputs.map((input) => TestModel(id: input, value: i++)).toList();
      },
    );

    final future1 = batcher.addMany(['1', '2']);

    await delay();

    final future2 = batcher.addMany(['1', '3']);

    // The batcher should separate the IDs into two batches: [1, 2] and [1, 3].
    // It should de-dupe ID 1 in the second batch, however, since it is still in flight
    // in batch 1 when batch 2 is executed. This should cause result 2 to include the same item for ID 1 as in result 1
    // and i should be equal to 3 since ID 1 should not have been processed again.

    final result1 = await future1;
    final result2 = await future2;

    expect(result1.length, 2);
    expect(result1.first.id, '1');
    expect(result1.first.value, 0);
    expect(result1.last.id, '2');
    expect(result1.last.value, 1);

    expect(result2.length, 2);
    expect(result2.first.id, '1');
    expect(result2.first.value, 0);
    expect(result2.last.id, '3');
    expect(result2.last.value, 2);

    expect(i, 3);
  });

  test('Does not de-dupe IDs if the previous batch is no longer in flight',
      () async {
    int i = 0;

    final batcher = DataBatcher<TestModel>(
      dedupeInFlight: false,
      execute: (inputs) async {
        await delay(const Duration(milliseconds: 50));
        return inputs.map((input) => TestModel(id: input, value: i++)).toList();
      },
    );

    final future1 = batcher.addMany(['1', '2']);

    await delay(const Duration(milliseconds: 100));

    final future2 = batcher.addMany(['1', '3']);

    // The batcher should separate the IDs into two batches: [1, 2] and [1, 3].
    // It should not de-dupe ID 1 in the second batch, however, since batch 1 is completed by the time batch 2 begins.
    // This should cause result 2 to include a different item for ID 1 than in result 1
    // and i should be equal to 4 since ID 1 should have been processed again.

    final result1 = await future1;
    final result2 = await future2;

    expect(result1.length, 2);
    expect(result1.first.id, '1');
    expect(result1.first.value, 0);
    expect(result1.last.id, '2');
    expect(result1.last.value, 1);

    expect(result2.length, 2);
    expect(result2.first.id, '1');
    expect(result2.first.value, 2);
    expect(result2.last.id, '3');
    expect(result2.last.value, 3);

    expect(i, 4);
  });

  test('Does not de-dupe in flight IDs when specified', () async {
    int i = 0;

    final batcher = DataBatcher<TestModel>(
      dedupeInFlight: false,
      execute: (inputs) async {
        await delay(const Duration(milliseconds: 50));
        return inputs.map((input) => TestModel(id: input, value: i++)).toList();
      },
    );

    final future1 = batcher.addMany(['1', '2']);

    await delay();

    final future2 = batcher.addMany(['1', '3']);

    // The batcher should separate the IDs into two batches: [1, 2] and [1, 3].
    // It should not de-dupe ID 1 in the second batch, however, since [dedupeInFlight] is false.
    // This should cause result 2 to include a different item for ID 1 than in result 1
    // and i should be equal to 4 since ID 1 should have been processed again.

    final result1 = await future1;
    final result2 = await future2;

    expect(result1.length, 2);
    expect(result1.first.id, '1');
    expect(result1.first.value, 0);
    expect(result1.last.id, '2');
    expect(result1.last.value, 1);

    expect(result2.length, 2);
    expect(result2.first.id, '1');
    expect(result2.first.value, 2);
    expect(result2.last.id, '3');
    expect(result2.last.value, 3);

    expect(i, 4);
  });

  test('Items should be resolved using the idExtractor', () async {
    int i = 0;

    final batcher = DataBatcher<TestModel>(
      idExtractor: (item) => item.value.toString(),
      execute: (inputs) async {
        return inputs
            .map((input) => TestModel(id: input, value: 3 - i++))
            .toList();
      },
    );

    final future1 = batcher.addMany(['1', '2']);
    batcher.add('3');
    final future2 = batcher.complete();

    final result1 = await future1;
    final result2 = await future2;

    expect(result1.length, 2);
    expect(result2.length, 3);

    // Since the idExtractor maps the items in reverse order, the item delivered for ID 1
    // is item 3, and the item delivered for ID 2 is item 2.
    expect(result1.first.id, '3');
    expect(result1.last.id, '2');

    // This should also be the case for the future returning the complete set of items returned from the batcher.
    expect(result2[0].id, '3');
    expect(result2[1].id, '2');
    expect(result2[2].id, '1');
  });

  test('Throws error if a batch request fails', () async {
    final batcher = DataBatcher<TestModel>(
      execute: (inputs) async {
        throw Exception();
      },
    );

    expectLater(batcher.add('1'), throwsException);
  });
}
