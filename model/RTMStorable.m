//
//  RTMStorable.m
//  Milpon
//
//  Created by mootoh on 10/9/08.
//  Copyright 2008 deadbeaf.org. All rights reserved.
//

#import "RTMStorable.h"

@implementation RTMStorable

@synthesize iD;

- (id) initByID:(NSNumber *)iid inDB:(RTMDatabase *)ddb
{
  if (self = [super init]) {
    db = [ddb retain];
    iD = [iid retain];
  }
  return self;
}

- (void) dealloc
{
  [iD release];
  [db release];
  [super dealloc];
}

+ (void) createAtOnline:(NSDictionary *)params inDB:(RTMDatabase *)db
{
}

+ (void) createAtOffline:(NSDictionary *)params inDB:(RTMDatabase *)db
{
}

+ (void) erase:(RTMDatabase *)db
{
}

+ (void) remove:(NSInteger)iid fromDB:(RTMDatabase *)db
{
}

@end
