/// Wrapper that lets [copyWith] methods distinguish between
/// "not provided" (omit the parameter) and "explicitly set to null"
/// (pass [Nullable(null)]).
///
/// Usage:
///   copyWith(rpe: Nullable(5))     // set to 5
///   copyWith(rpe: Nullable(null))  // clear to null
///   copyWith()                      // keep existing value
class Nullable<T> {
  final T? value;
  const Nullable(this.value);
}
