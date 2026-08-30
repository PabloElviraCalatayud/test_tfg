import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'mqtt_platform_io.dart'
    if (dart.library.js_interop) 'mqtt_platform_web.dart';

// Broker publico EMQX, sobre WebSocket seguro (wss, puerto 8084, path
// /mqtt). Wss es obligatorio (requisito de red de la universidad -- el
// trafico tiene que ir cifrado), asi que no se contempla bajar a ws/8083
// aunque fuera util como diagnostico. Se usa WebSocket -- en vez del
// puerto TCP directo 1883 -- porque Flutter Web no tiene sockets TCP
// (dart:io no existe en el navegador), asi el mismo MqttService sirve
// tanto para movil/escritorio como para un build web usado para generar
// datos simulados sin el ESP32-S3 conectado.
const _kMqttServer = 'wss://broker.emqx.io/mqtt';
const _kMqttPort = 8084;

class MqttService {
  late mqtt.MqttClient _client;
  bool _connected = false;
  String? _clientId;

  Timer? _reconnectTimer;

  Future<void> connect(String clientIdPrefix) async {
    // El Client ID debe ser unico por broker: con un prefijo fijo, dos
    // sesiones conectadas a la vez (p.ej. el movil real y un build de
    // pruebas en el navegador) hacen que el broker desconecte en
    // silencio a la que ya estaba conectada.
    final clientId =
        '${clientIdPrefix}_${Random().nextInt(0xFFFFFF).toRadixString(16)}';
    _clientId = clientId;

    _client = createPlatformMqttClient(_kMqttServer, clientId, _kMqttPort);
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
      print("[MQTT] Intentando conectar a EMQX ($_kMqttServer:$_kMqttPort)...");
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

    publish("flutter_pisada/test/manual_test", {
      "device_id": _clientId,
      "msg": "hola desde flutter",
      "timestamp": DateTime.now().toIso8601String(),
    });
  }
}
