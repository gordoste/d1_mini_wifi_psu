# D1 Mini PSU

Firmware and GUI for a modified version of the Mini PSU from Silicon Chip's Feb 2021 issue. See https://siliconchip.com.au to obtain the original article. Additions include:

+ 2 transistors to allow switching the relay from the D1 mini's 3.3V logic
+ Addition of TMUX1204 4:1 mux - the D1 mini only has one ADC. Sensing of supply voltage, output voltage and current are all done via this mux, which adds 3 extra analog inputs in return for the use of 2 digital outputs needed to select the mux channel.
+ Addition of AMS1117-5.0 regulator to provide the 5V rail from DC power (this also powers the D1 mini) - I would suggest anybody planning to feed more than 12V to the input should upgrade this.

In my design, a daughter board connected via 2.54mm pitch pin headers routes signals to the correct pins on the D1 mini. 

The GUI program acts as a server, waiting for the PSU to connect. The PSU connects to the GUI on startup, and everything works the same once the connection is established. The PSU also listens for connections on port 23. Connecting to this allows the user to specify the IP of the GUI program that the PSU should attempt to connect to. The only other firmware modification was to set the mux channel before reading values from the ADC.

## Uploading to the D1 Mini

This repo is a project for PlatformIO (https://platformio.org) for VS Code. If you're an Arduino IDE fan, copying the contents of src/main.cpp to an .ino file should work with only minor changes. Here are the steps in PlatformIO:

1. Clone the GitHub project to a folder on your PC.
2. Open the project in PlatformIO
3. Connect your D1 mini to USB. It's safest to do this with the PSU's DC power disconnected. If the USB port on the board is obstructed, you can use a serial-to-USB module, however note that to get the module into programming mode you must hold the GPIO0 pin (D3) low while manually resetting. After successful programming, you will need to reset manually again.
4. Edit platformio.ini and input the SSID and password that the device will use.
5. Build the flash filesystem and upload the image, followed by the firmware itself. Go to the PlatformIO tab on the left and under d1_mini_serial, select "Platform > Upload Filesystem Image". After this completes, select "General > Upload and Monitor".
6. Serial output will be displayed after the D1 mini resets. You should see the device's IP.
7. (optional) If you want to set up Over-The-Air (OTA) updates (over WiFi), edit the "upload_port" parameter in platformio.ini. To do an OTA update, use the d1_mini project instead of d1_mini_serial. You can make this the default by editing the default_envs parameter in platformio.ini.

## GUI

The GUI (in the src/Mini_Digital_PSU folder) has been modified as follows:

+ No use of serial ports. Therefore configuration and hotkeys related to this are removed.
+ A configuration parameter "port" can now be used to specify the port to listen on. The default is 23.

## Configuring

There are 3 configuration parameters:

+ *ip* - the IP of the PC running the GUI.
+ *ssid* - the SSID of the WiFi network to connect to (overrides the hardcoded value)
+ *password* - the password of the WiFi network to connect to (overrides the hardcoded value)

To set these, connect to the PSU on port 23 and enter the parameter name followed by a space and then the desired value. The value will be saved to the flash filesystem so that it is restored after reboot.


## Feedback / Requests For Help

Feel free to post questions, feedback and suggestions against this project's Issues tracker. That way I'll get notifited.
