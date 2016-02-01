//
//  UARTPeripheral.h
//  iDoc360
//
//  Created by Edwin Finch on 2015-04-11.
//  Copyright (c) 2015 Edwin Finch Software. All rights reserved.
//

#import <Foundation/Foundation.h>
@import CoreBluetooth;

@protocol UARTPeripheralDelegate
- (void) didReceiveData:(NSString *) string;
@optional
- (void) didReadHardwareRevisionString:(NSString *) string;
@end


@interface UARTPeripheral : NSObject <CBPeripheralDelegate>
@property CBPeripheral *peripheral;
@property id<UARTPeripheralDelegate> delegate;

+ (CBUUID *) uartServiceUUID;

- (UARTPeripheral *) initWithPeripheral:(CBPeripheral*)peripheral delegate:(id<UARTPeripheralDelegate>) delegate;

- (void) writeString:(NSString *) string;

- (void) didConnect;
- (void) didDisconnect;
@end