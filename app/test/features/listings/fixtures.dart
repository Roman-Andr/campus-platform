import '../../helpers/fake_api.dart';

Map<String, Object?> listingJson({
  String id = 'listing-1',
  String? author,
  String status = 'active',
}) => {
  'id': id,
  'author_id': author ?? userJson['id'],
  'author_name': 'Ivan Ivanov',
  'category_id': 'category-items',
  'hidden_reason': null,
  'kind': 'giveaway',
  'title': 'A desk',
  'description': 'Collect on campus',
  'visibility': 'city',
  'audience': 'students',
  'city_id': 'city-moscow',
  'dormitory_id': null,
  'faculty_id': null,
  'status': status,
  'version': 1,
  'created_at': '2026-11-14T00:00:00Z',
  'expires_at': status == 'draft' ? null : '2026-12-14T00:00:00Z',
};
Map<String, Object?> pageJson(List<Object?> items, {String? next}) => {
  'items': items,
  'next_page': next,
};
