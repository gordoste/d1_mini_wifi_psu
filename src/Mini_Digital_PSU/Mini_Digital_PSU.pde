import processing.net.*;

Server psuServer;
int port = 23;
String portName="23";
Client PSU;
int printcode=-1;
int printkey =-1;
int serialIndex=0;
boolean portConnect=false;
boolean lastkey;

//for parsing function, in lieu of static variables
long parseN=0;
long p=0;
int sign=1;
boolean valid=false;    //only return if something has been entered
int prefix=0;   //prefix

//for saving values from serial port
// U,J,S are the sensed values
long adcU=0;
long adcJ=0;
long adcS=0;

//output states for UI display
float Vout=0;
float Iout=0;
boolean Rout=false;

//conversion factors
float Ufactor=0.0196;    //for converting ADC to display V
float Vfactor=12.83;     //for converting display V to digipot
float Jfactor=0.000769;  //for converting ADC to display I
float Ifactor=325;       //for converting display I to digipot
float Sfactor=0.0196;    //for converting ADC to display supply voltage

//PSU IP
String psuip;

//interface
boolean thismouse, lastmouse;

//graphics
PImage bGround;

//config
String[] config;

//presets
float[] Vpreset={5.0, 5.0, 0.0, 0.0, 0.0};
float[] Ipreset={0.1, 0.5, 0.0, 0.0, 0.0};
String[] Npreset={"USB 0.1A", "USB 0.5A", "---", "---", "---"};
int cPreset=0;    //current preset (to highlight)
float Vsup=0;

void setup() {
  bGround = loadImage("back.png");
  size(480, 320, P2D);
  //size(480, 320,P3D);
  surface.setTitle("Silicon Chip Mini Digital PSU");
  surface.setResizable(false);          //doesn't prevent maximise
  background(color(128, 128, 128));      //cls
  noStroke();    //transparent stroke
  textSize(32);   //gives 24 pixels high text
  lastkey=keyPressed;
  lastmouse=mousePressed;

  //load config and parse into variables
  try {
    config = loadStrings("config.txt");
    println(config.length + " config lines");
  }
  catch(Exception e) {
  }
  if (config != null) {
    for (int i = 0; i < config.length; i++) {
      //println(config[i]);
      String[] tok=split(config[i], '=');
      //println(tok.length);
      if (tok.length == 2) {    //as expected
        if (tok[0].toUpperCase().equals("UFACTOR")) {
          ufactorSet(tok[1]);
        }
        if (tok[0].toUpperCase().equals("VFACTOR")) {
          vfactorSet(tok[1]);
        }
        if (tok[0].toUpperCase().equals("IFACTOR")) {
          ifactorSet(tok[1]);
        }
        if (tok[0].toUpperCase().equals("JFACTOR")) {
          jfactorSet(tok[1]);
        }
        if (tok[0].toUpperCase().equals("SFACTOR")) {
          sfactorSet(tok[1]);
        }
        if (tok[0].toUpperCase().equals("PRESET1")) {
          presetSet(0, tok[1]);
        }    //display is 1 indexed, arrays are 0 indexed
        if (tok[0].toUpperCase().equals("PRESET2")) {
          presetSet(1, tok[1]);
        }    //display is 1 indexed, arrays are 0 indexed
        if (tok[0].toUpperCase().equals("PRESET3")) {
          presetSet(2, tok[1]);
        }    //display is 1 indexed, arrays are 0 indexed
        if (tok[0].toUpperCase().equals("PRESET4")) {
          presetSet(3, tok[1]);
        }    //display is 1 indexed, arrays are 0 indexed
        if (tok[0].toUpperCase().equals("PRESET5")) {
          presetSet(4, tok[1]);
        }    //display is 1 indexed, arrays are 0 indexed
        if (tok[0].toUpperCase().equals("PORT")) {
          portSet(tok[1]);
        }
        //if(tok[0].toUpperCase().equals("VIN")){vinSet(tok[1]);}
      }
    }
  }
  surface.setTitle("Silicon Chip Mini Digital PSU: "+nf(Vsup, 2, 1)+"V input");
  psuServer = new Server(this, port);
}

/*
void vinSet(String t){
 float x;
 x=float(t);
 if(x>0){    //also weed out NaN etc
 Vsup=x;
 println("VIN set");
 }
 }
 */

void presetSet(int n, String t) {
  float volts, current;
  String name;
  String[] parts=split(t, ",");    //eg PRESET1=5,0.1,USB
  if (parts.length<3) {
    return;
  }
  volts=float(parts[0]);
  current=float(parts[1]);
  name=parts[2];
  if (name.length()>7) {
    name=name.substring(0, 6);
  }
  if (name.length()==0) {
    name="-";
  }
  if ((volts>0)&&(current>0)) {
    Vpreset[n]=volts;
    Ipreset[n]=current;
    Npreset[n]=name;
    print("PRESET set ");
    println(n);
  }
}

void ufactorSet(String t) {
  float x;
  x=float(t);
  if (x>0) {    //also weed out NaN etc
    Ufactor=x;
    println("UFACTOR set");
  }
}

void vfactorSet(String t) {
  float x;
  x=float(t);
  if (x>0) {    //also weed out NaN etc
    Vfactor=x;
    println("VFACTOR set");
  }
}

void ifactorSet(String t) {
  float x;
  x=float(t);
  if (x>0) {    //also weed out NaN etc
    Ifactor=x;
    println("IFACTOR set");
  }
}

void jfactorSet(String t) {
  float x;
  x=float(t);
  if (x>0) {    //also weed out NaN etc
    Jfactor=x;
    println("JFACTOR set");
  }
}

void sfactorSet(String t) {
  float x;
  x=float(t);
  if (x>0) {    //also weed out NaN etc
    Sfactor=x;
    println("SFACTOR set");
  }
}

void portSet(String t) {
  try {
    port = Integer.parseInt(t);
    println("PORT set to "+t);
    portName = t;
  }
  catch (Exception e) {
    println("Invalid port: " +t);
  }
}

void draw() {
  boolean thiskey;
  int d, i;
  float xTemp;
  float pTemp;
  int buttonX, buttonY, buttonZ;
  surface.setTitle("Silicon Chip Mini Digital PSU: "+nf(Vsup, 2, 1)+"V input");
  background(color(128, 128, 128));      //cls
  image(bGround, 0, 0);                //background
  if (portConnect) {
    fill(color(0, 192, 0));    //green
  } else {
    fill(color(0, 0, 0));
  }
  text(portName, 340, 312);
  thiskey=keyPressed;
  if ((thiskey==true)&&(lastkey!=true)) {
    printcode=keyCode;
    printkey=key;
  }
  if (portConnect==false) {
    try {
      PSU = psuServer.available();
      if (PSU!=null) {
        println("Got connection");
        portConnect=true;
      }
    }
    catch(Exception e) {
      portConnect=false;              //failed to connect
    }
  }
  /* user initiated disconnect
  else {
    PSU.write("R0\r\nV0\r\nI0\r\n");    //signal for everything off
    adcU=0;
    adcJ=0;    //zero readouts
    PSU.stop();
    portConnect=false;
  }*/
  lastkey=thiskey;

  if (PSU!=null) portConnect = PSU.active();
  if (portConnect) {
    d=parseToken();
    if (d!=0) {
      if (d=='U') {
        if ((parseN>=0)&&(parseN<=1023)) {
          adcU=parseN;
        }
      }
      if (d=='J') {
        if ((parseN>=0)&&(parseN<=1023)) {
          adcJ=parseN;
        }
      }
      //Vsup
      if (d=='S') {
        if ((parseN>=0)&&(parseN<=1023)) {
          adcS=parseN;
          Vsup=adcS*Sfactor;
        }
      }
    }
  }
  buttonX=0;
  buttonY=0;
  buttonZ=0;
  thismouse=mousePressed;
  if ((thismouse==true)&&(lastmouse!=true)) {    //click!
    if ((mouseX>385)&&(mouseX<471)) {            //on or off
      if ((mouseY>4)&&(mouseY<52)) {             //on
        Rout=true;
      }
      if ((mouseY>96)&&(mouseY<143)) {             //off
        Rout=false;
      }
    }
    if ((mouseX>10)&&(mouseX<150)) {
      buttonX=1;
    }
    if ((mouseX>170)&&(mouseX<310)) {
      buttonX=2;
    }
    if ((mouseX>330)&&(mouseX<470)) {
      buttonX=3;
    }
    if ((mouseY>190)&&(mouseY<220)) {
      buttonY=1;
    }
    if ((mouseY>238)&&(mouseY<268)) {
      buttonY=2;
    }
    if ((mouseY>286)&&(mouseY<316)) {
      buttonY=3;
    }
    if ((buttonX>0)&&(buttonY>0)) {
      buttonZ=buttonX+buttonY*3-3;
    }
    if ((buttonZ>0)&&(buttonZ<6)) {
      loadPreset(buttonZ);
    }
    if (buttonZ==6) {
      surface.setResizable(true);
      surface.setSize(480, 480);
      surface.setResizable(false);
    }
    if (mouseY>320) {              //anywhere on extended panel
      surface.setResizable(true);
      surface.setSize(480, 320);
      surface.setResizable(false);
    }
  }
  if (thismouse) {            //in slider zone, any time mouse is down
    if ((mouseY>55)&&(mouseY<89)) {      //V slider
      cPreset=0;
      Vout=((mouseX-24)*20.0)/348;
      if (Vout<0) {
        Vout=0;
      }
      if (Vout>20) {
        Vout=20;
      }
    }
    if ((mouseY>146)&&(mouseY<180)) {      //I slider
      cPreset=0;
      Iout=((mouseX-24)*1.0)/348;
      if (Iout<0) {
        Iout=0;
      }
      if (Iout>1) {
        Iout=1;
      }
    }
  }
  if (portConnect) {        //update output
    if (Rout) {
      PSU.write("R1\r\n");
      //println("R1");
    } else {
      PSU.write("R0\r\n");
      //println("R0");
    }
    PSU.write("V"+str(int(Vout*Vfactor))+"\r\n"); //to output
    PSU.write("I"+str(int(Iout*Ifactor))+"\r\n"); //to output
    //println("V"+str(int(Vout*Vfactor))); //to output
    //println("I"+str(int(Iout*Ifactor))); //to output
  } else {
    Vout=0;            //not connected can't output
    Iout=0;            //not connected can't output
  }
  //draw indicator triangles
  tPointer(24+((Vout/20)*348), 76, 0, 255, 0);  //setpoint for volts=green
  tPointer(24+((adcU*Ufactor/20)*348), 76, 255, 0, 0);  //actual for volts=red
  tPointer(24+((Iout/1.0)*348), 167, 0, 255, 0);  //setpoint for current=green
  tPointer(24+((adcJ*Jfactor/1.0)*348), 167, 255, 0, 0);  //actual for current=red
  if (Rout) {
    fill(color(0, 192, 0));    //green
  } else {
    fill(color(255, 0, 0));    //red
  }
  rect(391, 10, 75, 38);
  fill(color(0, 0, 0));
  text("ON", 404, 41);
  text("OFF", 401, 132);
  text(nf(Vout, 2, 2)+"V", 70, 41);          //V setpoint
  text(nf(int(Iout*1000), 4)+"mA", 60, 132);    //I setpoint
  text(nf(adcU*Ufactor, 2, 2)+"V", 238, 41);  //V readout
  text(nf(int(adcJ*Jfactor*1000), 4)+"mA", 228, 132);//I readout
  //text("V="+str(adcU)+"    ",10,40);
  //text("I="+str(adcJ)+"    ",10,80);
  //ellipse(mouseX,mouseY,10,10);
  //text(str(mouseX)+","+str(mouseY)+","+str(buttonZ)+"     ",160,300);

  //preset titles
  for (i=0; i<5; i++) {
    if ((i+1)==cPreset) {
      fill(color(0, 192, 0));    //green
    } else {
      fill(color(0, 0, 0));    //black
    }
    text(Npreset[i], (i%3)*160+80-(Npreset[i].length())*9, (i/3)*48+215);
  }

  //power display
  pTemp=adcU*Ufactor*adcJ*Jfactor;
  fill(color(0, 0, 0));    //black
  if (pTemp>0.8) {
    fill(color(128, 128, 0));
  }    //yellow
  if (pTemp>1.0) {
    fill(color(128, 64, 0));
  }    //orange
  if (pTemp>1.2) {
    fill(color(128, 0, 0));
  }    //red
  text("P="+nf(pTemp, 1, 2)+"W", 5, 312);

  pTemp=(Vsup-(adcU*Ufactor))*adcJ*Jfactor;
  if (pTemp<0) {
    pTemp=0;
  }    //in case of glitches
  fill(color(0, 0, 0));    //black
  if (pTemp>0.8) {
    fill(color(128, 128, 0));
  }    //yellow
  if (pTemp>1.0) {
    fill(color(128, 64, 0));
  }    //orange
  if (pTemp>1.2) {
    fill(color(128, 0, 0));
  }    //red
  text("Q="+nf(pTemp, 1, 2)+"W", 165, 312);

  //display calibration data
  //assume V=U=4;
  fill(color(0, 0, 0));    //black
  text("6V:", 5, 350);
  text("VFACTOR="+nf((Vout*Vfactor)/6.0, 2, 4), 150, 350);
  if (adcU>0) {
    text("UFACTOR="+nf(6.0/adcU, 2, 4), 150, 390);
  } else {
    text("Voltage invalid", 150, 390);
  }

  //assume I=J=300mA;
  text("300mA:", 5, 430);
  text("IFACTOR="+nf((Iout*Ifactor)/0.3, 2, 4), 150, 430);
  if (adcJ>0) {
    text("JFACTOR="+nf(0.3/adcJ, 2, 4), 150, 470);
  } else {
    text("Current invalid", 150, 470);
  }


  //save to check for changes
  lastmouse=thismouse;
  lastkey=thiskey;
}

void loadPreset(int p) {
  cPreset=p;
  Vout=Vpreset[p-1];
  Iout=Ipreset[p-1];
  if (Vout<0) {
    Vout=0;
  }
  if (Vout>20) {
    Vout=20;
  }
  if (Iout<0) {
    Iout=0;
  }
  if (Iout>1) {
    Iout=1;
  }
}

int parseToken() { //scan stream and if number entered, returns char prefix (eg U,J)
  int retval=0;
  int d;
  while (PSU.available()>0) {
    d=PSU.read();
    //print(char(d));
    if (d=='-') {
      if (p==0) {
        sign=-1;
      }      //negative if - first character
    } else if ((d>='0')&&(d<='9')) {    //add digit
      p=p*10+d-'0';
      valid=true;
    } else if ((d==13)||(d==10)) {
      if (valid) {
        parseN=p*sign;
        retval=prefix;
      }
      //clear everything if CR/LF received
      p=0;
      sign=1;
      valid=false;
      prefix=0;
    } else if ((d>='A')&&(d<='Z')) {
      prefix=d;
    } else {
      //clear everything if anything else received
      p=0;
      sign=1;
      valid=false;
    }
  }
  return retval;
}

void tPointer(float x, float y, float r, float g, float b) {
  fill(color(0, 0, 0));
  triangle(x, y, x-8, y-16, x+8, y-16);    //outline
  fill(color(r, g, b));
  triangle(x, y-2, x-6, y-14, x+6, y-14);    //body
}
