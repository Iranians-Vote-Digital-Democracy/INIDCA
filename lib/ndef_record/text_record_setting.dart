import 'package:flutter/material.dart';

import 'package:ndef/ndef.dart' as ndef;

class NDEFTextRecordSetting extends StatefulWidget {
  final ndef.TextRecord record;
  NDEFTextRecordSetting({super.key, ndef.TextRecord? record})
      : record = record ?? ndef.TextRecord(language: 'en', text: '');
  @override
  State createState() => _NDEFTextRecordSetting();
}

class _NDEFTextRecordSetting extends State<NDEFTextRecordSetting> {
  final GlobalKey _formKey = GlobalKey<FormState>();
  late TextEditingController _languageController;
  late TextEditingController _textController;
  late int _dropButtonValue;

  @override
  initState() {
    super.initState();

    _languageController = TextEditingController.fromValue(
        TextEditingValue(text: widget.record.language!));
    _textController = TextEditingController.fromValue(
        TextEditingValue(text: widget.record.text!));
    _dropButtonValue = ndef.TextEncoding.values.indexOf(widget.record.encoding);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Set Record'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.always,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  DropdownButton(
                    value: _dropButtonValue,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('UTF-8')),
                      DropdownMenuItem(value: 1, child: Text('UTF-16')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _dropButtonValue = value as int;
                      });
                    },
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'language'),
                    validator: (v) {
                      return v!.trim().length % 2 == 0
                          ? null
                          : 'length must not be blank';
                    },
                    controller: _languageController,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'text'),
                    controller: _textController,
                  ),
                  ElevatedButton(
                    child: const Text('OK'),
                    onPressed: () {
                      if ((_formKey.currentState as FormState).validate()) {
                        Navigator.pop(
                            context,
                            ndef.TextRecord(
                                encoding:
                                    ndef.TextEncoding.values[_dropButtonValue],
                                language: (_languageController.text),
                                text: (_textController.text)));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
