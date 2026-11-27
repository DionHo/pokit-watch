/// GATT UUIDs used by Pokit devices, as strings so this package stays free of CoreBluetooth.
///
/// Sources: Pokit's "Bluetooth API Definition" (D0005250) and the open-source dokit project,
/// which documents the Pokit Pro additions.
public enum PokitUUID {
    // MARK: Status service (its UUID also tells the products apart)

    /// Status service as advertised by the Pokit Meter.
    public static let statusServiceMeter = "57D3A771-267C-4394-8872-78223E92AEC4"
    /// Status service as advertised by the Pokit Pro.
    public static let statusServicePro = "57D3A771-267C-4394-8872-78223E92AEC5"

    /// Read. 20 bytes: firmware version, limits, MAC address.
    public static let deviceCharacteristics = "6974F5E5-0E54-45C3-97DD-29E4B5FB0849"
    /// Read (Meter) / read + notify (Pro). Device status and battery.
    public static let status = "3DBA36E1-6120-4706-8DFD-ED9C16E569B6"
    /// Read / write. UTF-8, at most 11 bytes.
    public static let deviceName = "7F0375DE-077E-4555-8F78-800494509CC3"
    /// Write `01` to flash the LED. Works on the Pokit Meter only.
    public static let flashLED = "EC9BB1F3-05A9-4277-8DD0-60A7896F0D6E"
    /// Pokit Pro only. Read / write / notify, one byte: 0 = off, 1 = on.
    public static let torch = "AAF3F6D5-43D4-4A83-9510-DFF3D858D4CC"
    /// Pokit Pro only. Read / write / notify, two bytes; the second is the button state.
    public static let buttonPress = "8FE5B5A9-B5B4-4A7B-8FF2-87224B970F89"

    // MARK: Multimeter service

    public static let multimeterService = "E7481D2F-5781-442E-BB9A-FD4E3441DADC"
    /// Write. 6 bytes: mode, range, update interval.
    public static let multimeterSettings = "53DC9A7A-BC19-4280-B76B-002D0E23B078"
    /// Read + notify. 7 bytes: status, value, mode, range.
    public static let multimeterReading = "047D3559-8BEE-423A-B229-4417FA603B90"

    // MARK: Oscilloscope (DSO) service

    public static let dsoService = "1569801E-1425-4A7A-B617-A4F4ED719DE6"
    /// Write. 13 bytes: command, trigger level, mode, range, sampling window, sample count.
    public static let dsoSettings = "A81AF1B6-B8B3-4244-8859-3DA368D2BE39"
    /// Read + notify. Status, scale and size of the capture that follows.
    public static let dsoMetadata = "970F00BA-F46F-4825-96A8-153A5CD0CDA9"
    /// Notify. The capture, as raw 16-bit samples spread over several notifications.
    public static let dsoReading = "98E14F8E-536E-4F24-B4F4-1DEBFED0A99E"

    // MARK: Data logger service

    public static let loggerService = "A5FF3566-1FD8-4E10-8362-590A578A4121"
    /// Write. Start, stop or fetch; 11 bytes on the Pokit Meter, 13 on the Pokit Pro.
    public static let loggerSettings = "5F97C62B-A83B-46C6-B9CD-CAC59E130A78"
    /// Read + notify. Status, scale, interval, sample count and start time of the log.
    public static let loggerMetadata = "9ACADA2E-3936-430B-A8F7-DA407D97CA6E"
    /// Notify. The logged samples, raw 16-bit values spread over several notifications.
    public static let loggerReading = "3C669DAB-FC86-411C-9498-4F9415049CC0"

    // MARK: Device Information service (Bluetooth SIG)

    public static let deviceInformationService = "180A"
    public static let manufacturerName = "2A29"
    public static let modelNumber = "2A24"
    public static let serialNumber = "2A25"
    public static let firmwareRevision = "2A26"
    public static let hardwareRevision = "2A27"
    public static let softwareRevision = "2A28"
}
