/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2008-2009 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#include "PLCrashFeatureConfig.h"

#if PLCRASH_FEATURE_MACH_EXCEPTIONS

#import "SenTestCompat.h"
#import "PLCrashMachExceptionPort.h"
#import "PLCrashAsync.h"

/* EXC_MASK_GUARD isn't supported on Mac OS X 10.8, but the iOS Simulator includes it in
 * EXC_MASK_ALL; we don't actually need to use it for our tests, so we define a safe subset
 * of EXC_MASK_ALL here. */
#ifndef EXC_MASK_GUARD
#define EXC_MASK_GUARD 0
#endif
#define EXC_MASK_ALL_SAFE (EXC_MASK_ALL & ~(EXC_MASK_GUARD|EXC_MASK_RESOURCE))

@interface PLCrashMachExceptionPortTests : SenTestCase {

}
@end

@implementation PLCrashMachExceptionPortTests

- (void) testExceptionPortStatesForTask {
    plcrash_mach_exception_port_set_t states;
    NSError *error;
    kern_return_t kr;
    
    /* Fetch the current ports */
    kr = task_get_exception_ports(mach_task_self(), EXC_MASK_ALL_SAFE, states.masks, &states.count, states.ports, states.behaviors, states.flavors);
    
    PLCrashMachExceptionPortSetA *objStates = [PLCrashMachExceptionPortA exceptionPortsForTask: mach_task_self() mask: EXC_MASK_ALL_SAFE error: &error];
    STAssertNotNil(objStates, @"Failed to fetch port state: %@", error);

    /* Compare the sets */
    STAssertEquals([objStates.set count], (NSUInteger) states.count, @"Incorrect count");
    for (PLCrashMachExceptionPortA *state in objStates) {
        BOOL found = NO;
        for (mach_msg_type_number_t i = 0; i < states.count; i++) {
            if (states.masks[i] != state.mask)
                continue;
            
            found = YES;
            STAssertEquals(states.ports[i], state.server_port, @"Incorrect port");
            STAssertEquals(states.behaviors[i], state.behavior, @"Incorrect behavior");
            STAssertEquals(states.flavors[i], state.flavor, @"Incorrect flavor");
        }
        STAssertTrue(found, @"State not found");
    }
}

- (void) testExceptionPortStatesForThread {
    plcrash_mach_exception_port_set_t states;
    NSError *error;
    kern_return_t kr;
    
    /* Fetch the current ports */
    kr = thread_get_exception_ports(pl_mach_thread_self(), EXC_MASK_ALL_SAFE, states.masks, &states.count, states.ports, states.behaviors, states.flavors);
    
    PLCrashMachExceptionPortSetA *objStates = [PLCrashMachExceptionPortA exceptionPortsForThread: pl_mach_thread_self() mask: EXC_MASK_ALL_SAFE error: &error];
    STAssertNotNil(objStates, @"Failed to fetch port state: %@", error);
    
    /* Compare the sets */
    STAssertEquals([objStates.set count], (NSUInteger) states.count, @"Incorrect count");
    for (PLCrashMachExceptionPortA *state in objStates) {
        BOOL found = NO;
        for (mach_msg_type_number_t i = 0; i < states.count; i++) {
            if (states.masks[i] != state.mask)
                continue;
            
            found = YES;
            STAssertEquals(states.ports[i], state.server_port, @"Incorrect port");
            STAssertEquals(states.behaviors[i], state.behavior, @"Incorrect behavior");
            STAssertEquals(states.flavors[i], state.flavor, @"Incorrect flavor");
        }
        STAssertTrue(found, @"State not found");
    }
}

- (void) testRegisterForTask {
    NSError *error;
    PLCrashMachExceptionPortSetA *previousStates;

    PLCrashMachExceptionPortA *state = [[[PLCrashMachExceptionPortA alloc] initWithServerPort: MACH_PORT_NULL
                                                                                           mask: EXC_MASK_SOFTWARE
                                                                                       behavior: EXCEPTION_STATE_IDENTITY
                                                                                         flavor: MACHINE_THREAD_STATE] autorelease];

    /* Fetch the current state to compare against */
    PLCrashMachExceptionPortSetA *initialState = [PLCrashMachExceptionPortA exceptionPortsForTask: mach_task_self() mask: EXC_MASK_SOFTWARE error: &error];
    STAssertNotNil(initialState, @"Failed to fetch port state: %@", error);
    
    /* Set new state */
    STAssertTrue([state registerForTask: mach_task_self() previousPortSet: &previousStates error: &error], @"Failed to register exception ports: %@", error);
    
    /* Verify that new state matches our expectations */
    PLCrashMachExceptionPortSetA *newState = [PLCrashMachExceptionPortA exceptionPortsForTask: mach_task_self() mask: EXC_MASK_SOFTWARE error: &error];
    for (PLCrashMachExceptionPortA *expected in newState) {
        STAssertEquals((mach_port_t)MACH_PORT_NULL, expected.server_port, @"Incorrect port");
    }

    /* Restore */
    for (PLCrashMachExceptionPortA *prev in previousStates)
        STAssertTrue([prev registerForTask: mach_task_self() previousPortSet: NULL error: &error], @"Failed to restore port: %@", error);

    /* Verify that final state matches our expectations */
    for (PLCrashMachExceptionPortA *expected in initialState) {
        for (PLCrashMachExceptionPortA *prev in previousStates)
            if (prev.mask == expected.mask)
                STAssertEquals(expected.server_port, prev.server_port, @"Incorrect port restored");
    }
}

- (void) testRegisterForThread {
    NSError *error;
    PLCrashMachExceptionPortSetA *previousStates;
    
    PLCrashMachExceptionPortA *state = [[[PLCrashMachExceptionPortA alloc] initWithServerPort: MACH_PORT_NULL
                                                                                           mask: EXC_MASK_SOFTWARE
                                                                                       behavior: EXCEPTION_STATE_IDENTITY
                                                                                         flavor: MACHINE_THREAD_STATE] autorelease];
    
    /* Fetch the current state to compare against */
    PLCrashMachExceptionPortSetA *initialState = [PLCrashMachExceptionPortA exceptionPortsForThread: pl_mach_thread_self() mask: EXC_MASK_SOFTWARE error: &error];
    STAssertNotNil(initialState, @"Failed to fetch port state: %@", error);
    
    /* Set new state */
    STAssertTrue([state registerForThread: pl_mach_thread_self() previousPortSet: &previousStates error: &error], @"Failed to register exception ports: %@", error);
    
    /* Verify that new state matches our expectations */
    PLCrashMachExceptionPortSetA *newState = [PLCrashMachExceptionPortA exceptionPortsForThread: pl_mach_thread_self() mask: EXC_MASK_SOFTWARE error: &error];
    for (PLCrashMachExceptionPortA *expected in newState) {
        STAssertEquals((mach_port_t)MACH_PORT_NULL, expected.server_port, @"Incorrect port");
    }
    
    /* Restore */
    for (PLCrashMachExceptionPortA *prev in previousStates)
        STAssertTrue([prev registerForThread: pl_mach_thread_self() previousPortSet: NULL error: &error], @"Failed to restore port: %@", error);
    
    /* Verify that final state matches our expectations */
    for (PLCrashMachExceptionPortA *expected in initialState) {
        for (PLCrashMachExceptionPortA *prev in previousStates)
            if (prev.mask == expected.mask)
                STAssertEquals(expected.server_port, prev.server_port, @"Incorrect port restored");
    }
}

@end

#endif /* PLCRASH_FEATURE_MACH_EXCEPTIONS */