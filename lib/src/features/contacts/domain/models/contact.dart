import 'package:freezed_annotation/freezed_annotation.dart';

part 'contact.freezed.dart';
part 'contact.g.dart';

/// Represents a saved contact.
@freezed
abstract class Contact with _$Contact {
  const factory Contact({
    /// The Korium identity (Ed25519 public key hex)
    required String identity,

    /// User-defined display name
    required String displayName,

    /// Optional avatar URL
    String? avatarUrl,

    /// Optional status message
    String? status,

    /// When the contact was added
    required DateTime addedAt,

    /// Whether the contact is blocked
    @Default(false) bool isBlocked,

    /// Whether the contact is a favorite
    @Default(false) bool isFavorite,
  }) = _Contact;

  factory Contact.fromJson(Map<String, dynamic> json) =>
      _$ContactFromJson(json);
}
