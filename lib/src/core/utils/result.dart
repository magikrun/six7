import 'package:freezed_annotation/freezed_annotation.dart';

part 'result.freezed.dart';

/// A Result type for explicit error handling.
/// MUST be used instead of throwing exceptions for recoverable errors.
@freezed
sealed class Result<T, E> with _$Result<T, E> {
  const factory Result.ok(T value) = Ok<T, E>;
  const factory Result.err(E error) = Err<T, E>;

  const Result._();

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T? get okOrNull => switch (this) {
        Ok(:final value) => value,
        Err() => null,
      };

  E? get errOrNull => switch (this) {
        Ok() => null,
        Err(:final error) => error,
      };

  T unwrap() => switch (this) {
        Ok(:final value) => value,
        Err(:final error) =>
          throw StateError('Called unwrap on Err: $error'),
      };

  T unwrapOr(T defaultValue) => switch (this) {
        Ok(:final value) => value,
        Err() => defaultValue,
      };

  /// Maps the Ok value to a new type.
  /// Use this instead of freezed's map for Result transformation.
  Result<U, E> mapOk<U>(U Function(T) mapper) => switch (this) {
        Ok(:final value) => Result.ok(mapper(value)),
        Err(:final error) => Result.err(error),
      };

  Result<T, F> mapErr<F>(F Function(E) mapper) => switch (this) {
        Ok(:final value) => Result.ok(value),
        Err(:final error) => Result.err(mapper(error)),
      };

  Result<U, E> flatMap<U>(Result<U, E> Function(T) mapper) => switch (this) {
        Ok(:final value) => mapper(value),
        Err(:final error) => Result.err(error),
      };
}
