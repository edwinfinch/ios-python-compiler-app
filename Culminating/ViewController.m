//
//  ViewController.m
//  Culminating
//
//  Created by Edwin Finch on 1/19/16.
//  Copyright © 2016 Lignite. All rights reserved.
//

#import "ViewController.h"
@import CoreBluetooth;

typedef enum
{
    IDLE = 0,
    SCANNING,
    CONNECTED,
} ConnectionState;

typedef enum
{
    LOGGING,
    RX,
    TX,
} ConsoleDataType;

@interface ViewController () <NSStreamDelegate>

@property BOOL wasManualDisconnect;

@property CBCentralManager *cm;
@property ConnectionState state;
@property UARTPeripheral *currentPeripheral;

@property NSInputStream *inputStream;
@property NSOutputStream *outputStream;

@property NSStreamEvent lastEvent;

@property UILabel *dataLabel, *debugLabel;
@property UIButton *markAsReadButton, *sendButton, *signinButton, *getProjectsButton;
@property UITextField *userNameView;
@property UITextView *pythonscriptview, *pythonResultsView;

@property int reconnectLength;
@property NSTimer *reconnectTimer;

@end

@implementation ViewController

@synthesize cm = _cm;
@synthesize currentPeripheral = _currentPeripheral;

//Thanks to http://stackoverflow.com/questions/6368867/generate-json-string-from-nsdictionary-in-ios
-(NSString*) jsonStringWithNSDictionary:(NSDictionary*)dict PrettyPrint:(BOOL)prettyPrint {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:(NSJSONWritingOptions)(prettyPrint ? NSJSONWritingPrettyPrinted : 0)
                                                         error:&error];
    
    if (!jsonData) {
        NSLog(@"jsonStringWithPrettyPrint: error: %@", error.localizedDescription);
        return @"{}";
    } else {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
}

//Send a message to the server via the connected socket
- (void)sendMessageToServer:(NSDictionary*)message {
    NSLog(@"Sending %@", message);
    NSString *response  = [self jsonStringWithNSDictionary:message PrettyPrint:NO];
    NSData *data = [[NSData alloc] initWithData:[response dataUsingEncoding:NSASCIIStringEncoding]];
    [self.outputStream write:[data bytes] maxLength:[data length]];
}

//Login to the service
- (IBAction)joinServer:(id)sender {
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc]initWithObjects:@[@(0)] forKeys:@[@"requestType"]];
    [dictionary setObject:self.userNameView.text forKey:@"username"];
    [self sendMessageToServer:dictionary];
}

//Set the text of the data label. This is only needed for connecting to the server. Once logged in, the data label is hidden
- (void)setText:(NSString*)text {
    self.dataLabel.text = text;
}

//Should the user be disconnected from the service, try to reconnect continuously
- (void)reconnectToServer {
    if(self.reconnectLength < 1){
        self.reconnectLength = 1;
    }
    if([self.reconnectTimer isValid]){
        NSLog(@"Refusing request to open reconnect, timer is already live");
        return;
    }
    NSLog(@"Reconnect event fired seconds %d", self.reconnectLength);
    if(self.lastEvent != NSStreamEventOpenCompleted){
        self.reconnectLength *= 1.5; //1.5 will just keep it at 1 since you're dealing with an int and not a float. Change this to a value of 2 or above and it will expand exponentially over time. 1 second is good for testing, though
        self.reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:self.reconnectLength
                                         target:self
                                       selector:@selector(initNetworkCommunication)
                                       userInfo:nil
                                        repeats:NO];
        [self setText:@"Connecting..."];
    }
    else{
        self.reconnectLength = -1; //Turn off reconnect timer
    }
}

//Send a message (of code) to the server
- (void)sendMessage {
    if(self.pythonscriptview.text.length < 1){
        [self makeKeyboardDisappear:self];
        [self.pythonResultsView setText:@"Please enter some code in the field above"];
        return;
    }
    NSMutableDictionary *dict = [[NSMutableDictionary alloc]init];
    [dict setObject:self.pythonscriptview.text forKey:@"python"];
    [dict setObject:@"edwin" forKey:@"username"];
    [dict setObject:@(1) forKey:@"requestType"];
    [self sendMessageToServer:dict];
}

//Turn the bluetooth light off
- (void)lightOff {
    [self lightOn:NO];
}

//Handle any incoming stream events
- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent {
    switch (streamEvent) {
            //The connection was opened
        case NSStreamEventOpenCompleted:
            NSLog(@"Stream opened");
            [self setText:@"Connection opened"];
            break;
            //There are incoming bytes. This usually means the server is trying to chat with you
        case NSStreamEventHasBytesAvailable:
            if (theStream == self.inputStream) {
                
                uint8_t buffer[1024];
                int len;
                
                while ([self.inputStream hasBytesAvailable]) { //If there are bytes, read em'
                    len = (int)[self.inputStream read:buffer maxLength:sizeof(buffer)];
                    if (len > 0) {
                        //Process the output as a readable string which the phone can now process
                        NSString *output = [[NSString alloc] initWithBytes:buffer length:len encoding:NSASCIIStringEncoding];
                        
                        if (nil != output) {
                            NSLog(@"server said: %@", output);
                            [self setText:output];
                            
                            NSData *stringData=[output dataUsingEncoding:NSUTF8StringEncoding];
                            NSError *error;
                            NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:stringData options:NSJSONReadingMutableContainers error:&error];
                            //If the result type is a login result, let the user see the python dialogue and setup the interface
                            if([[dictionary objectForKey:@"requestType"] isEqualToNumber:@(0)] && [[dictionary objectForKey:@"status"] isEqualToNumber:@(200)]){
                                NSLog(@"Success logging in");
                                [UIView animateWithDuration:0.5f animations:^{
                                    self.userNameView.frame = CGRectMake(self.userNameView.frame.origin.x, self.userNameView.frame.origin.y-200, self.userNameView.frame.size.width, self.userNameView.frame.size.height);
                                    self.signinButton.frame = CGRectMake(self.signinButton.frame.origin.x, self.signinButton.frame.origin.y-200, self.signinButton.frame.size.width, self.signinButton.frame.size.height);
                                    self.dataLabel.frame = CGRectMake(self.dataLabel.frame.origin.x, self.view.frame.size.height + 10, self.view.frame.size.width, self.dataLabel.frame.size.height);
                                    self.pythonscriptview.frame = CGRectMake(10, 25, self.view.frame.size.width-20, self.view.frame.size.height/2);
                                    self.pythonResultsView.frame = CGRectMake(10, self.view.frame.size.height/2 + 180, self.view.frame.size.width-20, 140);
                                    self.sendButton.enabled = YES;
                                    self.getProjectsButton.enabled = YES;
                                    [self.sendButton setTitle:@"Compile and Run" forState:UIControlStateNormal];
                                    [self.getProjectsButton setTitle:@"Get Past Projects" forState:UIControlStateNormal];
                                }];
                            }
                            //If the requestType is for fetching previous projects
                            else if([[dictionary objectForKey:@"requestType"] isEqualToNumber:@(2)] && [[dictionary objectForKey:@"status"] isEqualToNumber:@(200)]){
                                //And it's sucessful, turn the light on
                                [self lightOn:YES];
                                [NSTimer scheduledTimerWithTimeInterval:5.0f
                                                                 target:self
                                                               selector:@selector(lightOff)
                                                               userInfo:nil
                                                                repeats:NO];
                                NSArray *results = [dictionary objectForKey:@"files"];
                                NSMutableString *string = [[NSMutableString alloc]initWithString:@""];
                                for(int i = 0; i < [results count]; i++){
                                    [string appendString:[results objectAtIndex:i]];
                                    [string appendString:@"\n"];
                                }
                                [self.pythonResultsView setText:string];

                            }
                            //If the request type was for code compilation and was successful
                            else{
                                if([[dictionary objectForKey:@"status"] isEqualToNumber:@(200)]){
                                    //Turn the light on and display the results
                                    [self lightOn:YES];
                                    [NSTimer scheduledTimerWithTimeInterval:5.0f
                                                                     target:self
                                                                   selector:@selector(lightOff)
                                                                   userInfo:nil
                                                                    repeats:NO];
                                    NSArray *results = [dictionary objectForKey:@"results"];
                                    if(results){
                                        NSMutableString *string = [[NSMutableString alloc]initWithString:@""];
                                        for(int i = 0; i < [results count]; i++){
                                            [string appendString:[results objectAtIndex:i]];
                                            [string appendString:@"\n"];
                                        }
                                        [self.pythonResultsView setText:string];
                                    }
                                    else{
                                        //This only ever happened once to me, but better safe than sorry
                                        [self.pythonResultsView setText:@"[No results]"];
                                    }
                                }
                                //If there was an error
                                else{
                                    if([dictionary objectForKey:@"error"]){
                                        //Display that error
                                        [self.pythonResultsView setText:[NSString stringWithFormat:@"Error: %@", [dictionary objectForKey:@"error"]]];
                                    }
                                    else{
                                        self.pythonResultsView.text = @"Compilation results will go here";
                                    }
                                }
                            }
                            
                            [self makeKeyboardDisappear:self];
                            [self lightOn:YES];
                        }
                    }
                }
            }
            break;
            
            //An error occurred in the stream
        case NSStreamEventErrorOccurred:
            NSLog(@"Can not connect to the host!");
            [self reconnectToServer];
            [self setText:@"Can't connect to host"];
            break;
            
            //User was disconnected from the server
        case NSStreamEventEndEncountered:
            NSLog(@"Event ended");
            [self setText:@"Disconnected from server"];
            [self reconnectToServer];
            [theStream close];
            [theStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            break;
            
        default:
            NSLog(@"Unknown event");
            break;
    }
}

//Initialize netwrok communication
- (void)initNetworkCommunication {
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    //10.5.18.61
    CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)@"s.lignite.me", 5000, &readStream, &writeStream);
    self.inputStream = (__bridge NSInputStream *)readStream;
    self.outputStream = (__bridge NSOutputStream *)writeStream;
    
    [self.inputStream setDelegate:self];
    [self.outputStream setDelegate:self];
    
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    
    [self.inputStream open];
    [self.outputStream open];
}

//Dismiss keyboard
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (IBAction)makeKeyboardDisappear:(id)sender {
    [self textFieldShouldReturn:self.userNameView];
    [self textFieldShouldReturn:(UITextField*)self.pythonscriptview];
}

//Send a message to the server asking for past projects from the user
- (void)getPastProjects {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc]init];
    [dict setObject:@(2) forKey:@"requestType"];
    [dict setObject:self.userNameView.text forKey:@"username"];
    [self sendMessageToServer:dict];
}

//Load the view
- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.cm = [[CBCentralManager alloc] initWithDelegate:self queue:nil];

    self.dataLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, self.view.frame.size.height/2 - 20, self.view.frame.size.width, 40)];
    self.dataLabel.textAlignment = NSTextAlignmentCenter;
    self.dataLabel.text = @"Connecting...";
    self.dataLabel.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:18.0f];
    [self.view addSubview:self.dataLabel];
    
    self.debugLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, self.dataLabel.frame.origin.y+self.dataLabel.frame.size.height, self.view.frame.size.width, 40)];
    self.debugLabel.textAlignment = NSTextAlignmentCenter;
    self.debugLabel.font = [UIFont fontWithName:@"HelveticaNeue-Thin" size:14.0f];
    [self.view addSubview:self.debugLabel];
    
    self.markAsReadButton = [[UIButton alloc]initWithFrame:CGRectMake(0, self.debugLabel.frame.origin.y+self.debugLabel.frame.size.height - 20, self.view.frame.size.width, 40)];
    self.markAsReadButton.userInteractionEnabled = YES;
    [self.markAsReadButton.titleLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:16.0f]];
    [self.markAsReadButton addTarget:self action:@selector(markAsRead) forControlEvents:UIControlEventTouchUpInside];
    [self.markAsReadButton setTitle:@"Turn off light" forState:UIControlStateNormal];
    [self.markAsReadButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.view addSubview:self.markAsReadButton];
    
    self.sendButton = [[UIButton alloc]initWithFrame:CGRectMake(0, self.markAsReadButton.frame.origin.y+self.markAsReadButton.frame.size.height, self.view.frame.size.width, 40)];
    self.sendButton.userInteractionEnabled = YES;
    self.sendButton.enabled = NO;
    [self.sendButton.titleLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:18.0f]];
    [self.sendButton addTarget:self action:@selector(sendMessage) forControlEvents:UIControlEventTouchUpInside];
    [self.sendButton setTitle:@"" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.view addSubview:self.sendButton];
    
    self.getProjectsButton = [[UIButton alloc]initWithFrame:CGRectMake(0, self.sendButton.frame.origin.y+self.sendButton.frame.size.height, self.view.frame.size.width, 40)];
    self.getProjectsButton.userInteractionEnabled = YES;
    self.getProjectsButton.enabled = NO;
    [self.getProjectsButton.titleLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:14.0f]];
    [self.getProjectsButton addTarget:self action:@selector(getPastProjects) forControlEvents:UIControlEventTouchUpInside];
    [self.getProjectsButton setTitle:@"" forState:UIControlStateNormal];
    [self.getProjectsButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.view addSubview:self.getProjectsButton];
    
    self.userNameView = [[UITextField alloc]initWithFrame:CGRectMake(30, 30, self.view.frame.size.width-60, 40)];
    self.userNameView.userInteractionEnabled = YES;
    self.userNameView.keyboardAppearance = UIKeyboardAppearanceLight;
    self.userNameView.keyboardType = UIKeyboardTypeAlphabet;
    self.userNameView.layer.cornerRadius = 8.0f;
    self.userNameView.layer.masksToBounds = YES;
    self.userNameView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.userNameView.layer.borderWidth = 1.0f;
    [self.view addSubview:self.userNameView];
    
    self.signinButton = [[UIButton alloc]initWithFrame:CGRectMake(0, self.userNameView.frame.origin.y+self.userNameView.frame.size.height+10, self.view.frame.size.width, 20)];
    self.signinButton.userInteractionEnabled = YES;
    [self.signinButton.titleLabel setFont:[UIFont fontWithName:@"HelveticaNeue-Light" size:16.0f]];
    [self.signinButton addTarget:self action:@selector(joinServer:) forControlEvents:UIControlEventTouchUpInside];
    [self.signinButton setTitle:@"Login" forState:UIControlStateNormal];
    [self.signinButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.view addSubview:self.signinButton];
    
    self.pythonscriptview = [[UITextView alloc]initWithFrame:CGRectMake(30, -self.view.frame.size.height, self.view.frame.size.width-60, self.view.frame.size.height/2)];
    self.pythonscriptview.userInteractionEnabled = YES;
    self.pythonscriptview.keyboardAppearance = UIKeyboardAppearanceLight;
    self.pythonscriptview.keyboardType = UIKeyboardTypeASCIICapable;
    self.pythonscriptview.layer.cornerRadius = 8.0f;
    self.pythonscriptview.layer.masksToBounds = YES;
    self.pythonscriptview.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.pythonscriptview.layer.borderWidth = 1.0f;
    [self.view addSubview:self.pythonscriptview];
    
    self.pythonResultsView = [[UITextView alloc]initWithFrame:CGRectMake(30, -self.view.frame.size.height, self.view.frame.size.width-60, self.view.frame.size.height/2)];
    self.pythonResultsView.userInteractionEnabled = YES;
    self.pythonResultsView.backgroundColor = [UIColor blackColor];
    self.pythonResultsView.textColor = [UIColor greenColor];
    self.pythonResultsView.font = [UIFont fontWithName:@"Courier-Bold" size:14.0f];
    self.pythonResultsView.keyboardAppearance = UIKeyboardAppearanceLight;
    self.pythonResultsView.keyboardType = UIKeyboardTypeURL;
    self.pythonResultsView.layer.cornerRadius = 8.0f;
    self.pythonResultsView.layer.masksToBounds = YES;
    self.pythonResultsView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.pythonResultsView.layer.borderWidth = 1.0f;
    [self.view addSubview:self.pythonResultsView];
    
    
    self.view.userInteractionEnabled = YES;
    UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(makeKeyboardDisappear:)];
    [self.view addGestureRecognizer:gesture];
    
    [self initNetworkCommunication];
    NSLog(@"Network communication setup");
}

- (void) didReadHardwareRevisionString:(NSString *)string{
    //dust
    NSLog(@"Got hardware string %@", string);
}

- (void) didReceiveData:(NSString *)string{
    NSLog(@"Got data string %@", string);
}

//No need for this in "production", it's used for the bluetooth light
- (void) debug:(NSString *)toDebug{
    return;
    if(self.debugLabel == nil){
        NSLog(@"debugLabel is nil... returning.");
        return;
    }
    [self.debugLabel setText:toDebug];
}

/*
 From here on out your on your own, read the NSLog's if you want to understand the code more
 tbh unless you have the right bluetooth module you won't be able to use the code for this anyway
 */

- (IBAction)connectButtonPressed:(id)sender{
    NSLog(@"Pressed %d", self.state);
    
    switch (self.state) {
        case IDLE:
            self.state = SCANNING;
            
            NSLog(@"Scanning");

            [self.cm scanForPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID] options:@{CBCentralManagerScanOptionAllowDuplicatesKey: [NSNumber numberWithBool:NO]}];
            break;
            
        case SCANNING:
            self.state = IDLE;
        
            NSLog(@"Stopped scan");
            
            [self.cm stopScan];
            break;
            
        case CONNECTED:
            NSLog(@"Disconnect peripheral %@", self.currentPeripheral.peripheral.name);
            self.wasManualDisconnect = YES;
            [self.cm cancelPeripheralConnection:self.currentPeripheral.peripheral];
            break;
    }
}

- (void)lightOn:(BOOL)on {
    NSString *toSend = on ? @"on\r" : @"off\r";
    [self.currentPeripheral writeString:toSend];
}

- (void)markAsRead {
    [self lightOn:NO];
}

- (void) centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state == CBCentralManagerStatePoweredOn)
    {
        NSLog(@"Enable connect button");
        [self connectButtonPressed:self];
    }
    
}

- (void) centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSLog(@"Did discover peripheral %@", peripheral.name);
    [self.cm stopScan];
    
    self.currentPeripheral = [[UARTPeripheral alloc] initWithPeripheral:peripheral delegate:self];
    
    [self.cm connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: [NSNumber numberWithBool:YES]}];
}

- (void) centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Did connect peripheral %@", peripheral.name);
    
    NSString *string = [[NSString alloc]initWithFormat:@"Connected to %@", peripheral.name];
    [self debug:string];
    
    self.state = CONNECTED;
    
    if ([self.currentPeripheral.peripheral isEqual:peripheral])
    {
        [self.currentPeripheral didConnect];
    }
}

- (void) centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Did disconnect peripheral %@", peripheral.name);
    
    NSString *string = [[NSString alloc]initWithFormat:@"Disconnected from %@", peripheral.name];
    [self debug:string];
    
    self.state = IDLE;
    
    if ([self.currentPeripheral.peripheral isEqual:peripheral]){
        [self.currentPeripheral didDisconnect];
    }
    
    if(!self.wasManualDisconnect){
        NSLog(@"Was disconnected from the device without user request. Reconnecting...");
        [self connectButtonPressed:nil];
    }
    else{
        self.wasManualDisconnect = NO;
    }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    /*
     NSIndexPath *topIndexPath =
     [NSIndexPath indexPathForRow:messages.count-1
     inSection:0];
     [self.tView scrollToRowAtIndexPath:topIndexPath
     atScrollPosition:UITableViewScrollPositionMiddle
     animated:YES];
     */
}

@end
