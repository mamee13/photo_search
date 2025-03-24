import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

class SearchProvider extends ChangeNotifier {
  File? selectedImage;
  List<String> recentSearches = [];
  List<String> searchResults = [];
  bool isLoading = false;
  String? error;

  void setSelectedImage(File image) {
    selectedImage = image;
    notifyListeners();
  }

  void setLoading(bool loading) {
    isLoading = loading;
    notifyListeners();
  }

  Future<void> addToRecentSearches(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    recentSearches.insert(0, imagePath);
    if (recentSearches.length > 5) {
      recentSearches.removeLast();
    }
    await prefs.setStringList('recent_searches', recentSearches);
    notifyListeners();
  }

  Future<void> loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    recentSearches = prefs.getStringList('recent_searches') ?? [];
    notifyListeners();
  }

  static const String unsplashApiKey = '00kThq_sB6HtIQ5g43W-8rr6I88mLg055b5YnNMebfg';
  static const String geminiApiKey = 'AIzaSyAPPNgvusxR29yA6G8ZDR3ah_aAowypFp8';

  Future<void> searchSimilarImages() async {
    if (selectedImage == null) return;

    try {
      setLoading(true);
      error = null;
      
      final imageBytes = await selectedImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      
      // First, get image description from Gemini
      final geminiResponse = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1/models/gemini-pro-vision:generateContent'),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': geminiApiKey,
        },
        body: jsonEncode({
          'contents': [{
            'parts': [
              {'text': 'Describe this image in a few keywords that could be used for image search'},
              {
                'inlineData': {
                  'mimeType': 'image/jpeg',
                  'data': base64Image
                }
              }
            ]
          }],
          'generationConfig': {
            'temperature': 0.4,
            'topK': 32,
            'topP': 1,
            'maxOutputTokens': 2048,
          },
        }),
      );

      if (geminiResponse.statusCode == 200) {
        final geminiData = json.decode(geminiResponse.body); // Fixed: decode response body instead of status code
        final description = geminiData['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
        
        print('Gemini description: $description'); // Added for debugging

        // Use description to search Unsplash
        final unsplashResponse = await http.get(
          Uri.parse('https://api.unsplash.com/search/photos')
            .replace(queryParameters: {
              'query': description,
              'per_page': '10',
            }),
          headers: {
            'Authorization': 'Client-ID $unsplashApiKey'
          },
        );

        print('Unsplash status code: ${unsplashResponse.statusCode}'); // Added for debugging

        if (unsplashResponse.statusCode == 200) {
          final unsplashData = json.decode(unsplashResponse.body);
          searchResults = (unsplashData['results'] as List)
              .map((photo) => photo['urls']['regular'] as String)
              .toList();
          
          print('Found ${searchResults.length} images'); // Added for debugging
          
          if (searchResults.isEmpty) {
            error = 'No similar images found';
          }
        } else {
          error = 'Failed to fetch images from Unsplash: ${unsplashResponse.body}';
          searchResults = [];
        }
      } else {
        error = 'Failed to analyze image: ${geminiResponse.body}';
        searchResults = [];
      }
    } catch (e) {
      error = e.toString();
      searchResults = [];
    } finally {
      setLoading(false);
    }
    notifyListeners();
  }
}