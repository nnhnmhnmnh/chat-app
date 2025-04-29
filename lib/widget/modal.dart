import 'package:flutter/material.dart';

class ModelConfigModal extends StatefulWidget {
  final String selectedModel;
  final double temperature;
  final String systemInstruction;
  final bool isTemporaryChat;
  final Future<void> Function(
      String model,
      double temperature,
      String systemInstruction,
      bool isTemporaryChat,
      ) onApply;
  final List<String> availableModels;
  final Future<int> Function() countTokens;

  const ModelConfigModal({
    required this.selectedModel,
    required this.temperature,
    required this.systemInstruction,
    required this.isTemporaryChat,
    required this.availableModels,
    required this.countTokens,
    required this.onApply,
    super.key,
  });

  @override
  State<ModelConfigModal> createState() => _ModelConfigModalState();
}

class _ModelConfigModalState extends State<ModelConfigModal> {
  late String _tempModel;
  late double _tempTemperature;
  late bool _tempIsTemporaryChat;
  late TextEditingController _tempSIController;
  bool _isExpanded = false;
  String _tokenCount = "0";

  @override
  void initState() {
    super.initState();
    _tempModel = widget.selectedModel;
    _tempTemperature = widget.temperature;
    _tempIsTemporaryChat = widget.isTemporaryChat;
    _tempSIController = TextEditingController(text: widget.systemInstruction);

    _calculateTokens();
  }

  void _calculateTokens() async {
    final tokenCount = await widget.countTokens();
    if (mounted) {
      setState(() {
        _tokenCount = tokenCount.toString();
      });
    }
  }

  @override
  void dispose() {
    _tempSIController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Model Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: Icon(Icons.memory),
              ),
              value: _tempModel,
              items: widget.availableModels.map((model) {
                return DropdownMenuItem(
                  value: model,
                  child: Text(model),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _tempModel = value!;
                });
              },
            ),
            SizedBox(height: 10),
            Container(
              margin: EdgeInsets.symmetric(vertical: 10),
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Total tokens: $_tokenCount',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
            ),
            Row(
              children: [
                Icon(Icons.thermostat, color: Colors.red),
                SizedBox(width: 5),
                Text('Temperature', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Slider(
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    value: _tempTemperature,
                    onChanged: (value) {
                      setState(() {
                        _tempTemperature = value;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 50,
                  height: 50,
                  child: TextField(
                    controller: TextEditingController(
                      text: _tempTemperature.toStringAsFixed(1),
                    ),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(border: OutlineInputBorder()),
                    onChanged: (value) {
                      final temp = double.tryParse(value);
                      if (temp != null && temp >= 0 && temp <= 2) {
                        setState(() {
                          _tempTemperature = temp;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            ListTileTheme(
              contentPadding: EdgeInsets.zero,
              child: SwitchListTile(
                title: Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, color: Colors.blue),
                    SizedBox(width: 5),
                    Text('Temporary Chat', style: TextStyle(fontSize: 16)),
                  ],
                ),
                value: _tempIsTemporaryChat,
                onChanged: (value) {
                  setState(() {
                    _tempIsTemporaryChat = value;
                  });
                },
                inactiveThumbColor: Colors.grey,
              ),
            ),
            SizedBox(height: 10),
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _isExpanded ? MediaQuery.of(context).size.height * 0.6 : 60,
              child: TextField(
                controller: _tempSIController,
                onChanged: (value) {},
                decoration: InputDecoration(
                  labelText: 'System Instructions',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30.0)),
                  suffixIcon: IconButton(
                    icon: Icon(_isExpanded ? Icons.fullscreen_exit : Icons.fullscreen),
                    onPressed: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                  ),
                ),
                minLines: _isExpanded ? null : 1,
                maxLines: _isExpanded ? 30 : 3,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await widget.onApply(
                  _tempModel,
                  _tempTemperature,
                  _tempSIController.text,
                  _tempIsTemporaryChat,
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}