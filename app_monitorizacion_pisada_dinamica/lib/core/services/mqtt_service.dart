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

    _client = MqttServerClient('192.168.1.19', clientId);
    _client.port = 1883;
    _client.keepAlivePeriod = 20;
    _client.logging(on: true);

    _client.onDisconnected = _onDisconnected;
    _client.onConnected = _onConnected;

    _client.onSubscribed = (topic) {
      print('Subscribed to $topic');
    };

    _client.pongCallback = () {
      print('Ping response received');
    };

    final connMess = mqtt.MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    _client.connectionMessage = connMess;

    await _tryConnect();
  }

  Future<void> _tryConnect() async {
    try {
      print("Intentando conectar...");
      await _client.connect();

      if (_client.connectionStatus?.state ==
          mqtt.MqttConnectionState.connected) {
        print("Conectado al broker MQTT");
        _connected = true;

        _client.updates?.listen((List<mqtt.MqttReceivedMessage<mqtt.MqttMessage?>> c) {
          final recMess = c[0].payload as mqtt.MqttPublishMessage;
          final payload = mqtt.MqttPublishPayload.bytesToStringAsString(
            recMess.payload.message,
          );
          print("Mensaje recibido: $payload");
        });

      } else {
        print("Fallo de conexión: ${_client.connectionStatus}");
        _connected = false;
        _client.disconnect();
        _scheduleReconnect();
      }
    } catch (e) {
      print("Excepción al conectar: $e");
      _connected = false;
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    print("Callback: conectado");
    _connected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _onDisconnected() {
    print("Callback: desconectado");
    _connected = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;

    print("Intentando reconectar cada 5s...");

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
      print("No conectado, no se puede publicar");
      return;
    }

    final builder = mqtt.MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    print("Publicando en $topic: $payload");

    _client.publishMessage(
      topic,
      mqtt.MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void subscribe(String topic) {
    if (!_connected) {
      print("No conectado, no se puede suscribir");
      return;
    }

    _client.subscribe(topic, mqtt.MqttQos.atLeastOnce);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _client.disconnect();
    _connected = false;
  }

  bool get isConnected => _connected;

  Future<void> testPublish() async {
    int retries = 0;

    while (!_connected && retries < 10) {
      print("Esperando conexión...");
      await Future.delayed(const Duration(seconds: 1));
      retries++;
    }

    if (!_connected) {
      print("No se pudo conectar tras varios intentos");
      return;
    }

    publish("test/topic", {
      "device_id": _clientId,
      "msg": "hola desde flutter",
      "timestamp": DateTime.now().toIso8601String(),
    });
  }
}