//
//  RTMAPI.m
//  Milpon
//
//  Created by mootoh on 8/30/08.
//  Copyright 2008 deadbeaf.org. All rights reserved.
//

#import <CommonCrypto/CommonDigest.h>
#import "RTMAPI.h"
#import "logger.h"

#define RTM_URI   "http://api.rememberthemilk.com"
#define REST_PATH "/services/rest/"
#define AUTH_PATH "/services/auth/"

@implementation RTMAPI

static NSString *s_api_key;
static NSString *s_shared_secret;
static NSString *s_token;

+ (void) setApiKey:(NSString *)key
{
   s_api_key = [key retain];
}

+ (void) setSecret:(NSString *)sec
{
   s_shared_secret = [sec retain];
}

+ (void) setToken:(NSString *)tok
{
   s_token = [tok retain];
}

- (void) dealloc
{
   [timeline release];
   [super dealloc];
}

- (NSData *) call:(NSString *)method withArgs:(NSDictionary *)args
{
   sleep(1);
   NSString *url = [self path:method withArgs:args];
   NSURLRequest *req = [NSURLRequest
      requestWithURL:[NSURL URLWithString:url]
      cachePolicy:NSURLRequestUseProtocolCachePolicy
      timeoutInterval:60.0];
   NSURLResponse *res;
   NSError *err;

   LOG(@"API calling for url=%@", url);
   NSData *ret = [NSURLConnection sendSynchronousRequest:req
      returningResponse:&res
      error:&err];
   if (NULL == ret) {
      LOG(@"failed in API call: %@, url=%@", [err localizedDescription], url);
   } else {
      LOG(@"API call succeeded for url=%@", url);
   }

#ifdef DUMP_API_RESPONSE
   if (ret) {
      //NSString *dump_path = [NSString stringWithFormat:@"/tmp/%@.xml", method];
      //BOOL wrote = [ret writeToFile:dump_path options:NSAtomicWrite error:nil];
      //NSAssert(wrote, @"dump should be written");
      NSLog(@"method=%@, response=%@", method, [[[NSString alloc] initWithData:ret encoding:NSUTF8StringEncoding] autorelease]);
   }
#endif // DUMP_API_RESPONSE

   return ret;
}

- (NSString *) path:(NSString *)method withArgs:(NSDictionary *)args
{
   NSMutableString *arg = [[[NSMutableString alloc] init] autorelease];

   NSMutableDictionary *args_with_token = [NSMutableDictionary dictionaryWithDictionary:args];
   if (s_token)
      [args_with_token setObject:s_token forKey:@"auth_token"];

   NSEnumerator *enumerator = [args_with_token keyEnumerator];
   NSString *key;
   while (key = [enumerator nextObject]) {
      // escape values
      NSString *val = [args_with_token objectForKey:key];
      val = [val stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
      val = [val stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];

      [arg appendFormat:@"&%@=%@", key, val];
   }

   NSString *sig = [self sign:method withArgs:args_with_token];
   NSString *ret = [NSString
      stringWithFormat:@"%s%s?method=%@&api_key=%@&api_sig=%@%@",
      RTM_URI, REST_PATH, method, s_api_key, sig, arg];
   return ret;
}

- (NSString *)sign:(NSString *)method withArgs:(NSDictionary *)args
{
   // append method, api_key
   NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:args];
   if (method) [params setObject:method forKey:@"method"];

   [params setObject:s_api_key forKey:@"api_key"];

   NSMutableArray *keys = [NSMutableArray arrayWithArray:[params allKeys]];
   [keys sortUsingSelector:@selector(compare:)];

   NSString *key;
   NSMutableString *concat = [NSMutableString stringWithString:s_shared_secret];
   for (key in keys)
      [concat appendFormat:@"%@%@", key, [params objectForKey:key]];

   // MD5 hash
   unsigned char digest[CC_MD5_DIGEST_LENGTH];
   memset(digest, 0, CC_MD5_DIGEST_LENGTH);
   const char *from = [concat UTF8String];
   CC_MD5(from, strlen(from), digest);
   NSString *ret = [NSString stringWithFormat:
      @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
      digest[0], digest[1], digest[2], digest[3],
      digest[4], digest[5], digest[6], digest[7],
      digest[8], digest[9], digest[10], digest[11],
      digest[12], digest[13], digest[14], digest[15]];
   return ret;
}

// XXX: dup with path:
- (NSString *) authURL:(NSString *)frob forPermission:(NSString *)perm {	
   NSArray *keys = [NSArray arrayWithObjects:@"frob", @"perms", nil];
   NSArray *vals = [NSArray arrayWithObjects:frob, perm, nil];
   NSDictionary *args = [NSDictionary dictionaryWithObjects:vals forKeys:keys];

   NSMutableString *arg = [[[NSMutableString alloc] init] autorelease];
   NSEnumerator *enumerator = [args keyEnumerator];
   NSString *key;
   while (key = [enumerator nextObject])
      [arg appendFormat:@"&%@=%@", key, [args objectForKey:key]];

   NSString *sig = [self sign:nil withArgs:args];
   NSString *ret = [NSString stringWithFormat:@"%s%s?api_key=%@%@&api_sig=%@",
            RTM_URI, AUTH_PATH, s_api_key, arg, sig];
   return ret;
}

- (NSString *) createTimeline
{
   NSData *response = [self call:@"rtm.timelines.create" withArgs:nil];
   if (! response) return nil;

   method_ = TIMELINES_CREATE;
   NSXMLParser *parser = [[[NSXMLParser alloc] initWithData:response] autorelease];
   [parser setDelegate:self];
   BOOL parsed = [parser parse];
   NSAssert(parsed, @"parse should be done successfully");

   return timeline;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict
{
   if ([elementName isEqualToString:@"timeline"]) {
      NSAssert(method_ == TIMELINES_CREATE, @"method should be timelines.create");
   }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
   if ([elementName isEqualToString:@"timeline"]) {
      NSAssert(method_ == TIMELINES_CREATE, @"method should be timelines.create");
      NSAssert(timeline, @"timeline should be obtained");
   }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)chars
{
   [timeline release];
   timeline = [chars retain];
}

@end
