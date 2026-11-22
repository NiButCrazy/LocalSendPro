import 'package:localsend_app/util/native/admin_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Whether LocalSend runs with administrator privileges.
///
/// An elevated Windows process cannot receive files dragged in from Explorer.
final administratorProvider = Provider<bool>((ref) => isRunningAsAdministrator());
