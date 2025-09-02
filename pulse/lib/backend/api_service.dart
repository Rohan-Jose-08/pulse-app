import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth/firebase_auth/auth_util.dart';
import '../auth/firebase_auth/firebase_user_provider.dart';
import 'config.dart';

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._() {
    _client = http.Client();
  } // private constructor

  static String get _baseUrl => getBackendHttpBase();
  late final http.Client _client;

  Future<String?> _getAuthToken() async {
    // Get Firebase ID token for authentication
    final user = currentUser;
    if (user == null) return null;

    // Cast to PulseFirebaseUser to access the underlying Firebase User object
    if (user is PulseFirebaseUser && user.user != null) {
      try {
        final idToken = await user.user!.getIdToken();
        return idToken;
      } catch (e) {
        print('Error getting Firebase ID token: $e');
        return null;
      }
    }

    return null;
  }

  Map<String, String> _getHeaders(String? token) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<bool> ensureUserExists() async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return false;
      }

      print('Attempting to ensure user exists with token: $token');

      final url = '$_baseUrl/auth';
      final response = await _client.post(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      print('Auth response status: ${response.statusCode}');
      print('Auth response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('User ensured in backend database');
        return true;
      } else {
        print(
            'Failed to ensure user exists: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error ensuring user exists: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> createPulse({
    required String title,
    String? description,
    String? location,
    required DateTime eventTime,
    bool isPublic = true,
    List<String>? tags,
    String? imageUrl,
    double? latitude,
    double? longitude,
    DateTime? activeFrom,
    DateTime? activeUntil,
    int? activeDurationMinutes,
  }) async {
    // Ensure user exists in backend before creating pulse
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot create pulse: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/pulses';
      final payload = <String, dynamic>{
        'title': title,
        'description': description,
        'location': location,
        'eventTime': eventTime.toIso8601String(),
        'isPublic': isPublic,
        'tags': tags ?? [],
        'imageUrl': imageUrl,
      };
      if (latitude != null && longitude != null) {
        // backend will reverse geocode & create Location row
        payload['latitude'] = latitude;
        payload['longitude'] = longitude;
      }
      if (activeFrom != null) {
        payload['activeFrom'] = activeFrom.toIso8601String();
      }
      if (activeUntil != null) {
        payload['activeUntil'] = activeUntil.toIso8601String();
      }
      if (activeDurationMinutes != null) {
        payload['activeDurationMinutes'] = activeDurationMinutes;
      }
      final body = jsonEncode(payload);

      final response = await _client.post(
        Uri.parse(url),
        headers: _getHeaders(token),
        body: body,
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to create pulse: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error creating pulse: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getPulses({
    List<String>? tags,
    String? search,
    String? location,
    DateTime? eventTime,
    double? latitude,
    double? longitude,
    double? radiusKm,
  }) async {
    // Ensure user exists in backend before fetching pulses
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch pulses: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      // Build query parameters
      final params = <String, String>{};
      if (tags != null && tags.isNotEmpty) params['tags'] = tags.join(',');
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      if (location != null && location.isNotEmpty) {
        params['location'] = location;
      }
      if (eventTime != null) {
        params['eventTime'] = eventTime.toIso8601String();
      }
      if (latitude != null && longitude != null) {
        params['lat'] = latitude.toString();
        params['lng'] = longitude.toString();
        if (radiusKm != null) params['radiusKm'] = radiusKm.toString();
      }

      final url = Uri.parse('$_baseUrl/pulses').replace(
        queryParameters: params.isNotEmpty ? params : null,
      );

      final response = await _client.get(
        url,
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      } else {
        print(
            'Failed to fetch pulses: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching pulses: $e');
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>?> testBackendConnection() async {
    try {
      final url = '$_baseUrl/health';
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Backend health check: $data');
        return data;
      } else {
        print(
            'Backend health check failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error testing backend connection: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPulseById(String pulseId) async {
    // Ensure user exists in backend before fetching pulse
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch pulse: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/pulses/$pulseId';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Pulse data received: $data'); // Debug log

        // Add debug info about current user
        final user = currentUser;
        if (user != null) {
          print('Current user info: ${user.toString()}');
        }

        if (data is Map<String, dynamic>) {
          // Validate that we have the required fields
          if (data['id'] == null) {
            print('Warning: Pulse data missing ID field');
          }
          if (data['title'] == null) {
            print('Warning: Pulse data missing title field');
          }
          return data;
        } else {
          print('Error: Pulse data is not a Map<String, dynamic>');
          return null;
        }
      } else if (response.statusCode == 404) {
        print('Pulse not found: ${response.statusCode} - ${response.body}');
        return null;
      } else if (response.statusCode == 401) {
        print('Unauthorized: ${response.statusCode} - ${response.body}');
        return null;
      } else {
        print(
            'Failed to fetch pulse: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching pulse: $e');
      return null;
    }
  }

  /// Reverse geocode a geohash to a human friendly label + raw address (backend caches & best-effort)
  Future<Map<String, dynamic>?> reverseGeocodeGeohash(String geohash) async {
    if (geohash.isEmpty) return null;
    try {
      final url = '$_baseUrl/geohash/reverse?hash=$geohash';
      final resp =
          await _client.get(Uri.parse(url), headers: _getHeaders(null));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) return data;
      } else {
        print('Reverse geocode failed ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      print('Reverse geocode error: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getUserPulses() async {
    // Ensure user exists in backend before fetching user pulses
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch user pulses: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/pulses';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      } else {
        print(
            'Failed to fetch user pulses: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching user pulses: $e');
      return null;
    }
    return null;
  }

  Future<List<String>?> getTags() async {
    // Ensure user exists in backend before fetching tags
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch tags: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/pulses/tags';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<String>.from(data);
        }
      } else {
        print(
            'Failed to fetch tags: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching tags: $e');
      return null;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> searchPulses(String query) async {
    // Ensure user exists in backend before fetching pulses
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot search pulses: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url =
          '$_baseUrl/pulses/search?query=${Uri.encodeQueryComponent(query)}';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      } else {
        print(
            'Failed to search pulses: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error searching pulses: $e');
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>?> joinPulse(String pulseId) async {
    // Ensure user exists in backend before joining pulse
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot join pulse: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/pulses/$pulseId/join';
      final response = await _client.post(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to join pulse: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error joining pulse: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> leavePulse(String pulseId) async {
    // Ensure user exists in backend before leaving pulse
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot leave pulse: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/pulses/$pulseId/leave';
      final response = await _client.post(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to leave pulse: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error leaving pulse: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updatePulse({
    required String pulseId,
    String? title,
    String? description,
    DateTime? eventTime,
    bool? isPublic,
    List<String>? tags,
    String? imageUrl,
    int? maxParticipants,
    String? category,
    String? difficulty,
    double? price,
    String? currency,
  }) async {
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot update pulse: User not registered in backend');
      return null;
    }
    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }
      final url = '$_baseUrl/pulses/$pulseId';
      final body = jsonEncode({
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (eventTime != null) 'eventTime': eventTime.toIso8601String(),
        if (isPublic != null) 'isPublic': isPublic,
        if (tags != null) 'tags': tags,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (maxParticipants != null) 'maxParticipants': maxParticipants,
        if (category != null) 'category': category,
        if (difficulty != null) 'difficulty': difficulty,
        if (price != null) 'price': price,
        if (currency != null) 'currency': currency,
        // coordinates removed
      });
      final response = await _client.put(Uri.parse(url),
          headers: _getHeaders(token), body: body);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('updatePulse failed: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      print('Error updating pulse: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> patchPulse({
    required String pulseId,
    Map<String, dynamic>? fields,
  }) async {
    final userExists = await ensureUserExists();
    if (!userExists) return null;
    try {
      final token = await _getAuthToken();
      if (token == null) return null;
      final url = '$_baseUrl/pulses/$pulseId';
      final response = await _client.patch(Uri.parse(url),
          headers: _getHeaders(token), body: jsonEncode(fields ?? {}));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('patchPulse failed: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      print('Error patching pulse: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPulseParticipants(String pulseId) async {
    // Ensure user exists in backend before fetching participants
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch pulse participants: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/pulses/$pulseId/participants';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to fetch pulse participants: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching pulse participants: $e');
      return null;
    }
  }

  // Messaging APIs
  Future<Map<String, dynamic>?> getOrCreateConversationWith(
      String otherUserId) async {
    try {
      // Ensure user exists before messaging
      final ensured = await ensureUserExists();
      if (!ensured) return null;
      final token = await _getAuthToken();
      if (token == null) return null;
      final url = '$_baseUrl/conversations/with/$otherUserId';
      final response =
          await _client.post(Uri.parse(url), headers: _getHeaders(token));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('Error getOrCreateConversationWith: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> listConversations() async {
    try {
      final ensured = await ensureUserExists();
      if (!ensured) return null;
      final token = await _getAuthToken();
      if (token == null) return null;
      final url = '$_baseUrl/conversations';
      final response =
          await _client.get(Uri.parse(url), headers: _getHeaders(token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          try {
            final pulseGroups =
                data.where((c) => c is Map && c['pulseId'] != null).length;
            print(
                'listConversations debug: total=${data.length} pulseGroups=$pulseGroups');
            if (pulseGroups == 0 && data.isNotEmpty) {
              print('listConversations sample[0]: ' + data.first.toString());
            }
          } catch (e) {
            print('listConversations debug parse error: $e');
          }
          return List<Map<String, dynamic>>.from(data);
        }
      }
    } catch (e) {
      print('Error listConversations: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> listMessages(String conversationId,
      {String? cursor, int limit = 30}) async {
    try {
      final ensured = await ensureUserExists();
      if (!ensured) return null;
      final token = await _getAuthToken();
      if (token == null) return null;
      final url =
          Uri.parse('$_baseUrl/conversations/$conversationId/messages').replace(
        queryParameters: {
          if (cursor != null) 'cursor': cursor,
          'limit': limit.toString(),
        },
      );
      final response = await _client.get(url, headers: _getHeaders(token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
      }
    } catch (e) {
      print('Error listMessages: $e');
    }
    return null;
  }

  /// Invite members to an existing conversation (group chat)
  /// Backend endpoint (new): POST /conversations/{conversationId}/invitations
  /// Body: { "userIds": ["uid1", "uid2"] }
  /// Returns created invitations.
  Future<Map<String, dynamic>?> addMembersToConversation(
      String conversationId, List<String> userIds) async {
    if (userIds.isEmpty) return null;
    try {
      final ensured = await ensureUserExists();
      if (!ensured) return null;
      final token = await _getAuthToken();
      if (token == null) return null;
      final url = '$_baseUrl/conversations/$conversationId/invitations';
      final response = await _client.post(Uri.parse(url),
          headers: _getHeaders(token), body: jsonEncode({'userIds': userIds}));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) return data;
        return {'status': 'ok'}; // fallback
      } else {
        print(
            'addMembersToConversation failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error addMembersToConversation: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getPulseChat(String pulseId) async {
    try {
      final ensured = await ensureUserExists();
      if (!ensured) {
        print('getPulseChat: User not ensured in backend');
        return null;
      }
      final token = await _getAuthToken();
      if (token == null) {
        print('getPulseChat: No auth token available');
        return null;
      }
      final getUrl = '$_baseUrl/pulses/$pulseId/chat';
      print('getPulseChat: Trying GET $getUrl');
      http.Response? response;
      try {
        response =
            await _client.get(Uri.parse(getUrl), headers: _getHeaders(token));
      } catch (e) {
        print('getPulseChat GET error: $e');
      }
      if (response == null ||
          response.statusCode == 404 ||
          response.statusCode == 405) {
        // Fallback to legacy POST create-or-get behavior
        final postUrl = getUrl;
        print('getPulseChat: Fallback POST $postUrl');
        response =
            await _client.post(Uri.parse(postUrl), headers: _getHeaders(token));
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('getPulseChat: Response status: ${response.statusCode}');
        final body = response.body;
        // Avoid logging potentially large data; truncate
        print('getPulseChat: Response body (truncated): ' +
            (body.length > 300 ? body.substring(0, 300) + '...' : body));
        final data = jsonDecode(body);
        if (data is Map<String, dynamic>) {
          if (data.containsKey('conversationId')) {
            data['id'] = data['conversationId'];
          }
          return data;
        }
      } else {
        print(
            'getPulseChat failed final: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error getPulseChat: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getCreatedPulses() async {
    // Fetch all pulses visible to the user, then filter client-side
    try {
      final all = await getPulses();
      if (all == null) return null;

      final uid = currentUserUid;
      if (uid.isEmpty) {
        print('No current user UID available');
        return [];
      }

      final created = all.where((p) {
        try {
          final authorId = (p['author'] != null && p['author'] is Map)
              ? (p['author']['id'] as String?)
              : (p['authorId'] as String?);
          return authorId == uid;
        } catch (e) {
          print('Error processing pulse author: $e');
          return false;
        }
      }).toList();
      return created;
    } catch (e) {
      print('Error filtering created pulses: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getParticipatingPulses() async {
    // Fetch all pulses visible to the user, then filter client-side
    try {
      final all = await getPulses();
      if (all == null) return null;

      final uid = currentUserUid;
      if (uid.isEmpty) {
        print('No current user UID available');
        return [];
      }

      final participating = all.where((p) {
        try {
          final participants =
              (p['participants'] as List<dynamic>?) ?? const [];
          final isParticipant = participants.any((pp) {
            if (pp is Map<String, dynamic>) {
              return pp['id'] == uid;
            }
            return false;
          });
          final authorId = (p['author'] != null && p['author'] is Map)
              ? (p['author']['id'] as String?)
              : (p['authorId'] as String?);
          final isAuthor = authorId == uid;
          return isParticipant && !isAuthor;
        } catch (e) {
          print('Error processing pulse participants: $e');
          return false;
        }
      }).toList();
      return participating;
    } catch (e) {
      print('Error filtering participating pulses: $e');
      return null;
    }
  }

  Future<bool> deletePulse(String pulseId) async {
    // Ensure user exists in backend before deleting pulse
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot delete pulse: User not registered in backend');
      return false;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return false;
      }

      final url = '$_baseUrl/pulses/$pulseId';
      final response = await _client.delete(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print(
            'Failed to delete pulse: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error deleting pulse: $e');
      return false;
    }
  }

  // Geohash nearby public pulses
  Future<List<Map<String, dynamic>>?> getNearbyPulsesGeohash({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
  }) async {
    // DEPRECATED: backend geohash endpoint removed; fall through to structured version
    return getNearbyPulses(
        latitude: latitude, longitude: longitude, radiusKm: radiusKm);
  }

  // Nearby public pulses using structured Location relation (bounding box + haversine on backend)
  Future<List<Map<String, dynamic>>?> getNearbyPulses({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
  }) async {
    try {
      final token = await _getAuthToken();
      // _baseUrl already includes '/api'; avoid duplicating it.
      final url =
          '$_baseUrl/pulses/nearby?lat=$latitude&lng=$longitude&radiusKm=$radiusKm';
      final resp =
          await _client.get(Uri.parse(url), headers: _getHeaders(token));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['pulses'] is List) {
          return List<Map<String, dynamic>>.from(data['pulses']);
        }
      } else {
        print('Failed getNearbyPulses: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('Error getNearbyPulses: $e');
    }
    return null;
  }

  // Public pulses listing (global) – relies on server including location
  Future<List<Map<String, dynamic>>?> getPublicPulses({int limit = 100}) async {
    try {
      final token = await _getAuthToken();
      final url = '$_baseUrl/pulses/public?limit=$limit';
      final resp =
          await _client.get(Uri.parse(url), headers: _getHeaders(token));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && data['pulses'] is List) {
          return List<Map<String, dynamic>>.from(data['pulses']);
        }
      } else {
        print('Failed getPublicPulses: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('Error getPublicPulses: $e');
    }
    return null;
  }

  // Profile-related methods
  Future<Map<String, dynamic>?> getUserProfile() async {
    // Ensure user exists in backend before fetching profile
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch profile: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/profile';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to fetch profile: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateUserProfile({
    String? displayName,
    String? bio,
    String? profileImageUrl,
    String? location,
    double? locationLatitude,
    double? locationLongitude,
    int? locationAccuracy,
    String? website,
    Map<String, dynamic>? socialLinks,
    List<String>? interests,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? gender,
    String? occupation,
    String? company,
    String? education,
    List<String>? languages,
    String? timezone,
    Map<String, dynamic>? preferences,
  }) async {
    // Ensure user exists in backend before updating profile
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot update profile: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/profile';
      final body = jsonEncode({
        if (displayName != null) 'displayName': displayName,
        if (bio != null) 'bio': bio,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        if (location != null) 'location': location,
        // Structured location fields (send nulls explicitly if clearing)
        if (locationLatitude != null) 'locationLatitude': locationLatitude,
        if (locationLongitude != null) 'locationLongitude': locationLongitude,
        if (locationAccuracy != null) 'locationAccuracy': locationAccuracy,
        if (website != null) 'website': website,
        if (socialLinks != null) 'socialLinks': socialLinks,
        if (interests != null) 'interests': interests,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
        if (gender != null) 'gender': gender,
        if (occupation != null) 'occupation': occupation,
        if (company != null) 'company': company,
        if (education != null) 'education': education,
        if (languages != null) 'languages': languages,
        if (timezone != null) 'timezone': timezone,
        if (preferences != null) 'preferences': preferences,
      });

      final response = await _client.put(
        Uri.parse(url),
        headers: _getHeaders(token),
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to update profile: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error updating profile: $e');
      return null;
    }
  }

  // Nearby users using structured location
  Future<List<Map<String, dynamic>>?> getNearbyUsers({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) return null;
      final url =
          '$_baseUrl/profile/nearby?lat=$latitude&lng=$longitude&radiusKm=$radiusKm';
      final response =
          await _client.get(Uri.parse(url), headers: _getHeaders(token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['users'] is List) {
          return List<Map<String, dynamic>>.from(data['users']);
        }
      } else {
        print('Nearby users failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error nearby users: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> searchUsers(String query) async {
    // Ensure user exists in backend before searching users
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot search users: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url =
          '$_baseUrl/profile/search?query=${Uri.encodeQueryComponent(query)}';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      } else {
        print(
            'Failed to search users: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error searching users: $e');
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getUserProfileById(String userId) async {
    // Ensure user exists in backend before fetching user profile
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch user profile: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/profile/$userId';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          // Attempt to fetch richer geolocation (geohash + structured) details
          try {
            final loc = await getUserLocationDetails(userId);
            if (loc != null) {
              data['locationDetails'] =
                  loc; // { coordinates, geohash, cityLevelGeohash, ... }
            }
          } catch (e) {
            print('Optional location details fetch failed: $e');
          }
          return data;
        }
        return null;
      } else {
        print(
            'Failed to fetch user profile: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserStats(String userId) async {
    // Ensure user exists in backend before fetching user stats
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch user stats: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/profile/$userId/stats';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to fetch user stats: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching user stats: $e');
      return null;
    }
  }

  // Follow/Unfollow functionality
  Future<bool> followUser(String userId) async {
    // Ensure user exists in backend before following user
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot follow user: User not registered in backend');
      return false;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return false;
      }

      final url = '$_baseUrl/profile/$userId/follow';
      final response = await _client.post(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print(
            'Failed to follow user: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error following user: $e');
      return false;
    }
  }

  Future<bool> unfollowUser(String userId) async {
    // Ensure user exists in backend before unfollowing user
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot unfollow user: User not registered in backend');
      return false;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return false;
      }

      final url = '$_baseUrl/profile/$userId/follow';
      final response = await _client.delete(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print(
            'Failed to unfollow user: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error unfollowing user: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> getUserFollowers(String userId) async {
    // Ensure user exists in backend before fetching followers
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch followers: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/profile/$userId/followers';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['followers'] is List) {
          return List<Map<String, dynamic>>.from(data['followers']);
        }
      } else {
        print(
            'Failed to fetch followers: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching followers: $e');
      return null;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getUserFollowing(String userId) async {
    // Ensure user exists in backend before fetching following
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch following: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/profile/$userId/following';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['following'] is List) {
          return List<Map<String, dynamic>>.from(data['following']);
        }
      } else {
        print(
            'Failed to fetch following: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching following: $e');
      return null;
    }
    return null;
  }

  Future<bool> isFollowingUser(String userId) async {
    // Ensure user exists in backend before checking follow status
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot check follow status: User not registered in backend');
      return false;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return false;
      }

      // Get current user's following list and check if target user is in it
      final currentUserId = currentUserUid;
      if (currentUserId.isEmpty) {
        print('No current user UID available');
        return false;
      }

      final following = await getUserFollowing(currentUserId);
      if (following != null) {
        return following.any((user) => user['id'] == userId);
      }
    } catch (e) {
      print('Error checking follow status: $e');
    }
    return false;
  }

  // Posts-related methods
  Future<Map<String, dynamic>?> createPost({
    required String content,
    String? imageUrl,
    bool isPublic = true,
  }) async {
    // Ensure user exists in backend before creating post
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot create post: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/posts';
      final body = jsonEncode({
        'content': content,
        'imageUrl': imageUrl,
        'isPublic': isPublic,
      });

      final response = await _client.post(
        Uri.parse(url),
        headers: _getHeaders(token),
        body: body,
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print(
            'Failed to create post: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error creating post: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getMyPosts() async {
    // Ensure user exists in backend before fetching posts
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch posts: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/posts/me';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      } else {
        print(
            'Failed to fetch posts: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching posts: $e');
      return null;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> getUserPosts(String userId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = '$_baseUrl/posts/user/$userId';
      final response = await _client.get(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      } else {
        print(
            'Failed to fetch user posts: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching user posts: $e');
      return null;
    }
    return null;
  }

  // Other-user pulses (hosted/joined) with pagination
  Future<List<Map<String, dynamic>>?> getHostedPulsesForUser(String userId,
      {int page = 0, int size = 12}) async {
    // Ensure user exists in backend before fetching
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch hosted pulses: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = Uri.parse('$_baseUrl/profile/$userId/pulses/hosted')
          .replace(queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      });
      final response = await _client.get(url, headers: _getHeaders(token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return List<Map<String, dynamic>>.from(data);
      } else {
        print(
            'Failed to fetch hosted pulses: ${response.statusCode} - ${response.body}');
        // fall through to client-side fallback below
      }
    } catch (e) {
      print('Error fetching hosted pulses: $e');
      // fall through to client-side fallback below
    }
    // Client-side fallback: fetch all pulses and filter by authorId
    try {
      final all = await getPulses();
      if (all == null) return null;
      final filtered = all.where((p) {
        try {
          final authorId = (p['author'] != null && p['author'] is Map)
              ? (p['author']['id'] as String?)
              : (p['authorId'] as String?);
          return authorId == userId;
        } catch (e) {
          return false;
        }
      }).toList();
      final start = (page * size).clamp(0, filtered.length);
      final end = ((page + 1) * size).clamp(0, filtered.length);
      return filtered.sublist(start, end);
    } catch (e) {
      print('Fallback error filtering hosted pulses: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getJoinedPulsesForUser(String userId,
      {int page = 0, int size = 12}) async {
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch joined pulses: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url = Uri.parse('$_baseUrl/profile/$userId/pulses/joined')
          .replace(queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      });
      final response = await _client.get(url, headers: _getHeaders(token));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return List<Map<String, dynamic>>.from(data);
      } else {
        print(
            'Failed to fetch joined pulses: ${response.statusCode} - ${response.body}');
        // fall through to client-side fallback below
      }
    } catch (e) {
      print('Error fetching joined pulses: $e');
      // fall through to client-side fallback below
    }
    // Client-side fallback: fetch all pulses and filter by participants containing userId (and not author)
    try {
      final all = await getPulses();
      if (all == null) return null;
      final filtered = all.where((p) {
        try {
          final participants =
              (p['participants'] as List<dynamic>?) ?? const [];
          final isParticipant = participants.any((pp) {
            if (pp is Map<String, dynamic>) {
              return pp['id'] == userId;
            }
            return false;
          });
          final authorId = (p['author'] != null && p['author'] is Map)
              ? (p['author']['id'] as String?)
              : (p['authorId'] as String?);
          final isAuthor = authorId == userId;
          return isParticipant && !isAuthor;
        } catch (e) {
          return false;
        }
      }).toList();
      final start = (page * size).clamp(0, filtered.length);
      final end = ((page + 1) * size).clamp(0, filtered.length);
      return filtered.sublist(start, end);
    } catch (e) {
      print('Fallback error filtering joined pulses: $e');
      return null;
    }
  }

  Future<bool> deletePost(String postId) async {
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot delete post: User not registered in backend');
      return false;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return false;
      }

      final url = '$_baseUrl/posts/$postId';
      final response = await _client.delete(
        Uri.parse(url),
        headers: _getHeaders(token),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print(
            'Failed to delete post: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error deleting post: $e');
      return false;
    }
  }

  // Notifications
  Future<List<Map<String, dynamic>>?> getNotifications(
      {int page = 0, int size = 20}) async {
    final userExists = await ensureUserExists();
    if (!userExists) {
      print('Cannot fetch notifications: User not registered in backend');
      return null;
    }

    try {
      final token = await _getAuthToken();
      if (token == null) {
        print('No authentication token available');
        return null;
      }

      final url =
          Uri.parse('$_baseUrl/notifications').replace(queryParameters: {
        'page': page.toString(),
        'size': size.toString(),
      });
      final response = await _client.get(url, headers: _getHeaders(token));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return List<Map<String, dynamic>>.from(data);
      } else {
        print(
            'Failed to fetch notifications: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching notifications: $e');
      return [];
    }
    return [];
  }

  Future<bool> markNotificationRead(String notificationId) async {
    final userExists = await ensureUserExists();
    if (!userExists) return false;
    try {
      final token = await _getAuthToken();
      if (token == null) return false;
      final url = '$_baseUrl/notifications/$notificationId/read';
      final response =
          await _client.post(Uri.parse(url), headers: _getHeaders(token));
      if (response.statusCode == 200) return true;
      print(
          'Failed to mark notification read: ${response.statusCode} - ${response.body}');
    } catch (e) {
      print('Error marking notification read: $e');
    }
    return false;
  }

  Future<bool> markAllNotificationsRead() async {
    final userExists = await ensureUserExists();
    if (!userExists) return false;
    try {
      final token = await _getAuthToken();
      if (token == null) return false;
      final url = '$_baseUrl/notifications/mark-all-read';
      final response =
          await _client.post(Uri.parse(url), headers: _getHeaders(token));
      if (response.statusCode == 200) return true;
      print(
          'Failed to mark all notifications read: ${response.statusCode} - ${response.body}');
    } catch (e) {
      print('Error marking all notifications read: $e');
    }
    return false;
  }

  // Conversation invitation actions
  Future<bool> respondToInvitation(String invitationId, bool accept) async {
    try {
      final ensured = await ensureUserExists();
      if (!ensured) return false;
      final token = await _getAuthToken();
      if (token == null) return false;
      final url = '$_baseUrl/invitations/$invitationId/respond';
      final resp = await _client.post(Uri.parse(url),
          headers: _getHeaders(token),
          body: jsonEncode({'action': accept ? 'ACCEPT' : 'DECLINE'}));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return true;
      }
      print('respondToInvitation failed: ${resp.statusCode} - ${resp.body}');
    } catch (e) {
      print('Error respondToInvitation: $e');
    }
    return false;
  }

  Future<bool> acceptInvitation(String invitationId) =>
      respondToInvitation(invitationId, true);
  Future<bool> declineInvitation(String invitationId) =>
      respondToInvitation(invitationId, false);

  // --- Geolocation / Geohash related additions ---

  // Fetch detailed location info (structured coordinates + geohash variants) for a user
  Future<Map<String, dynamic>?> getUserLocationDetails(String userId) async {
    final userExists = await ensureUserExists();
    if (!userExists) return null;
    try {
      final token = await _getAuthToken();
      if (token == null) return null;
      final url = '$_baseUrl/profile/location/details/$userId';
      final resp =
          await _client.get(Uri.parse(url), headers: _getHeaders(token));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) return data;
      } else {
        print(
            'Failed getUserLocationDetails($userId): ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('Error getUserLocationDetails: $e');
    }
    return null;
  }

  // Convenience for current user's location details (requires their id which we may derive from profile fetch elsewhere)
  Future<Map<String, dynamic>?> getMyLocationDetails(String myUserId) async {
    return getUserLocationDetails(myUserId);
  }

  // Wrapper to get nearby users (already geohash optimized) returning enriched list with distance if available.
  // Provided for semantic clarity when calling from UI widgets wanting explicit geohash semantics.
  Future<List<Map<String, dynamic>>?> getNearbyUsersGeohash({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
  }) =>
      getNearbyUsers(
          latitude: latitude, longitude: longitude, radiusKm: radiusKm);

  // Combined map overview (public pulses + users) to reduce round trips
  Future<Map<String, dynamic>?> getMapOverview({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
    bool includePulses = true,
    bool includeUsers = true,
  }) async {
    try {
      final token = await _getAuthToken();
      final layers =
          [if (includePulses) 'events', if (includeUsers) 'people'].join(',');
      final url =
          '$_baseUrl/map/overview?lat=$latitude&lng=$longitude&radiusKm=$radiusKm&layers=$layers';
      final resp =
          await _client.get(Uri.parse(url), headers: _getHeaders(token));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) return data;
      } else {
        print('getMapOverview failed: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      print('Error getMapOverview: $e');
    }
    return null;
  }
}
