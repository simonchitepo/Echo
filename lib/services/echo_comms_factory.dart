import 'echo_comms.dart';

import 'echo_comms_factory_stub.dart'
if (dart.library.html) 'echo_comms_factory_web.dart'
if (dart.library.io) 'echo_comms_factory_io.dart';

EchoComms createEchoComms() => createEchoCommsImpl();