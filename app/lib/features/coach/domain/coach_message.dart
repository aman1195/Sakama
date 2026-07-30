/// One turn in the Vita conversation. Local-only for now (M3.3a); persistence
/// to a synced coach_messages table is a later slice.
enum CoachRole { user, vita }

class CoachMessage {
  const CoachMessage(this.role, this.content, {this.synthetic = false});
  final CoachRole role;
  final String content;

  /// App-generated chrome (budget/error notices), NOT a model turn — kept in
  /// the visible thread but excluded from what we replay upstream, so the
  /// model never mistakes our copy for its own prior reply (review #58).
  final bool synthetic;

  /// For the wire format the Vita function expects.
  Map<String, String> toWire() =>
      {'role': role == CoachRole.user ? 'user' : 'assistant', 'content': content};
}
