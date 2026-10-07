/// Base type for expected, user-explainable failures.
/// [message] is safe to show to the user; [cause] is for diagnostics only.
sealed class AppError {
  const AppError(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

final class DatabaseError extends AppError {
  const DatabaseError(super.message, {super.cause, super.stackTrace});
}
