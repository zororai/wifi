import 'errors.dart';

/// Outcome of an operation that can fail in an expected way.
/// Unexpected programming errors are still thrown, not wrapped.
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);
  final AppError error;
}
