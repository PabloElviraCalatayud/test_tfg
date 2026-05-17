class MqttMessage {
  final String topic;
  final String deviceId;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const MqttMessage({
    required this.topic,
    required this.deviceId,
    required this.timestamp,
    required this.data,
  });

  Map<String, dynamic> toJson() {
    return {
      "device_id": deviceId,
      "timestamp": timestamp.toIso8601String(),
      ...data,
    };
  }
}