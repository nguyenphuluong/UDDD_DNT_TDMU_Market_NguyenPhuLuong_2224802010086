import 'dart:convert';
import 'dart:io';

class ApiClient {
  ApiClient(this.baseUrl);

  String baseUrl;
  String? token;

  Future<dynamic> request(String method, String path,
      {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, uri);
      req.headers.contentType = ContentType.json;
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      final data = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(data['error'] ?? 'Lỗi server');
      }
      return data;
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await request('POST', '/api/auth/login',
        body: {'email': email, 'password': password});
    token = data['token'];
    return Map<String, dynamic>.from(data['user']);
  }

  Future<Map<String, dynamic>> requestRegisterCode({
    required String name,
    required String email,
    required String studentId,
    required String major,
    required String password,
  }) async {
    final data =
        await request('POST', '/api/auth/register/request-code', body: {
      'name': name,
      'email': email,
      'studentId': studentId,
      'major': major,
      'password': password,
    });
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> verifyRegister(String email, String code) async {
    final data = await request('POST', '/api/auth/register/verify',
        body: {'email': email, 'code': code});
    token = data['token'];
    return Map<String, dynamic>.from(data['user']);
  }

  Future<Map<String, dynamic>> requestPasswordCode(String email) async {
    final data = await request('POST', '/api/auth/forgot/request-code',
        body: {'email': email});
    return Map<String, dynamic>.from(data);
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) {
    return request('POST', '/api/auth/forgot/reset',
        body: {'email': email, 'code': code, 'password': password});
  }

  Future<List<Map<String, dynamic>>> products(
      {String q = '', String category = 'all'}) async {
    final params = Uri(queryParameters: {
      'q': q,
      'category': category,
      'status': 'approved'
    }).query;
    final data = await request('GET', '/api/products?$params');
    return List<Map<String, dynamic>>.from(data['products']);
  }

  Future<List<Map<String, dynamic>>> adminProducts(
      {String status = 'all'}) async {
    final params = Uri(queryParameters: {'status': status}).query;
    final data = await request('GET', '/api/products?$params');
    return List<Map<String, dynamic>>.from(data['products']);
  }

  Future<Map<String, dynamic>> product(String id) async {
    final data = await request('GET', '/api/products/$id');
    return Map<String, dynamic>.from(data['product']);
  }

  Future<List<String>> categories() async {
    final data = await request('GET', '/api/categories');
    return List<String>.from(data['categories']);
  }

  Future<String> uploadImage(String dataUrl) async {
    final data =
        await request('POST', '/api/uploads', body: {'dataUrl': dataUrl});
    return '${data['imageUrl']}';
  }

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> body) async {
    final data = await request('PATCH', '/api/me', body: body);
    return Map<String, dynamic>.from(data['user']);
  }

  Future<List<Map<String, dynamic>>> myProducts() async {
    final data = await request('GET', '/api/products?mine=true&status=all');
    return List<Map<String, dynamic>>.from(data['products']);
  }

  Future<void> createProduct(Map<String, dynamic> body) =>
      request('POST', '/api/products', body: body);
  Future<void> updateProduct(String id, Map<String, dynamic> body) =>
      request('PATCH', '/api/products/$id', body: body);
  Future<void> deleteProduct(String id) =>
      request('DELETE', '/api/products/$id');
  Future<void> addFavorite(String productId) =>
      request('POST', '/api/products/$productId/favorite');
  Future<void> addCart(String productId) => request('POST', '/api/cart',
      body: {'productId': productId, 'quantity': 1});

  Future<Map<String, dynamic>> cart() async {
    return Map<String, dynamic>.from(await request('GET', '/api/cart'));
  }

  Future<void> removeCart(String productId) =>
      request('DELETE', '/api/cart/$productId');

  Future<Map<String, dynamic>> checkout(String method) async {
    final data = await request('POST', '/api/payments/checkout',
        body: {'method': method});
    return Map<String, dynamic>.from(data['order']);
  }

  Future<List<Map<String, dynamic>>> chats() async {
    final data = await request('GET', '/api/chats');
    return List<Map<String, dynamic>>.from(data['chats']);
  }

  Future<Map<String, dynamic>> startChat(String productId) async {
    final data =
        await request('POST', '/api/chats', body: {'productId': productId});
    return Map<String, dynamic>.from(data['chat']);
  }

  Future<List<Map<String, dynamic>>> messages(String chatId) async {
    final data = await request('GET', '/api/chats/$chatId/messages');
    return List<Map<String, dynamic>>.from(data['messages']);
  }

  Future<void> markChatRead(String chatId) {
    return request('PATCH', '/api/chats/$chatId/messages');
  }

  Stream<Map<String, dynamic>> chatStream(String chatId) async* {
    final uri = Uri.parse('$baseUrl/api/chats/$chatId/stream');
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Không thể kết nối chat trực tuyến');
      }

      var event = '';
      var data = '';
      await for (final line
          in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (event == 'message' && data.isNotEmpty) {
            yield Map<String, dynamic>.from(jsonDecode(data));
          }
          event = '';
          data = '';
          continue;
        }
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data += line.substring(5).trim();
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> sendMessage(String chatId, String text,
      {String? imageUrl}) async {
    final body = <String, dynamic>{'text': text};
    if (imageUrl != null && imageUrl.isNotEmpty) body['imageUrl'] = imageUrl;
    final data =
        await request('POST', '/api/chats/$chatId/messages', body: body);
    return Map<String, dynamic>.from(data['message']);
  }

  Future<Map<String, dynamic>> notificationSummary() async {
    final data = await request('GET', '/api/notifications');
    return {
      'notifications': List<Map<String, dynamic>>.from(data['notifications']),
      'unread': data['unread'] ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> notifications() async {
    final data = await notificationSummary();
    return List<Map<String, dynamic>>.from(data['notifications']);
  }

  Future<void> markNotificationsRead() =>
      request('PATCH', '/api/notifications/read');

  Future<Map<String, dynamic>> adminStats() async {
    final data = await request('GET', '/api/admin/stats');
    return Map<String, dynamic>.from(data['stats']);
  }

  Future<Map<String, dynamic>> adminDetail(String type) async {
    final data = await request('GET', '/api/admin/details/$type');
    return Map<String, dynamic>.from(data);
  }

  Future<void> moderateProduct(String productId, String status) =>
      request('PATCH', '/api/admin/products/$productId',
          body: {'status': status});

  Future<void> adminDeleteProduct(String productId) =>
      request('DELETE', '/api/admin/products/$productId');

  Future<List<Map<String, dynamic>>> adminUsers() async {
    final data = await request('GET', '/api/admin/users');
    return List<Map<String, dynamic>>.from(data['users']);
  }

  Future<void> updateUserStatus(String userId, String status) =>
      request('PATCH', '/api/admin/users/$userId', body: {'status': status});

  Future<void> adminDeleteUser(String userId) =>
      request('DELETE', '/api/admin/users/$userId');
}
