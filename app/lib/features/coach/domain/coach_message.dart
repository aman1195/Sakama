/// One turn in the Vita conversation. Local-only for now (M3.3a); persistence
/// to a synced coach_messages table is a later slice.
enum CoachRole { user, vita }

class CoachMessage {
  const CoachMessage(this.role, this.content);
  final CoachRole role;
  final String content;

  /// For the wire format the Vita function expects.
  Map<String, String> toWire() =>
      {'role': role == CoachRole.user ? 'user' : 'assistant', 'content': content};
}
