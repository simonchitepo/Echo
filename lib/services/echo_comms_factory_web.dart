import 'echo_comms.dart';
import 'lan/lan_comms_service.dart';

EchoComms createEchoCommsImpl() {
  return LanCommsService();
}