import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  late MqttServerClient _client;
  bool _connected = false;
  String? _clientId;

  Timer? _reconnectTimer;

  Future<void> connect(String clientId) async {
    _clientId = clientId;

    _client = MqttServerClient('broker.emqx.io', clientId);
    _client.port = 1883;
    _client.secure = false;
    _client.keepAlivePeriod = 20;
    _client.logging(on: false);

    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;

    _client.onSubscribed = (topic) {
      print('[MQTT] Subscribed to $topic');
    };

    _client.pongCallback = () {
      print('[MQTT] Ping response received');
    };

    final connMess = mqtt.MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    _client.connectionMessage = connMess;

    await _tryConnect();
  }

  Future<void> _tryConnect() async {
    try {
      print("[MQTT] Intentando conectar a EMQX...");
      await _client.connect();

      final status = _client.connectionStatus;

      if (status?.state == mqtt.MqttConnectionState.connected) {
        print("[MQTT] Conectado al broker EMQX");
        _connected = true;

        _client.updates?.listen(
              (List<mqtt.MqttReceivedMessage<mqtt.MqttMessage?>> c) {
            final recMess = c[0].payload as mqtt.MqttPublishMessage;
            final payload =
            mqtt.MqttPublishPayload.bytesToStringAsString(
              recMess.payload.message,
            );

            print("[MQTT] Mensaje recibido -> Topic: ${c[0].topic}");
            print("[MQTT] Payload: $payload");
          },
        );
      } else {
        print("[MQTT] Fallo de conexión: $status");
        _connected = false;
        _client.disconnect();
        _scheduleReconnect();
      }
    } catch (e) {
      print("[MQTT] Excepción al conectar: $e");
      _connected = false;
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    print("[MQTT] Callback: conectado");
    _connected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _onDisconnected() {
    print("[MQTT] Callback: desconectado");
    _connected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;

    print("[MQTT] Intentando reconectar cada 5s...");

    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_connected) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        return;
      }

      if (_clientId != null) {
        await _tryConnect();
      }
    });
  }

  void publish(String topic, Map<String, dynamic> payload) {
    if (!_connected) {
      print("[MQTT] No conectado, no se puede publicar");
      return;
    }

    final builder = mqtt.MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    print("[MQTT] Publicando -> Topic: $topic");
    print("[MQTT] Payload: $payload");

    _client.publishMessage(
      topic,
      mqtt.MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void subscribe(String topic) {
    if (!_connected) {
      print("[MQTT] No conectado, no se puede suscribir");
      return;
    }

    print("[MQTT] Suscribiéndose a $topic");
    _client.subscribe(topic, mqtt.MqttQos.atLeastOnce);
  }

  void disconnect() {
    print("[MQTT] Desconectando cliente");
    _reconnectTimer?.cancel();
    _client.disconnect();
    _connected = false;
  }

  bool get isConnected => _connected;

  Future<void> testPublish() async {
    int retries = 0;

    while (!_connected && retries < 10) {
      print("[MQTT] Esperando conexión...");
      await Future.delayed(const Duration(seconds: 1));
      retries++;
    }

    if (!_connected) {
      print("[MQTT] No se pudo conectar tras varios intentos");
      return;
    }

    publish("miapp/test", {
      "device_id": _clientId,
      "msg": "hola desde flutter",
      "timestamp": DateTime.now().toIso8601String(),
    });
  }
}