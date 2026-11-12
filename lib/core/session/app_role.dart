/// The three experiences in the mobile app.
enum AppRole {
  client('client', 'Client'),
  staff('staff', 'Staff'),
  supervisor('supervisor', 'Supervisor');

  const AppRole(this.path, this.label);

  final String path;
  final String label;

  static AppRole fromPath(String? path) =>
      values.firstWhere((role) => role.path == path, orElse: () => client);
}
