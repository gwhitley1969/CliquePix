sealed class AppFailure {
  final String message;
  const AppFailure(this.message);

  @override
  String toString() => message;
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'Network error. Please check your connection.']);
}

class AuthFailure extends AppFailure {
  const AuthFailure([super.message = 'Authentication failed. Please sign in again.']);
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'The requested item was not found.']);
}

class ValidationFailure extends AppFailure {
  const ValidationFailure([super.message = 'Invalid input.']);
}

class ServerFailure extends AppFailure {
  const ServerFailure([super.message = 'Something went wrong. Please try again.']);
}

class PermissionFailure extends AppFailure {
  const PermissionFailure([super.message = 'You do not have permission for this action.']);
}

class StorageFailure extends AppFailure {
  const StorageFailure([super.message = 'Failed to access storage.']);
}
