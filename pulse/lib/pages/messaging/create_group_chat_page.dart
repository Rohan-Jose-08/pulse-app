import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/firebase_auth/auth_util.dart';
import '../../backend/api_service.dart';
import '../../flutter_flow/flutter_flow_theme.dart';
import '../../flutter_flow/flutter_flow_widgets.dart';

/// Page for creating a new group chat
/// Allows user to set group name, description, avatar, and select initial members
class CreateGroupChatPage extends ConsumerStatefulWidget {
  const CreateGroupChatPage({super.key});

  @override
  ConsumerState<CreateGroupChatPage> createState() =>
      _CreateGroupChatPageState();
}

class _CreateGroupChatPageState extends ConsumerState<CreateGroupChatPage> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();

  final Set<String> _selectedUserIds = {};
  List<Map<String, dynamic>> _allFollowers = [];
  List<Map<String, dynamic>> _filteredFollowers = [];
  bool _isLoadingFollowers = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    setState(() => _isLoadingFollowers = true);

    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        print('No user ID available');
        if (mounted) {
          setState(() => _isLoadingFollowers = false);
        }
        return;
      }

      // Load both followers and following
      final followers = await ApiService.instance.getUserFollowers(userId);
      final following = await ApiService.instance.getUserFollowing(userId);

      if (mounted) {
        // Combine followers and following, remove duplicates
        final allUsers = <String, Map<String, dynamic>>{};

        if (followers != null) {
          for (var user in followers) {
            final id = user['id']?.toString();
            if (id != null && id != userId) {
              allUsers[id] = user;
            }
          }
        }

        if (following != null) {
          for (var user in following) {
            final id = user['id']?.toString();
            if (id != null && id != userId) {
              allUsers[id] = user;
            }
          }
        }

        setState(() {
          _allFollowers = allUsers.values.toList();
          _filteredFollowers = _allFollowers;
          _isLoadingFollowers = false;
        });
      }
    } catch (e) {
      print('Error loading followers: $e');
      if (mounted) {
        setState(() => _isLoadingFollowers = false);
      }
    }
  }

  void _filterFollowers(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredFollowers = _allFollowers;
      });
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredFollowers = _allFollowers.where((user) {
        final name = (user['displayName']?.toString() ?? '').toLowerCase();
        final email = (user['email']?.toString() ?? '').toLowerCase();
        return name.contains(lowerQuery) || email.contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _createGroupChat() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final result = await ApiService.instance.createGroupConversation(
        name: name,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        initialParticipantIds:
            _selectedUserIds.isNotEmpty ? _selectedUserIds.toList() : null,
      );

      if (result != null && mounted) {
        // Navigate back with the created group
        Navigator.pop(context, result);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create group chat')),
        );
      }
    } catch (e) {
      print('Error creating group chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primary,
        title: Text(
          'Create Group Chat',
          style: theme.headlineMedium.override(
            fontFamily: 'Outfit',
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isCreating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: theme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Creating group chat...',
                    style: theme.bodyMedium,
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group name input
                  Text(
                    'Group Name *',
                    style: theme.labelLarge.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Enter group name',
                      filled: true,
                      fillColor: theme.secondaryBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    maxLength: 50,
                  ),
                  const SizedBox(height: 16),

                  // Group description input
                  Text(
                    'Description (Optional)',
                    style: theme.labelLarge.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      hintText: 'What is this group about?',
                      filled: true,
                      fillColor: theme.secondaryBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    maxLines: 3,
                    maxLength: 200,
                  ),
                  const SizedBox(height: 24),

                  // Selected members section
                  if (_selectedUserIds.isNotEmpty) ...[
                    Text(
                      'Selected Members (${_selectedUserIds.length})',
                      style: theme.labelLarge.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _allFollowers
                          .where(
                              (user) => _selectedUserIds.contains(user['id']))
                          .map((user) => Chip(
                                avatar: CircleAvatar(
                                  backgroundImage: user['profileImageUrl'] !=
                                          null
                                      ? NetworkImage(user['profileImageUrl'])
                                      : null,
                                  child: user['profileImageUrl'] == null
                                      ? Text((user['displayName']?.toString() ??
                                              '?')[0]
                                          .toUpperCase())
                                      : null,
                                ),
                                label: Text(user['displayName'] ?? 'Unknown'),
                                onDeleted: () {
                                  setState(() {
                                    _selectedUserIds.remove(user['id']);
                                  });
                                },
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Followers list section
                  Text(
                    'Add Members from Your Network',
                    style: theme.labelLarge.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Filter by name or email',
                      filled: true,
                      fillColor: theme.secondaryBackground,
                      prefixIcon:
                          Icon(Icons.filter_list, color: theme.secondaryText),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      _filterFollowers(value);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Followers list
                  if (_isLoadingFollowers)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_allFollowers.isEmpty)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: theme.secondaryText,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No followers or following yet',
                              style: theme.bodyLarge.override(
                                color: theme.secondaryText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Connect with people to add them to groups',
                              style: theme.bodySmall.override(
                                color: theme.secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_filteredFollowers.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: theme.secondaryBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredFollowers.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: theme.alternate,
                        ),
                        itemBuilder: (context, index) {
                          final user = _filteredFollowers[index];
                          final userId = user['id'] as String;
                          final isSelected = _selectedUserIds.contains(userId);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: user['profileImageUrl'] != null
                                  ? NetworkImage(user['profileImageUrl'])
                                  : null,
                              child: user['profileImageUrl'] == null
                                  ? Text((user['displayName']?.toString() ??
                                          '?')[0]
                                      .toUpperCase())
                                  : null,
                            ),
                            title: Text(
                              user['displayName'] ?? 'Unknown',
                              style: theme.bodyLarge,
                            ),
                            subtitle: user['email'] != null
                                ? Text(
                                    user['email'],
                                    style: theme.bodySmall,
                                  )
                                : null,
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: theme.primary)
                                : Icon(Icons.add_circle_outline,
                                    color: theme.secondaryText),
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedUserIds.remove(userId);
                                } else {
                                  _selectedUserIds.add(userId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Create button
                  FFButtonWidget(
                    onPressed: _isCreating ? null : _createGroupChat,
                    text: 'Create Group Chat',
                    options: FFButtonOptions(
                      width: double.infinity,
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      iconPadding: EdgeInsets.zero,
                      color: theme.primary,
                      textStyle: theme.titleSmall.override(
                        fontFamily: 'Readex Pro',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      elevation: 2,
                      borderSide: const BorderSide(
                        color: Colors.transparent,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
