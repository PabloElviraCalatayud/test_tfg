import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

/// Cliente MQTT para Flutter Web: MqttBrowserClient ya usa WebSocket de
/// forma implicita (es la unica opcion en el navegador), no existe un
/// flag useWebSocket que activar como en el cliente nativo.
MqttClient createPlatformMqttClient(String server, String clientId, int port) {
  return MqttBrowserClient.withPort(server, clientId, port);
}
