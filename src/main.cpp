#include <ArduinoOTA.h>
#include <ESP8266WiFi.h>
#include <ESP8266mDNS.h>
#include <WiFiUdp.h>

#define CONFIG_FILE "/config.txt"

#define WIFI_CLIENT_TIMEOUT 60 // seconds
#define WIFI_RCVBUF_LEN 256

WiFiServer server(23);
WiFiClient client;
WiFiClient guiClient; // Connection to the GUI program

String guiIP = DEFAULT_GUI_IP;
String wifi_ssid = WIFI_SSID;
String wifi_pass = WIFI_PASSWORD;

unsigned int gui_conn_retry_t = 1; // sec.
unsigned long gui_conn_attempt_time = 0;

#define DIGIPOT_CS D3
#define DIGIPOT_MOSI D1
#define DIGIPOT_SCK D2

#define MUX_C0 D5 // LSB of channel selection
#define MUX_C1 D6 // MSB of channel selection

#define MUX_CHAN_I 0 // Mux channel for current sensing
#define MUX_CHAN_V 1 // Mux channel for output voltage sensing
#define MUX_CHAN_S 2 // Mux channel for supply voltage sensing

//#define NEG_PWM 3
#define RLY_CTL D0

#define OVERSAMPLE 32

long a, n;
unsigned long t, timeout;

char guiRcvBuf[WIFI_RCVBUF_LEN];
char cliRcvBuf[WIFI_RCVBUF_LEN];
byte guiBufLen = 0;
byte cliBufLen = 0;
bool hadClient = false;
bool hadGuiClient = false;

void clearGuiBuf() {
    memset(guiRcvBuf, 0, sizeof(guiRcvBuf));
    guiBufLen = 0;
}

void clearCliBuf() {
    memset(cliRcvBuf, 0, sizeof(cliRcvBuf));
    cliBufLen = 0;
}

void readConfig() {
    File f = SPIFFS.open(CONFIG_FILE, "r");
    if (!f) {
        Serial.println("readConfig(): open failed");
        return;
    }
    String s = f.readStringUntil('\n');
    s.trim();
    while (s.length() > 0) {
        if (s.charAt(0) != '#') {
            int eqPos = s.indexOf('=');
            String k = s.substring(0, eqPos);
            String v = s.substring(eqPos + 1);
            if (k.equalsIgnoreCase("ip")) {
                guiIP = v;
                Serial.println("GUI IP '" + guiIP + "' read from config file");
            }
            if (k.equalsIgnoreCase("ssid")) {
                wifi_ssid = v;
                Serial.println("SSID '" + wifi_ssid + "' read from config file");
            }
            if (k.equalsIgnoreCase("pass")) {
                wifi_pass = v;
                Serial.println("Password read from config file");
            }
        }
        s = f.readStringUntil('\n');
        s.trim();
    }
    f.close();
}

void writeConfig() {
    File f = SPIFFS.open(CONFIG_FILE, "w");
    if (!f) {
        Serial.println("writeConfig(): open failed");
    }
    f.println("IP=" + guiIP);
    f.println("SSID=" + wifi_ssid);
    f.println("PASS=" + wifi_pass);
    f.close();
    Serial.println("Config written");
}

void digipot_set(char chan, int val) { //chan is 0(A) or 1(B), value is 0-256 (inclusive)
    int d1 = 0;
    int d2 = 0;
    //16bit data is 000a00dddddddddd (4bit address is 0 or 1, write command is 00, data is 10bits
    if (chan) {
        d1 = 16;
    }
    if (val > 255) {
        d1 = d1 + 1;
    }
    d2 = val & 255;
    digitalWrite(DIGIPOT_CS, LOW);
    shiftOut(DIGIPOT_MOSI, DIGIPOT_SCK, MSBFIRST, d1);
    shiftOut(DIGIPOT_MOSI, DIGIPOT_SCK, MSBFIRST, d2);
    digitalWrite(DIGIPOT_CS, HIGH);
    //    Serial.println("%i %i", d1, d2);
}

void processGuiCmd() {
    char d;
    if (sscanf(guiRcvBuf, "%c%ld", &d, &n) == 2) {
        Serial.printf("%c:%ld\n", d, n);
        if (d == 'V') {
            if ((n >= 0) && (n <= 256)) {
                digipot_set(1, n);
                Serial.printf("Volts set to: %ld\n", n);
            }
        }
        if (d == 'I') {
            if ((n >= 0) && (n <= 256)) {
                digipot_set(0, n);
                Serial.printf("Current set to: %ld\n", n);
            }
        }
        if (d == 'R') {
            if (n == 0) {
                Serial.println("Relay off");
                digitalWrite(RLY_CTL, LOW);
            }
            if (n == 1) {
                Serial.println("Relay on");
                digitalWrite(RLY_CTL, HIGH);
            }
        }
    }
}

void processCliCmd() {
    if (strncasecmp_P(cliRcvBuf, "IP ", 3) == 0) {
        guiIP = String(cliRcvBuf + 3);
        client.printf("IP set to %s\n", guiIP.c_str());
        Serial.printf("IP set to %s\n", guiIP.c_str());
        writeConfig();
    }
    if (strncasecmp_P(cliRcvBuf, "SSID ", 5) == 0) {
        wifi_ssid = String(cliRcvBuf + 5);
        client.printf("SSID set to %s\n", wifi_ssid.c_str());
        Serial.printf("SSID set to %s\n", wifi_ssid.c_str());
        writeConfig();
    }
    if (strncasecmp_P(cliRcvBuf, "PASS ", 5) == 0) {
        wifi_ssid = String(cliRcvBuf + 5);
        client.println("Pass set");
        Serial.println("Pass set");
        writeConfig();
    }
}

void setMuxChan(uint8_t muxChan) {
    digitalWrite(MUX_C0, muxChan & 0x1 ? HIGH : LOW);
    digitalWrite(MUX_C1, muxChan & 0x2 ? HIGH : LOW);
    delay(1); // settle
}

int analogReadOversample(uint8_t muxChan) {
    setMuxChan(muxChan);
    int i;
    long n = 0;
    for (i = 0; i < OVERSAMPLE; i++) {
        n = n + analogRead(A0);
        delay(1);
    }
    return n / OVERSAMPLE;
}

int getI() { return analogReadOversample(MUX_CHAN_I); }
int getV() { return analogReadOversample(MUX_CHAN_V); }
int getS() { return analogReadOversample(MUX_CHAN_S); }

void digipot_init() {
    digitalWrite(DIGIPOT_CS, HIGH);
    digitalWrite(DIGIPOT_MOSI, LOW);
    digitalWrite(DIGIPOT_SCK, LOW);
    pinMode(DIGIPOT_CS, OUTPUT);
    pinMode(DIGIPOT_MOSI, OUTPUT);
    pinMode(DIGIPOT_SCK, OUTPUT);
}


void setup() {
    Serial.begin(SERIAL_SPEED);
    while (!Serial)
        ;

    delay(200);        //let boost stabilise
    digipot_init();    //I is chan 0, V is chan 1
    digipot_set(1, 0); //set to 0
    digipot_set(0, 0);
    digitalWrite(RLY_CTL, LOW);
    pinMode(RLY_CTL, OUTPUT);
    digitalWrite(MUX_C0, LOW);
    pinMode(MUX_C0, OUTPUT);
    digitalWrite(MUX_C1, LOW);
    pinMode(MUX_C1, OUTPUT);
    t = millis();

    timeout = 200;

    SPIFFSConfig cfg;
    cfg.setAutoFormat(false);
    SPIFFS.setConfig(cfg);
    if (SPIFFS.begin()) {
        Serial.println("Found FS");
        readConfig();
    }

    // Connect WiFi
    Serial.printf("Connecting to %s\n", wifi_ssid.c_str());
    WiFi.hostname(ESP8266_HOSTNAME);
    WiFi.begin(wifi_ssid, wifi_pass);

    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
        // Port defaults to 8266
        // ArduinoOTA.setPort(8266);

        // No authentication by default
        // ArduinoOTA.setPassword("admin");

        // Password can be set with it's md5 value as well
        // MD5(admin) = 21232f297a57a5a743894a0e4a801fc3
        // ArduinoOTA.setPasswordHash("21232f297a57a5a743894a0e4a801fc3");
    }
    Serial.println("WiFi connected");

    // Print the IP address
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());

    ArduinoOTA.onStart([]() {
        String type;
        if (ArduinoOTA.getCommand() == U_FLASH) {
            type = "sketch";
        } else { // U_FS
            type = "filesystem";
        }

        // NOTE: if updating FS this would be the place to unmount FS using FS.end()
        Serial.println("Start updating " + type);
    });
    ArduinoOTA.onEnd([]() {
        Serial.println("\nEnd");
    });
    ArduinoOTA.onProgress([](unsigned int progress, unsigned int total) {
        Serial.printf("Progress: %u%%\r", (progress / (total / 100)));
    });
    ArduinoOTA.onError([](ota_error_t error) {
        Serial.printf("Error[%u]: ", error);
        if (error == OTA_AUTH_ERROR) {
            Serial.println("Auth Failed");
        } else if (error == OTA_BEGIN_ERROR) {
            Serial.println("Begin Failed");
        } else if (error == OTA_CONNECT_ERROR) {
            Serial.println("Connect Failed");
        } else if (error == OTA_RECEIVE_ERROR) {
            Serial.println("Receive Failed");
        } else if (error == OTA_END_ERROR) {
            Serial.println("End Failed");
        }
    });
    ArduinoOTA.begin();

    server.begin();
    Serial.println("Server started");

    Serial.println("Ready");
}

void loop() {
    ArduinoOTA.handle();
    // If we're connected to the GUI ...
    if (guiClient && guiClient.connected()) {
        while (guiClient.available()) { // ... read & process commands from the GUI
            char c;
            c = guiClient.read();
            switch (c) {
            case '\r':
                break;
            case '\n':
                guiRcvBuf[guiBufLen++] = '\0';
                //Serial.printf("gui:%s\n", guiRcvBuf);
                processGuiCmd();
                clearGuiBuf();
                break;
            default:
                guiRcvBuf[guiBufLen++] = c;
            }
        }
        // Once done processing commands, send the latest readings to the GUI
        if ((millis() - t) > timeout) {
            t = t + timeout;
            guiClient.printf("J%i\n", getI());
            guiClient.printf("U%i\n", getV());
            guiClient.printf("S%i\n", getS());
        }
    } else {
        // Not connected to GUI.
        if (hadGuiClient) {
            // We used to be - conn is now closed
            guiClient.stop();
            Serial.println("gui conn lost");
            hadGuiClient = false;
        }
        // If we received a connection to our server ...
        if (client && client.connected()) {
            while (client.available()) { // ... Read & process commands from it
                char c;
                c = client.read();
                switch (c) {
                case '\r':
                    break;
                case '\n':
                    cliRcvBuf[cliBufLen++] = '\0';
                    //Serial.printf("cli:%s\n", cliRcvBuf);
                    processCliCmd();
                    clearCliBuf();
                    break;
                default:
                    cliRcvBuf[cliBufLen++] = c;
                }
            }
        } else { // Nobody is connected to us now
            if (hadClient) {
                // Someone used to be - conn is now closed
                client.stop();
                Serial.println("cli conn lost");
                hadClient = false;
            }
            // Check for a new connection
            client = server.available();
            if (client) {
                // Someone has connected
                Serial.println("cli conn open");
                hadClient = true;
            }
        }
        // Check if it's time to retry connecting to the GUI
        if (millis() - gui_conn_attempt_time > gui_conn_retry_t * 1000) {
            Serial.println("attempting gui conn");
            guiClient.connect(guiIP, 23);
            gui_conn_attempt_time = millis();
            if (guiClient && guiClient.connected()) {
                Serial.println("gui conn open");
                hadGuiClient = true;
            }
        }
    }
}