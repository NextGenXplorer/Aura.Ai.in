import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

final mediaPipeTasksServiceProvider = Provider((ref) => MediaPipeTasksService());

/// Structured result from a MediaPipe vision task.
class MediaPipeResult {
  final String taskType;
  final bool success;
  final String summary;
  final Map<String, dynamic> data;
  final String? errorMessage;

  const MediaPipeResult({
    required this.taskType,
    required this.success,
    required this.summary,
    this.data = const {},
    this.errorMessage,
  });
}

/// Wraps MediaPipe/ML Kit vision tasks for on-device image analysis.
///
/// These tasks use models bundled within the google_mlkit_* SDK packages —
/// no additional downloads needed by the user.
class MediaPipeTasksService {
  FaceDetector? _faceDetector;
  ObjectDetector? _objectDetector;
  SelfieSegmenter? _segmenter;
  PoseDetector? _poseDetector;

  // Lazy initialization to avoid loading all detectors at startup
  FaceDetector get _face => _faceDetector ??= FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  ObjectDetector get _object => _objectDetector ??= ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  SelfieSegmenter get _selfie => _segmenter ??= SelfieSegmenter(
    mode: SegmenterMode.single,
    enableRawSizeMask: true,
  );

  PoseDetector get _pose => _poseDetector ??= PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.single,
    ),
  );

  /// Detect faces in an image file.
  /// Returns structured result with face count, bounding boxes, and landmarks.
  Future<MediaPipeResult> detectFaces(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _face.processImage(inputImage);

      if (faces.isEmpty) {
        return const MediaPipeResult(
          taskType: 'faceDetection',
          success: true,
          summary: 'No faces detected in the image.',
          data: {'faceCount': 0},
        );
      }

      return MediaPipeResult(
        taskType: 'faceDetection',
        success: true,
        summary: 'Detected ${faces.length} face(s) in the image.',
        data: {
          'faceCount': faces.length,
          'faces': faces.map((f) => {
            'smilingProbability': f.smilingProbability?.toStringAsFixed(1) ?? 'N/A',
            'leftEyeOpen': f.leftEyeOpenProbability?.toStringAsFixed(1) ?? 'N/A',
            'rightEyeOpen': f.rightEyeOpenProbability?.toStringAsFixed(1) ?? 'N/A',
            'headAngleY': f.headEulerAngleY?.toStringAsFixed(1) ?? 'N/A',
            'headAngleZ': f.headEulerAngleZ?.toStringAsFixed(1) ?? 'N/A',
          }).toList(),
        },
      );
    } catch (e) {
      debugPrint('MediaPipe: Face detection error: $e');
      return MediaPipeResult(
        taskType: 'faceDetection',
        success: false,
        summary: 'Face detection failed.',
        errorMessage: 'Could not process the image. Try a clearer photo.',
      );
    }
  }

  /// Detect and label objects in an image file.
  /// Returns structured result with object labels and confidence scores.
  Future<MediaPipeResult> detectObjects(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final objects = await _object.processImage(inputImage);

      if (objects.isEmpty) {
        return const MediaPipeResult(
          taskType: 'objectDetection',
          success: true,
          summary: 'No objects detected in the image.',
          data: {'objectCount': 0},
        );
      }

      final objectDescriptions = <String>[];
      for (final obj in objects) {
        for (final label in obj.labels) {
          objectDescriptions.add(
            '${label.text} (${(label.confidence * 100).toStringAsFixed(0)}% confidence)'
          );
        }
      }

      return MediaPipeResult(
        taskType: 'objectDetection',
        success: true,
        summary: 'Detected ${objects.length} object(s): ${objectDescriptions.join(", ")}',
        data: {
          'objectCount': objects.length,
          'objects': objectDescriptions,
        },
      );
    } catch (e) {
      debugPrint('MediaPipe: Object detection error: $e');
      return MediaPipeResult(
        taskType: 'objectDetection',
        success: false,
        summary: 'Object detection failed.',
        errorMessage: 'Could not analyze the image. Try a different photo.',
      );
    }
  }

  /// Generate a segmentation mask for background removal.
  /// Returns structured result with mask dimensions.
  Future<MediaPipeResult> removeBackground(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final mask = await _selfie.processImage(inputImage);

      if (mask == null) {
        return const MediaPipeResult(
          taskType: 'segmentation',
          success: false,
          summary: 'Background removal failed.',
          errorMessage: 'Could not generate segmentation mask.',
        );
      }

      return MediaPipeResult(
        taskType: 'segmentation',
        success: true,
        summary: 'Background removal mask generated (${mask.width}x${mask.height}).',
        data: {
          'maskWidth': mask.width,
          'maskHeight': mask.height,
        },
      );
    } catch (e) {
      debugPrint('MediaPipe: Segmentation error: $e');
      return MediaPipeResult(
        taskType: 'segmentation',
        success: false,
        summary: 'Background removal failed.',
        errorMessage: 'Could not segment the image. Try a photo with a clear subject.',
      );
    }
  }

  /// Detect 33 body pose landmarks in an image.
  /// Returns structured result with landmark positions.
  Future<MediaPipeResult> detectPose(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final poses = await _pose.processImage(inputImage);

      if (poses.isEmpty) {
        return const MediaPipeResult(
          taskType: 'poseDetection',
          success: true,
          summary: 'No body pose detected in the image.',
          data: {'poseCount': 0},
        );
      }

      final landmarks = poses.first.landmarks.entries
          .where((e) => e.value.likelihood > 0.5)
          .map((e) => e.key.name)
          .toList();

      return MediaPipeResult(
        taskType: 'poseDetection',
        success: true,
        summary: 'Detected ${poses.length} pose(s) with ${landmarks.length} visible landmarks.',
        data: {
          'poseCount': poses.length,
          'landmarkCount': landmarks.length,
          'visibleLandmarks': landmarks,
        },
      );
    } catch (e) {
      debugPrint('MediaPipe: Pose detection error: $e');
      return MediaPipeResult(
        taskType: 'poseDetection',
        success: false,
        summary: 'Pose detection failed.',
        errorMessage: 'Could not detect body pose. Try a full-body photo.',
      );
    }
  }

  /// Dispose all detectors to free native resources.
  void dispose() {
    _faceDetector?.close();
    _objectDetector?.close();
    _segmenter?.close();
    _poseDetector?.close();
  }
}
