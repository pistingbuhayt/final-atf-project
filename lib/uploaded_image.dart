import 'package:hive/hive.dart';

part 'uploaded_image.g.dart'; // Ensure this matches the generated file name

@HiveType(typeId: 0) // Unique ID for the adapter
class UploadedImage {
  @HiveField(0)
  final String imagePath;

  @HiveField(1)
  final String resultText;

  UploadedImage(this.imagePath, this.resultText);
}
