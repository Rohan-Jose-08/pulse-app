import '/components/joinpulse_widget.dart';
import '/components/navbar_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'dart:ui';
import 'search_widget.dart' show SearchWidget;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class SearchModel extends FlutterFlowModel<SearchWidget> {
  ///  State fields for stateful widgets in this page.

  // State field(s) for TextField widget.
  FocusNode? textFieldFocusNode;
  TextEditingController? textController;
  String? Function(BuildContext, String?)? textControllerValidator;
  
  // Model for Navbar component.
  late NavbarModel navbarModel;
  
  // Additional state for enhanced search
  List<String> searchHistory = [];
  bool isVoiceSearchEnabled = false;
  DateTime? lastSearchTime;
  
  // Filter state
  Map<String, dynamic> activeFilters = {
    'distance': 10.0, // km
    'dateRange': null,
    'sortBy': 'relevance', // relevance, date, distance
  };

  @override
  void initState(BuildContext context) {
    navbarModel = createModel(context, () => NavbarModel());
  }

  @override
  void dispose() {
    textFieldFocusNode?.dispose();
    textController?.dispose();

    navbarModel.dispose();
  }
  
  // Helper methods
  void addToSearchHistory(String query) {
    if (query.isNotEmpty && !searchHistory.contains(query)) {
      searchHistory.insert(0, query);
      if (searchHistory.length > 10) {
        searchHistory.removeLast();
      }
    }
  }
  
  void clearSearchHistory() {
    searchHistory.clear();
  }
  
  void updateFilter(String key, dynamic value) {
    activeFilters[key] = value;
  }
  
  void resetFilters() {
    activeFilters = {
      'distance': 10.0,
      'dateRange': null,
      'sortBy': 'relevance',
    };
  }
}
