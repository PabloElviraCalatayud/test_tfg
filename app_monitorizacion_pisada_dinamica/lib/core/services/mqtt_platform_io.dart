import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Cliente MQTT para Android/iOS/escritorio, sobre WebSocket (dart:io
/// disponible). `useWebSocket` solo existe en MqttServerClient -- por eso
/// vive aqui y no en el codigo compartido de MqttService.
MqttClient createPlatformMqttClient(String server, String clientId, int port) {
  final client = MqttServerClient.withPort(server, clientId, port);
  client.useWebSocket = true;
  return client;
}
