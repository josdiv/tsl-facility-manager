import 'package:equatable/equatable.dart';

/// A single application action. Implemented in each feature's domain layer.
abstract interface class UseCase<Output, Params> {
  Future<Output> call(Params params);
}

/// Params for use cases that take no input.
final class NoParams extends Equatable {
  const NoParams();

  @override
  List<Object?> get props => const [];
}
