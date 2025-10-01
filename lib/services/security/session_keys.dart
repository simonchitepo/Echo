import 'package:cryptography/cryptography.dart';

class SessionKeys {
  final SecretKey sessionKey;
  int sendSeq;
  int recvSeqMax;

  SessionKeys({
    required this.sessionKey,
    this.sendSeq = 0,
    this.recvSeqMax = -1,
  });
}