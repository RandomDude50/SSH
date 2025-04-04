import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
// è stato aggiunto il prefisso perm per evitare che vada in conflitto con la libreria influxdb
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:influxdb_client/api.dart';
import 'package:flutter_application_last/login.dart';

var client = InfluxDBClient(
  url: 'http://ssh.matteolevoni.eu',
  token:
      'ZsrG7s6O3D6JOoeNATTV6VEAkdBU0kNM8orJKLRGFzrNdTWE6D3uRoHtNkkdIumUPeQR0ov-xGB-MUqPmULmCw==',
  org: 'SSH corporation',
  bucket: 'visite',
  debug: true,
);

void main() {
  runApp(LoginApp()); //runno la login app che poi runna questa
}

class LoginApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(
        onLoginComplete: (username) {
          // Una volta che il login è completato, mostra la schermata BLE
          runApp(MyApp(username: username));
        },
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  // l'input username dato nel login
  final String username;
  MyApp({required this.username});
  // Widget padre
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BleHome(username: username),
    );
  }
}

class BleHome extends StatefulWidget {
  final String username;
  BleHome({required this.username});
  // main Widget
  @override
  _BleHomeState createState() => _BleHomeState();
}

class _BleHomeState extends State<BleHome> {
  final flutterReactiveBle = FlutterReactiveBle(); // istanzio un BLE
  List<DiscoveredDevice> _devices = []; // devices
  Set<String> _scannedDeviceIds = Set(); // lista senza ripetuti
  //steams x gestione dati
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connection;

  var tempId = Uuid.parse("2eebb556-9114-4eb6-97bd-cd08cdac58ab");
  var battId = Uuid.parse("fb50f520-5c32-4437-8a49-c378301143c7");
  var ecg_ppgId = Uuid.parse("2359f450-8c5b-4de7-b503-9df03afa6095");
  //flag dati
  bool imconnected = false;
  //dati effetivi
  double? _temperatureData;
  int? _batteryData;
  double? _irData;
  double? _ecgData;
  double? _redData;

  double? real_irData;
  double? real_ecgData;
  double? real_redData;

  late Timer timer1, timer2, timer3, timerfake;

  @override
  void initState() {
    super.initState();
    _bleInitialization(); // avvia l'inizializzazione BLE all'avvio del widget
  }

  // Async function that serves the purpose to initialize the main pre-requisites of BLE
  Future<void> _bleInitialization() async {
    bool permission =
        await _checkPermissions(); // Permessi all'avvio dell'app (+android manifest)
    if (permission) {
      _checkBluetooth(); //vediamo fisicamente if possiamo bluetooth
    } else {
      print('Permessi non concessi');
    }
  }

  // BLE requires all these permission to be granted, not just location
  // warning: the permission_holder instances have the 'perm' prefix !
  Future<bool> _checkPermissions() async {
    perm.PermissionStatus locationPermission =
        await perm.Permission.location.request();
    perm.PermissionStatus bleScan =
        await perm.Permission.bluetoothScan.request();
    perm.PermissionStatus bleConnect =
        await perm.Permission.bluetoothConnect.request();

    return locationPermission.isGranted &&
        bleScan.isGranted &&
        bleConnect.isGranted;
  }

  void _checkBluetooth() {
    flutterReactiveBle.statusStream.listen((status) {
      if (status == BleStatus.ready) {
        //mi asssicuro sia tutto pronto
        _startDeviceScan();
      }
    });
  }

  //scan
  void _startDeviceScan() {
    _scanSubscription =
        flutterReactiveBle.scanForDevices(withServices: []).listen((device) {
      if (!_scannedDeviceIds.contains(device.id)) {
        setState(() {
          //aggiorno il main widget con le seguenti info
          _devices.add(device);
          _scannedDeviceIds.add(device.id);
        });
      }
    }, onError: (dynamic error) {
      print('Errore durante la scansione dei dispositivi: $error');
    });
  }

  // prima fase pairing
  void connect(String deviceId) {
    _connection = flutterReactiveBle
        .connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 2),
    )
        .listen((update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        Future.delayed(Duration(milliseconds: 75), () {
          imconnected = true;
        });
        //
        log('Connesso al dispositivo $deviceId');
        // Creiamo e passiamo la variabile qualifiedCharacteristic
        _discoverServices(deviceId);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        log('Disconnesso dal dispositivo $deviceId');
      }
    });
  }

  void requestTemperatureData(
      String deviceId, QualifiedCharacteristic qualifiedCharacteristic) {
    flutterReactiveBle.readCharacteristic(qualifiedCharacteristic).then((data) {
      setState(() {
        if (data.isNotEmpty && data.length > 3) {
          int tempTOHigh = data[2];
          int tempTOLow = data[3];
          int tempT0 = (tempTOHigh << 8) + tempTOLow;
          _temperatureData = (tempT0.toDouble()) / 100;
        } else {
          _temperatureData = null;
        }
      });
    }, onError: (dynamic error) {
      print('Error reading temperature data: $error');
    });
  }

  void requestBatteryData(
      String deviceId, QualifiedCharacteristic qualifiedCharacteristic) {
    flutterReactiveBle.readCharacteristic(qualifiedCharacteristic).then((data) {
      if (data.isNotEmpty && data.length > 3) {
        int batteryHigh = data[0];
        int batteryLow = data[1];
        int battery = (batteryHigh << 8) + batteryLow;
        _batteryData = (battery) ~/ 10; // _batteryData is now of type double?
      } else {
        _batteryData = null;
      }
    }, onError: (dynamic error) {
      print('Error reading battery data: $error');
    });
  }

  Future<void> influx_TX_data() async {
    var writeApi = WriteService(client);

    // delay di 240ms per dare tempo al programma di connettersi ad influxdb
    await Future.delayed(Duration(milliseconds: 240));

    // trasmissione batteria
    var batt_point = Point('batteria')
        .addTag('paziente', widget.username)
        .addField('%', _batteryData)
        .time(DateTime.now().toUtc());

    await writeApi.write(batt_point).then((value) {
      print('trasmission completed');
    }).catchError((exception) {
      print("transmission error");
      print(exception);
    });

    // trasmissione temperatura
    var temp_point = Point('temperatura')
        .addTag('paziente', widget.username)
        .addField('C', _temperatureData)
        .time(DateTime.now().toUtc());

    await writeApi.write(temp_point).then((value) {
      print('trasmission completed');
    }).catchError((exception) {
      print("transmission error");
      print(exception);
    });

    // trasmissione ecg
    var ecg_point = Point('ecg')
        .addTag('paziente', widget.username)
        .addField('-', _ecgData)
        .time(DateTime.now().toUtc());

    await writeApi.write(ecg_point).then((value) {
      print('trasmission completed');
    }).catchError((exception) {
      print("transmission error");
      print(exception);
    });

    // trasmissione red ppg
    var red_point = Point('red ppg')
        .addTag('paziente', widget.username)
        .addField('-', _redData)
        .time(DateTime.now().toUtc());

    await writeApi.write(red_point).then((value) {
      print('trasmission completed');
    }).catchError((exception) {
      print("transmission error");
      print(exception);
    });

    // trasmissione ir ppg
    var ir_point = Point('ir ppg')
        .addTag('paziente', widget.username)
        .addField('-', _irData)
        .time(DateTime.now().toUtc());

    await writeApi.write(ir_point).then((value) {
      print('trasmission completed');
    }).catchError((exception) {
      print("transmission error");
      print(exception);
    });
  }

// I ticks sono calcolati come 95000ms / 10ms = 9500 ticks, 95000ms / 200ms = 475 ticks e 95000ms / 12ms = 7917 ticks rispettivamente.
  void _discoverServices(String deviceId) async {
    flutterReactiveBle.discoverAllServices(deviceId);
    List<Service> services =
        await flutterReactiveBle.getDiscoveredServices(deviceId);
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        QualifiedCharacteristic qualifiedCharacteristic =
            QualifiedCharacteristic(
          serviceId: service.id,
          characteristicId: characteristic.id,
          deviceId: deviceId,
        );
        if (qualifiedCharacteristic.characteristicId.toString() ==
            tempId.toString()) {
          Timer timer1 = Timer.periodic(Duration(milliseconds: 1), (Timer t) {
            influx_TX_data();
            if (t.tick >= 95000) {
              t.cancel();
              // Ritorna alla pagina di login dopo 95 secondi
              runApp(LoginApp());
              client.close();
            }
          });
        } else if (qualifiedCharacteristic.characteristicId.toString() ==
            battId.toString()) {
          Timer timer2 = Timer.periodic(Duration(milliseconds: 20), (Timer t) {
            requestTemperatureData(deviceId, qualifiedCharacteristic);
            requestBatteryData(deviceId, qualifiedCharacteristic);
            if (t.tick >= 4750) {
              t.cancel();
              // Ritorna alla pagina di login dopo 95 secondi
              runApp(LoginApp());
              client.close();
            }
          });
        } else if (qualifiedCharacteristic.characteristicId.toString() ==
            ecg_ppgId.toString()) {
          _subscribeToCharacteristic(qualifiedCharacteristic);
          Timer timer3 = Timer.periodic(Duration(milliseconds: 2), (Timer t) {
            real_ecgData = _ecgData;
            real_redData = _redData;
            real_irData = _irData;
            if (t.tick >= 47500) {
              t.cancel();
              // Ritorna alla pagina di login dopo 95 secondi
              runApp(LoginApp());
              client.close();
            }
          });
        }
      }
    }
  }

  void _handleData(QualifiedCharacteristic characteristic, List<int> data) {
    if (characteristic.characteristicId.toString() == ecg_ppgId.toString()) {
      // ECG, IR PPG, RED PPG data handling
      var ECG = [
        data[0] | (data[1] << 8) | ((data[6] & 0x03) << 16),
        data[7] | (data[8] << 8) | ((data[13] & 0x03) << 16)
      ];
      var IR = [
        data[2] | (data[3] << 8) | ((data[6] & 0x1C) << 11),
        data[9] | (data[10] << 8) | ((data[13] & 0x1C) << 11)
      ];
      var RED = [
        data[4] | (data[5] << 8) | ((data[6] & 0xE0) << 8),
        data[11] | (data[12] << 8) | ((data[13] & 0xE0) << 8)
      ];
      var TimeStamp =
          data[14] | (data[15] << 8) | (data[16] << 16) | (data[17] << 24);
      // Use ECG, IR, Red, and TimeStamp as needed

      String sECG = ECG.join();
      String sRED = RED.join();
      String sIR = IR.join();

      _ecgData = double.parse(sECG);
      _redData = double.parse(sRED);
      _irData = double.parse(sIR);
    }
  }

  StreamSubscription<List<int>> _subscribeToCharacteristic(
      QualifiedCharacteristic characteristic) {
    return flutterReactiveBle.subscribeToCharacteristic(characteristic).listen(
        (data) {
      _handleData(characteristic, data);
      print('Received data: $data');
    }, onError: (dynamic error) {
      print('Error: $error');
    });
  }

  // chiusura
  @override
  void dispose() {
    _scanSubscription?.cancel();
    //_temperatureSubscription?.cancel();
    //_batterySubscription?.cancel();
    _connection?.cancel();
    super.dispose();
    timer1.cancel();
    timer2.cancel();
    timer3.cancel();
    client.close();
  }

  // main widget
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner Mattei'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!imconnected &&
                _devices.isEmpty) //non trova device pk no bluetooth
              const Center(
                child: Text(
                  'Attendere la fine dello scan e \nAssicurarsi di aver attivo Bluetooth del telefono',
                  style: TextStyle(fontSize: 20.0),
                ),
              ),
            if (!imconnected && _devices.isNotEmpty) _buildDeviceList(),
            if (imconnected) // Se siamo connessi, mostra i dati di temperatura e batteria
              //ho bisogno di far passare un secondo qiu per aggiustare tutto
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Temperature: ${_temperatureData}',
                    style: const TextStyle(
                      fontSize: 20.0, // Dimensione del carattere
                      color:
                          Color.fromARGB(255, 107, 0, 150), // Colore del testo
                      fontWeight: FontWeight.bold, // Grassetto
                    ),
                  ),
                  Text(
                      'Battery: ${_batteryData != null ? _batteryData! : 'N/A'}', // Mostra il valore della batteria o 'N/A' se null
                      style: TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.bold,
                        color: _batteryData != null
                            ? (_batteryData! >= 0 && _batteryData! <= 33
                                ? Colors
                                    .red // Batteria fra 0 e 33, colore rosso
                                : (_batteryData! >= 34 && _batteryData! <= 67
                                    ? Colors
                                        .yellow // Batteria fra 34 e 67, colore arancione
                                    : (_batteryData! >= 68 &&
                                            _batteryData! <= 100
                                        ? Colors
                                            .green // Batteria fra 68 e 100, colore verde
                                        : Colors
                                            .black))) // Valore non in un intervallo valido, colore di default nero
                            : Colors
                                .black, // Se _batteryData è null, colore di default nero
                      )),
                  Text(
                    'ECG: ${real_ecgData}',
                    style: const TextStyle(
                      fontSize: 20.0, // Dimensione del carattere
                      color: Color.fromARGB(255, 0, 0, 0), // Colore del testo
                      fontWeight: FontWeight.bold, // Grassetto
                    ),
                  ),
                  Text(
                    'IR PPG: ${real_irData}',
                    style: const TextStyle(
                      fontSize: 20.0, // Dimensione del carattere
                      color: Color.fromARGB(255, 0, 0, 0), // Colore del testo
                      fontWeight: FontWeight.bold, // Grassetto
                    ),
                  ),
                  Text(
                    'RED PPG: ${real_redData}',
                    style: const TextStyle(
                      fontSize: 20.0, // Dimensione del carattere
                      color: Color.fromARGB(255, 0, 0, 0), // Colore del testo
                      fontWeight: FontWeight.bold, // Grassetto
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // widget lista device
  Widget _buildDeviceList() {
    return Expanded(
      // Aggiunto Expanded per far sì che la ListView si espanda fino al limite dello spazio disponibile
      child: ListView.builder(
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          return ListTile(
            title: Text(device.name),
            subtitle:
                Text('MAC_add: ${device.id}\nRSSI: ${device.rssi.toString()}'),
            onTap: () {
              connect(device.id);
            },
          );
        },
      ),
    );
  }
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextFormField(),
                  SizedBox(height: 18.0),
                  ElevatedButton(
                    child: Text('Enter'),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                MyApp(username: _usernameController.text),
                          ),
                        );
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
