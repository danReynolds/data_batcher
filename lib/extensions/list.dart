part of data_batcher;

extension ListExtensions<T> on List<T> {
  Map<S, T> keyBy<S>(S Function(T item) keyBy) {
    return fold({}, (acc, item) {
      final id = keyBy(item);

      return {
        ...acc,
        id: item,
      };
    });
  }
}
