import '../mpv/mpv.dart';

import '../models/plex_media_info.dart';
import '../models/plex_metadata.dart';
import '../models/plex_user_profile.dart';
import '../utils/app_logger.dart';
import '../utils/language_codes.dart';

/// 轨道选择的优先级
enum TrackSelectionPriority {
  navigation, // 优先级 1：用户从上一集开始的手动选择
  plexSelected, // 优先级 2：Plex 选择的轨道
  perMedia, // 优先级 3：针对该媒体的语言偏好
  profile, // 优先级 4：用户个人资料偏好
  defaultTrack, // 优先级 5：默认轨道或第一个轨道
  off, // 优先级 6：关闭字幕 (仅限字幕)
}

/// 轨道选择结果，包含所选轨道以及使用的优先级
class TrackSelectionResult<T> {
  final T track;
  final TrackSelectionPriority priority;

  TrackSelectionResult(this.track, this.priority);
}

/// 用于根据偏好、用户个人资料和针对媒体的设置选择并应用音频和字幕轨道的服务。
class TrackSelectionService {
  final Player player;
  final PlexUserProfile? profileSettings;
  final PlexMetadata metadata;
  final PlexMediaInfo? plexMediaInfo;

  TrackSelectionService({required this.player, this.profileSettings, required this.metadata, this.plexMediaInfo});

  /// 从用户个人资料构建首选语言列表
  List<String> _buildPreferredLanguages(PlexUserProfile profile, {required bool isAudio}) {
    final primary = isAudio ? profile.defaultAudioLanguage : profile.defaultSubtitleLanguage;
    final list = isAudio ? profile.defaultAudioLanguages : profile.defaultSubtitleLanguages;

    final result = <String>[];
    if (primary != null && primary.isNotEmpty) {
      result.add(primary);
    }
    if (list != null) {
      result.addAll(list);
    }
    return result;
  }

  /// 通过首选语言查找轨道，支持变体查找和日志记录
  T? _findTrackByPreferredLanguage<T>(
    List<T> tracks,
    String preferredLanguage,
    String? Function(T) getLanguage,
    String Function(T) getDescription,
    String trackType,
  ) {
    final languageVariations = LanguageCodes.getVariations(preferredLanguage);
    return _findTrackByLanguageVariations<T>(
      tracks,
      preferredLanguage,
      languageVariations,
      getLanguage,
      getDescription,
      trackType,
    );
  }

  /// 对轨道应用过滤器，如果过滤器产生空结果则回退到原始列表
  List<T> _applyFilterWithFallback<T>(List<T> tracks, List<T> Function(List<T>) filter, String filterDescription) {
    final filtered = filter(tracks);
    return filtered.isNotEmpty ? filtered : tracks;
  }

  /// 音频和字幕轨道的通用轨道匹配
  /// 根据层级标准返回最佳匹配轨道：
  /// 1. 完全匹配 (id + 标题 + 语言)
  /// 2. 部分匹配 (标题 + 语言)
  /// 3. 仅语言匹配
  T? findBestTrackMatch<T>(
    List<T> availableTracks,
    T preferred,
    String Function(T) getId,
    String? Function(T) getTitle,
    String? Function(T) getLanguage,
  ) {
    if (availableTracks.isEmpty) return null;

    // 过滤掉 auto 和 no 轨道
    final validTracks = availableTracks.where((t) => getId(t) != 'auto' && getId(t) != 'no').toList();
    if (validTracks.isEmpty) return null;

    final preferredId = getId(preferred);
    final preferredTitle = getTitle(preferred);
    final preferredLanguage = getLanguage(preferred);

    // 尝试匹配：id、标题和语言
    for (var track in validTracks) {
      if (getId(track) == preferredId && getTitle(track) == preferredTitle && getLanguage(track) == preferredLanguage) {
        return track;
      }
    }

    // 尝试匹配：标题和语言
    for (var track in validTracks) {
      if (getTitle(track) == preferredTitle && getLanguage(track) == preferredLanguage) {
        return track;
      }
    }

    // 尝试匹配：仅语言
    for (var track in validTracks) {
      if (getLanguage(track) == preferredLanguage) {
        return track;
      }
    }

    return null;
  }

  AudioTrack? findBestAudioMatch(List<AudioTrack> availableTracks, AudioTrack preferred) {
    return findBestTrackMatch<AudioTrack>(availableTracks, preferred, (t) => t.id, (t) => t.title, (t) => t.language);
  }

  AudioTrack? findAudioTrackByProfile(List<AudioTrack> availableTracks, PlexUserProfile profile) {
    if (availableTracks.isEmpty || !profile.autoSelectAudio) return null;

    final preferredLanguages = _buildPreferredLanguages(profile, isAudio: true);
    if (preferredLanguages.isEmpty) return null;

    for (final preferredLanguage in preferredLanguages) {
      final match = _findTrackByPreferredLanguage<AudioTrack>(
        availableTracks,
        preferredLanguage,
        (t) => t.language,
        (t) => t.title ?? '轨道 ${t.id}',
        '音频轨道',
      );
      if (match != null) return match;
    }

    return null;
  }

  SubtitleTrack? findBestSubtitleMatch(List<SubtitleTrack> availableTracks, SubtitleTrack preferred) {
    // 处理特殊的“无字幕”情况
    if (preferred.id == 'no') {
      return SubtitleTrack.off;
    }

    return findBestTrackMatch<SubtitleTrack>(
      availableTracks,
      preferred,
      (t) => t.id,
      (t) => t.title,
      (t) => t.language,
    );
  }

  SubtitleTrack? findSubtitleTrackByProfile(
    List<SubtitleTrack> availableTracks,
    PlexUserProfile profile, {
    AudioTrack? selectedAudioTrack,
  }) {
    if (availableTracks.isEmpty) return null;

    // 模式 0：手动选择 - 返回 OFF
    if (profile.autoSelectSubtitle == 0) return SubtitleTrack.off;

    // 模式 1：在外语音频时显示
    if (profile.autoSelectSubtitle == 1) {
      if (selectedAudioTrack != null && profile.defaultSubtitleLanguage != null) {
        final audioLang = selectedAudioTrack.language?.toLowerCase();
        final prefLang = profile.defaultSubtitleLanguage!.toLowerCase();
        final languageVariations = LanguageCodes.getVariations(prefLang);

        // 如果音频匹配首选语言，则不需要字幕
        if (audioLang != null && languageVariations.contains(audioLang)) {
          return SubtitleTrack.off;
        }
      }
    }

    // 模式 2：始终启用 (或者从模式 1 继续，如果是外语音频)
    final preferredLanguages = _buildPreferredLanguages(profile, isAudio: false);
    if (preferredLanguages.isEmpty) return null;

    // 应用过滤，如果过滤产生空结果则回退到原始轨道列表
    var candidateTracks = availableTracks;
    candidateTracks = filterSubtitlesBySDH(candidateTracks, profile.defaultSubtitleAccessibility);
    candidateTracks = filterSubtitlesByForced(candidateTracks, profile.defaultSubtitleForced);
    candidateTracks = _applyFilterWithFallback(availableTracks, (_) => candidateTracks, '严格过滤');

    for (final preferredLanguage in preferredLanguages) {
      final match = _findTrackByPreferredLanguage<SubtitleTrack>(
        candidateTracks,
        preferredLanguage,
        (t) => t.language,
        (t) => t.title ?? '轨道 ${t.id}',
        '字幕',
      );
      if (match != null) return match;
    }

    return null;
  }

  /// 根据 SDH (听障字幕) 偏好过滤字幕轨道
  ///
  /// 值：
  /// - 0：首选非 SDH 字幕
  /// - 1：首选 SDH 字幕
  /// - 2：仅显示 SDH 字幕
  /// - 3：仅显示非 SDH 字幕
  List<SubtitleTrack> filterSubtitlesBySDH(List<SubtitleTrack> tracks, int preference) {
    if (preference == 0 || preference == 1) {
      final preferSDH = preference == 1;
      final preferred = tracks.where((t) => isSDH(t) == preferSDH).toList();
      return preferred.isNotEmpty ? preferred : tracks;
    } else if (preference == 2) {
      return tracks.where((t) => isSDH(t)).toList();
    } else if (preference == 3) {
      return tracks.where((t) => !isSDH(t)).toList();
    }
    return tracks;
  }

  /// 根据强制字幕偏好过滤字幕轨道
  ///
  /// 值：
  /// - 0：首选非强制字幕
  /// - 1：首选强制字幕
  /// - 2：仅显示强制字幕
  /// - 3：仅显示非强制字幕
  List<SubtitleTrack> filterSubtitlesByForced(List<SubtitleTrack> tracks, int preference) {
    if (preference == 0 || preference == 1) {
      final preferForced = preference == 1;
      final preferred = tracks.where((t) => isForced(t) == preferForced).toList();
      return preferred.isNotEmpty ? preferred : tracks;
    } else if (preference == 2) {
      return tracks.where((t) => isForced(t)).toList();
    } else if (preference == 3) {
      return tracks.where((t) => !isForced(t)).toList();
    }
    return tracks;
  }

  /// 检查字幕轨道是否为 SDH (听障字幕)
  ///
  /// 由于 mpv 可能无法直接公开此信息，我们从标题中推断
  bool isSDH(SubtitleTrack track) {
    final title = track.title?.toLowerCase() ?? '';

    // 寻找常见的 SDH 标识符
    return title.contains('sdh') ||
        title.contains('cc') ||
        title.contains('hearing impaired') ||
        title.contains('deaf');
  }

  /// 检查字幕轨道是否为强制字幕
  bool isForced(SubtitleTrack track) {
    final title = track.title?.toLowerCase() ?? '';
    return title.contains('forced');
  }

  /// 从轨道列表中查找匹配首选语言的轨道
  /// 返回第一个其语言匹配首选语言任何变体的轨道
  T? _findTrackByLanguageVariations<T>(
    List<T> tracks,
    String preferredLanguage,
    List<String> languageVariations,
    String? Function(T) getLanguage,
    String Function(T) getTrackDescription,
    String trackType,
  ) {
    for (var track in tracks) {
      final trackLang = getLanguage(track)?.toLowerCase();
      if (trackLang != null && languageVariations.any((lang) => trackLang.startsWith(lang))) {
        return track;
      }
    }
    return null;
  }

  /// 检查轨道语言是否匹配首选语言
  ///
  /// 处理 2 位 (ISO 639-1) 和 3 位 (ISO 639-2) 代码
  /// 还处理文献变体和区域代码 (例如 "en-US")
  bool languageMatches(String? trackLanguage, String? preferredLanguage) {
    if (trackLanguage == null || preferredLanguage == null) {
      return false;
    }

    final track = trackLanguage.toLowerCase();
    final preferred = preferredLanguage.toLowerCase();

    // 直接匹配
    if (track == preferred) return true;

    // 提取基础语言代码 (处理区域代码，如 "en-US")
    final trackBase = track.split('-').first;
    final preferredBase = preferred.split('-').first;

    if (trackBase == preferredBase) return true;

    // 获取首选语言的所有变体 (例如 "en" -> ["en", "eng"])
    final variations = LanguageCodes.getVariations(preferredBase);

    // 检查轨道的辅助代码是否匹配任何变体
    return variations.contains(trackBase);
  }

  /// 根据优先级选择最佳音频轨道：
  /// 优先级 1：来自导航的首选轨道
  /// 优先级 2：来自媒体信息的 Plex 选择轨道
  /// 优先级 3：针对该媒体的语言偏好
  /// 优先级 4：用户个人资料偏好
  /// 优先级 5：默认轨道或第一个轨道
  TrackSelectionResult<AudioTrack>? selectAudioTrack(
    List<AudioTrack> availableTracks,
    AudioTrack? preferredAudioTrack,
  ) {
    if (availableTracks.isEmpty) return null;

    AudioTrack? trackToSelect;

    // 优先级 1：尝试匹配来自导航的首选轨道
    if (preferredAudioTrack != null) {
      trackToSelect = findBestAudioMatch(availableTracks, preferredAudioTrack);
      if (trackToSelect != null) {
        return TrackSelectionResult(trackToSelect, TrackSelectionPriority.navigation);
      }
    }

    // 优先级 2：检查来自媒体信息的 Plex 选择轨道
    if (plexMediaInfo != null) {
      final plexAudioTracks = plexMediaInfo!.audioTracks;
      final plexSelectedIndex = plexAudioTracks.indexWhere((t) => t.selected);
      if (plexSelectedIndex >= 0 && plexSelectedIndex < availableTracks.length) {
        return TrackSelectionResult(availableTracks[plexSelectedIndex], TrackSelectionPriority.plexSelected);
      }
    }

    // 优先级 3：尝试针对该媒体的语言偏好
    if (metadata.audioLanguage != null) {
      final matchedTrack = availableTracks.firstWhere(
        (track) => languageMatches(track.language, metadata.audioLanguage),
        orElse: () => availableTracks.first,
      );
      if (languageMatches(matchedTrack.language, metadata.audioLanguage)) {
        return TrackSelectionResult(matchedTrack, TrackSelectionPriority.perMedia);
      }
    }

    // 优先级 4：尝试用户个人资料偏好
    if (profileSettings != null) {
      trackToSelect = findAudioTrackByProfile(availableTracks, profileSettings!);
      if (trackToSelect != null) {
        return TrackSelectionResult(trackToSelect, TrackSelectionPriority.profile);
      }
    }

    // 优先级 5：使用默认轨道或第一个轨道
    trackToSelect = availableTracks.firstWhere((t) => t.isDefault == true, orElse: () => availableTracks.first);
    return TrackSelectionResult(trackToSelect, TrackSelectionPriority.defaultTrack);
  }

  /// 根据优先级选择最佳字幕轨道：
  /// 优先级 1：来自导航的首选轨道
  /// 优先级 2：来自媒体信息的 Plex 选择轨道
  /// 优先级 3：针对该媒体的语言偏好
  /// 优先级 4：用户个人资料偏好
  /// 优先级 5：默认轨道
  /// 优先级 6：关闭
  TrackSelectionResult<SubtitleTrack> selectSubtitleTrack(
    List<SubtitleTrack> availableTracks,
    SubtitleTrack? preferredSubtitleTrack,
    AudioTrack? selectedAudioTrack,
  ) {
    SubtitleTrack? subtitleToSelect;

    // 优先级 1：尝试来自导航的首选轨道
    if (preferredSubtitleTrack != null) {
      if (preferredSubtitleTrack.id == 'no') {
        return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.navigation);
      } else if (availableTracks.isNotEmpty) {
        subtitleToSelect = findBestSubtitleMatch(availableTracks, preferredSubtitleTrack);
        if (subtitleToSelect != null) {
          return TrackSelectionResult(subtitleToSelect, TrackSelectionPriority.navigation);
        }
      }
    }

    // 优先级 2：检查来自媒体信息的 Plex 选择轨道
    if (plexMediaInfo != null && availableTracks.isNotEmpty) {
      final plexSubtitleTracks = plexMediaInfo!.subtitleTracks;
      final plexSelectedIndex = plexSubtitleTracks.indexWhere((t) => t.selected);
      if (plexSelectedIndex >= 0 && plexSelectedIndex < availableTracks.length) {
        return TrackSelectionResult(availableTracks[plexSelectedIndex], TrackSelectionPriority.plexSelected);
      }
    }

    // 优先级 3：尝试针对该媒体的语言偏好
    if (metadata.subtitleLanguage != null) {
      if (metadata.subtitleLanguage == 'none' || metadata.subtitleLanguage!.isEmpty) {
        return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.perMedia);
      } else if (availableTracks.isNotEmpty) {
        final matchedTrack = availableTracks.firstWhere(
          (track) => languageMatches(track.language, metadata.subtitleLanguage),
          orElse: () => availableTracks.first,
        );
        if (languageMatches(matchedTrack.language, metadata.subtitleLanguage)) {
          return TrackSelectionResult(matchedTrack, TrackSelectionPriority.perMedia);
        }
      }
    }

    // 优先级 4：应用用户个人资料偏好
    if (profileSettings != null && availableTracks.isNotEmpty) {
      subtitleToSelect = findSubtitleTrackByProfile(
        availableTracks,
        profileSettings!,
        selectedAudioTrack: selectedAudioTrack,
      );
      if (subtitleToSelect != null) {
        return TrackSelectionResult(subtitleToSelect, TrackSelectionPriority.profile);
      }
    }

    // 优先级 5：检查默认字幕
    if (availableTracks.isNotEmpty) {
      final defaultTrack = availableTracks.firstWhere((t) => t.isDefault == true, orElse: () => availableTracks.first);
      if (defaultTrack.isDefault == true) {
        return TrackSelectionResult(defaultTrack, TrackSelectionPriority.defaultTrack);
      }
    }

    // 优先级 6：关闭字幕
    return TrackSelectionResult(SubtitleTrack.off, TrackSelectionPriority.off);
  }

  /// 根据偏好选择并应用音频和字幕轨道
  Future<void> selectAndApplyTracks({
    AudioTrack? preferredAudioTrack,
    SubtitleTrack? preferredSubtitleTrack,
    double? preferredPlaybackRate,
    Function(AudioTrack)? onAudioTrackChanged,
    Function(SubtitleTrack)? onSubtitleTrackChanged,
  }) async {
    // 等待轨道加载完成
    int attempts = 0;
    while (player.state.tracks.audio.isEmpty && player.state.tracks.subtitle.isEmpty && attempts < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    // 获取真实轨道 (排除 auto 和 no)
    final realAudioTracks = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final realSubtitleTracks = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();

    // 选择并应用音频轨道
    final audioResult = selectAudioTrack(realAudioTracks, preferredAudioTrack);
    AudioTrack? selectedAudioTrack;
    if (audioResult != null) {
      selectedAudioTrack = audioResult.track;
      appLogger.d(
        '音频: ${selectedAudioTrack.title ?? selectedAudioTrack.language ?? "轨道 ${selectedAudioTrack.id}"} [${audioResult.priority.name}]',
      );
      player.selectAudioTrack(selectedAudioTrack);

      // 如果这是用户的导航偏好 (优先级 1)，则保存到 Plex
      if (audioResult.priority == TrackSelectionPriority.navigation && onAudioTrackChanged != null) {
        onAudioTrackChanged(selectedAudioTrack);
      }
    }

    // 选择并应用字幕轨道
    final subtitleResult = selectSubtitleTrack(realSubtitleTracks, preferredSubtitleTrack, selectedAudioTrack);
    final selectedSubtitleTrack = subtitleResult.track;
    final subtitleName = selectedSubtitleTrack.id == 'no'
        ? '关闭'
        : (selectedSubtitleTrack.title ?? selectedSubtitleTrack.language ?? '轨道 ${selectedSubtitleTrack.id}');
    appLogger.d('字幕: $subtitleName [${subtitleResult.priority.name}]');
    player.selectSubtitleTrack(selectedSubtitleTrack);

    // 如果这是用户的导航偏好 (优先级 1)，则保存到 Plex
    if (subtitleResult.priority == TrackSelectionPriority.navigation && onSubtitleTrackChanged != null) {
      onSubtitleTrackChanged(selectedSubtitleTrack);
    }

    // 如果提供了首选速率，则设置播放速率
    if (preferredPlaybackRate != null) {
      player.setRate(preferredPlaybackRate);
    }
  }
}
