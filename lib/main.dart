import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:image/image.dart' as img;
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'uploaded_image.dart';

void main() async {
  await Hive.initFlutter();
  Hive.registerAdapter(UploadedImageAdapter());
  await Hive.openBox<UploadedImage>('uploadedImages');

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ImagePickerDemo(),
    );
  }
}

class ImagePickerDemo extends StatefulWidget {
  @override
  _ImagePickerDemoState createState() => _ImagePickerDemoState();
}

class _ImagePickerDemoState extends State<ImagePickerDemo> {
  final ImagePicker _picker = ImagePicker();
  XFile? _image;
  File? file;
  List<dynamic>? _recognitions;
  String resultText = "";
  List<UploadedImage> uploadedImages = [];
  int _currentIndex = 0;
  bool isInHistory = false;

  @override
  void initState() {
    super.initState();
    loadModel().then((value) {
      loadHistory();
      setState(() {});
    });
  }

  loadModel() async {
    await Tflite.loadModel(
      model: "assets/model_unquant.tflite",
      labels: "assets/labels.txt",
    );
  }

  Future<void> loadHistory() async {
    var box = Hive.box<UploadedImage>('uploadedImages');
    setState(() {
      uploadedImages = box.values.toList();
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _image = image;
          file = File(image.path);
        });
        await detectImage(file!);
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> _scanDocument() async {
    try {
      List<String>? scannedImages = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: false,
      );
      if (scannedImages != null && scannedImages.isNotEmpty) {
        setState(() {
          _image = XFile(scannedImages.first);
          file = File(scannedImages.first);
        });
        await detectImage(file!);
      }
    } catch (e) {
      print('Error scanning document: $e');
    }
  }

  Future<void> preprocessImage(File image) async {
    var originalImage = img.decodeImage(image.readAsBytesSync());
    var resizedImage = img.copyResize(originalImage!, width: 1024, height: 1024);
    var processedImage = img.encodePng(resizedImage);
    File(image.path).writeAsBytesSync(processedImage);
  }

  Future<void> detectImage(File image) async {
    await preprocessImage(image);
    int startTime = DateTime.now().millisecondsSinceEpoch;
    var recognitions = await Tflite.runModelOnImage(
      path: image.path,
      numResults: 6,
      threshold: 0.1,
      imageMean: 127.5,
      imageStd: 127.5,
    );

    setState(() {
      _recognitions = recognitions;
      resultText = _getResultText(recognitions);
      if (!_isImageInHistory(image.path)) {
        _saveImageToHistory(image.path, resultText);
      }
    });

    int endTime = DateTime.now().millisecondsSinceEpoch;
    print("Inference took ${endTime - startTime}ms");
  }

  bool _isImageInHistory(String imagePath) {
    return uploadedImages.any((uploadedImage) => uploadedImage.imagePath == imagePath);
  }

  void _saveImageToHistory(String imagePath, String resultText) {
    var newImage = UploadedImage(imagePath, resultText);
    uploadedImages.add(newImage);
    var box = Hive.box<UploadedImage>('uploadedImages');
    box.add(newImage);
  }

  void _deleteImageFromHistory(int index) {
    var box = Hive.box<UploadedImage>('uploadedImages');
    box.deleteAt(index); // Delete from Hive
    uploadedImages.removeAt(index); // Remove from the local list
    setState(() {}); // Trigger a rebuild to reflect changes
  }

  String _getResultText(var recognitions) {
    if (recognitions != null && recognitions.isNotEmpty) {
      double maxConfidence = 0.0;
      String label = "";

      for (var recognition in recognitions) {
        if (recognition['confidence'] > maxConfidence) {
          maxConfidence = recognition['confidence'];
          label = recognition['label'];
        }
      }

      if ((label.contains("NFA") || label.contains("DFA")) && maxConfidence > 0.1) {
        double confidencePercentage = maxConfidence * 100;
        return "Detected: ${label.replaceAll(RegExp(r'\d'), '')} with confidence ${confidencePercentage.toStringAsFixed(2)}%";
      } else {
        return "No NFA or DFA detected.";
      }
    } else {
      return "No recognition results.";
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    if (index == 0) {
      Navigator.popUntil(context, (route) => route.isFirst);
      setState(() {
        isInHistory = false;
      });
    } else if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HistoryPage(
            uploadedImages: uploadedImages,
            onImageTap: _onHistoryImageTap,
            onDelete: _deleteImageFromHistory,
            currentIndex: _currentIndex,
            onItemTapped: _onItemTapped,
          ),
        ),
      ).then((_) {
        setState(() {
          isInHistory = false;
        });
      });
    }
  }

  void _onHistoryImageTap(UploadedImage uploadedImage) async {
    setState(() {
      _image = XFile(uploadedImage.imagePath);
      file = File(uploadedImage.imagePath);
      isInHistory = true;
    });
    await detectImage(file!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'NoD',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Color(0xFFD4D4D4),
      ),
      body: Column(
        children: [
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  offset: Offset(0, 5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20.0, right: 120.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _image != null ? 'Detector' : 'Home',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Jua',
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Non-Deterministic Finite Automaton or\nDeterministic Finite Automaton Detector',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Jua',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 30),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  if (_image != null)
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: 300,
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              offset: Offset(0, 4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_image!.path),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 280,
                      child: Image.asset(
                        'assets/images/Home.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  SizedBox(height: 20),

                  // Container for the result text
                  if (_image != null)
                    Container(
                      width: 330,
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: _getResultColor(resultText),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            offset: Offset(0, 4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          resultText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                  SizedBox(height: 20),
                  Container(
                    width: 330,
                    child: Column(
                      children: [
                        ElevatedButton(
                          onPressed: isInHistory
                              ? () {
                            // Go back to the collection
                            setState(() {
                              isInHistory = false; // Reset the state
                              _image = null; // Optionally reset the image
                            });
                          }
                              : _scanDocument,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFBF2C4),
                            padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                isInHistory ? Icons.arrow_back : Icons.camera_alt,
                                color: Colors.black,
                              ),
                              SizedBox(width: 10),
                              Text(
                                isInHistory ? 'Go back to collection' : 'Take an image',
                                style: TextStyle(
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _pickImage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFBF2C4),
                            padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.upload,
                                color: Colors.black,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Upload an image',
                                style: TextStyle(
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1.5,
            color: Colors.black,
          ),
          Container(
            color: Color(0xFFD4D4D4),
            child: BottomNavigationBar(
              items: <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Transform.translate(
                    offset: Offset(0, 10),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.home, size: 35),
                    ),
                  ),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Transform.translate(
                    offset: Offset(0, 10),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.image, size: 35),
                    ),
                  ),
                  label: '',
                ),
              ],
              currentIndex: _currentIndex,
              onTap: _onItemTapped,
              selectedItemColor: Colors.black,
              unselectedItemColor: Colors.black,
              backgroundColor: Color(0xFFD4D4D4),
            ),
          ),
        ],
      ),
    );
  }
}

Color _getResultColor(String resultText) {
  if (resultText.contains("NFA")) {
    return Color(0xFFF0A6B4);
  } else if (resultText.contains("DFA")) {
    return Color(0xFFBADAB6);
  }
  return Color(0xFFF0A6B4); // Default color
}


class HistoryPage extends StatefulWidget {
  final List<UploadedImage> uploadedImages;
  final Function(UploadedImage) onImageTap;
  final Function(int) onDelete; // Accept delete function
  final int currentIndex;
  final Function(int) onItemTapped;

  HistoryPage({
    required this.uploadedImages,
    required this.onImageTap,
    required this.onDelete,
    required this.currentIndex,
    required this.onItemTapped,
  });

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late List<UploadedImage> _uploadedImages;

  @override
  void initState() {
    super.initState();
    _uploadedImages = List.from(widget.uploadedImages); // Copy initial images
  }

  void _deleteImage(int index) {
    setState(() {
      _uploadedImages.removeAt(index);
    });
    widget.onDelete(index); // Call the delete function passed from the parent
  }

  Color _getContainerColor(String resultText) {
    if (resultText.contains("DFA")) {
      return Color(0xFFBADAB6); // Color for DFA
    } else if (resultText.contains("NFA")) {
      return Color(0xFFF0A6B4); // Color for NFA
    } else if (resultText == "No NFA or DFA detected.") {
      return Color(0xFFF0A6B4); // Default color for no detection
    }
    return Colors.grey[200]!; // Fallback color
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'NoD',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Color(0xFFD4D4D4),
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Container(
            height: 1.0,
            color: Colors.black,
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_uploadedImages.isEmpty)
            Center(
              child: Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/Collection.png'),
                    fit: BoxFit.contain,
                  ),
                ),
                height: 300,
                width: 300,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 20.0, right: 50.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20.0),
                  child: Text(
                    _uploadedImages.isNotEmpty ? 'Collection' : 'No History',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Jua',
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 20.0),
                  child: Text(
                    'Non-Deterministic Finite Automaton or\nDeterministic Finite Automaton Detector',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Jua',
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _uploadedImages.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () {
                          widget.onImageTap(_uploadedImages[index]);
                          Navigator.pop(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8.0, left: 50.0),
                          child: Container(
                            width: 300,
                            height: 90,
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _getContainerColor(_uploadedImages[index].resultText),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.black,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _uploadedImages[index].resultText,
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    _deleteImage(index);
                                  },
                                  child: Icon(
                                    Icons.delete,
                                    size: 20,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(width: 10),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1.5,
            color: Colors.black,
          ),
          Container(
            color: Color(0xFFD4D4D4),
            child: BottomNavigationBar(
              items: <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                  icon: Transform.translate(
                    offset: Offset(0, 10),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.home, size: 35),
                    ),
                  ),
                  label: '',
                ),
                BottomNavigationBarItem(
                  icon: Transform.translate(
                    offset: Offset(0, 10),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.image, size: 35),
                    ),
                  ),
                  label: '',
                ),
              ],
              currentIndex: widget.currentIndex,
              onTap: widget.onItemTapped,
              selectedItemColor: Colors.black,
              unselectedItemColor: Colors.black,
              backgroundColor: Color(0xFFD4D4D4),
            ),
          ),
        ],
      ),
    );
  }
}

