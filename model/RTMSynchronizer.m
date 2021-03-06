//
//  RTMSynchronizer.m
//  Milpon
//
//  Created by mootoh on 8/31/08.
//  Copyright 2008 deadbeaf.org. All rights reserved.
//

#import "RTMSynchronizer.h"
#import "RTMList.h"
#import "RTMTask.h"
#import "RTMExistingTask.h"
#import "RTMAuth.h"
#import "RTMAPIList.h"
#import "RTMAPITask.h"
#import "RTMAPINote.h"
#import "RTMPendingTask.h"
#import "ProgressView.h"
#import "logger.h"

@implementation RTMSynchronizer

- (id) initWithDB:(RTMDatabase *)ddb withAuth:aauth
{
   if (self = [super init]) {
      db   = ddb;
      auth = aauth;
   }
   return self;
}

- (void) dealloc
{
   [super dealloc];
}

- (void) replaceLists
{
   [RTMList erase:db];

   RTMAPIList *api_list = [[[RTMAPIList alloc] init] autorelease];
   NSArray *lists = [api_list getList];

   NSDictionary *list;
   for (list in lists)
      [RTMList create:list inDB:db];
}

- (void) syncLists
{
   RTMAPIList *api_list = [[[RTMAPIList alloc] init] autorelease];
   NSArray *new_lists = [api_list getList];
   NSArray *old_lists = [RTMList allLists:db];

   // remove only existing in olds
   RTMList *old;
   NSDictionary *new;
   for (old in old_lists) {
      BOOL found = NO;
      for (new in new_lists) {
         if ([old.iD stringValue] == [new objectForKey:@"id"])  {
            found = YES;
            break;
         }
      }
      if (! found)
         [RTMList remove:old.iD fromDB:db];
   }

   // insert only existing in news
   old_lists = [RTMList allLists:db];
   for (new in new_lists) {
      BOOL found = NO;
      for (old in old_lists) {
         if ([old.iD stringValue] == [new objectForKey:@"id"]) {
            found = YES;
            break;
         }
      }
      if (! found)
         [RTMList create:new inDB:db];
   }
}

- (void) replaceTasks
{
   [RTMTask erase:db];

   RTMAPITask *api_task = [[RTMAPITask alloc] init];
   NSArray *tasks = [api_task getList];
   if (tasks)
      [RTMTask updateLastSync:db];

   for (NSDictionary *task_series in tasks)
      [RTMTask createAtOnline:task_series inDB:db];

   [api_task release];
}

- (void) syncTasks:(ProgressView *)progressView
{
   RTMAPITask *api_task = [[RTMAPITask alloc] init];
   NSString *last_sync = [RTMTask lastSync:db];

   NSArray *task_serieses_updated = [api_task getListWithLastSync:last_sync];
   [api_task release];
   if (!task_serieses_updated || 0 == [task_serieses_updated count])
      return;

   /*
    * sync:
    *   - existing tasks
    *   - remove obsoletes
    *   - add to DB
    */
   NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

   int i=0;
   for (NSDictionary *task_series in task_serieses_updated) {
      [progressView updateMessage:[NSString stringWithFormat:@"syncing task %d/%d", i, task_serieses_updated.count] withProgress:(float)i/(float)task_serieses_updated.count];

      [RTMExistingTask createOrUpdate:task_series inDB:db];
      i++;
   }

   [pool release];

   [RTMTask updateLastSync:db];
}

- (void) uploadPendingTasks:(ProgressView *)progressView
{
   NSArray *pendings = [RTMPendingTask tasks:db];
   RTMAPITask *api_task = [[RTMAPITask alloc] init];

   int i=1;
   for (RTMPendingTask *task in pendings) {
      NSString *list_id = [task.list_id stringValue];
      NSDictionary *task_ret = [api_task add:task.name inList:list_id];

      // if added successfuly
      NSMutableDictionary *ids = [NSMutableDictionary dictionaryWithDictionary:task_ret];
      [ids setObject:list_id forKey:@"list_id"];

      if (task.due && ![task.due isEqualToString:@""]) {
         NSString *due = [task.due stringByReplacingOccurrencesOfString:@"_" withString:@"T"];
         due = [due stringByReplacingOccurrencesOfString:@" GMT" withString:@"Z"];
         [api_task setDue:due forIDs:ids];
      }

      if (0 != [task.location_id intValue])
         [api_task setLocation:[task.location_id stringValue] forIDs:ids];

      if (0 != [task.priority intValue])
         [api_task setPriority:[task.priority stringValue] forIDs:ids];

      if (task.estimate && ![task.estimate isEqualToString:@""]) 
         [api_task setEstimate:task.estimate forIDs:ids];

      /*
       * TODO: set tags
       */

      /*
       * TODO: set notes
       */
      // get Note from DB by old Task ID
      RTMAPINote *api_note = [[RTMAPINote alloc] init];
      NSArray *notes = [RTMPendingTask getNotes:task.iD fromDB:db];
      for (NSDictionary *note in notes) {
         // - API request (rtm.tasks.notes.add) using new Task ID
         [api_note add:[note objectForKey:@"text"] forIDs:ids];

         // remove old Note from DB
         [RTMPendingTask removeNote:[note objectForKey:@"id"] fromDB:db];
      }
      [api_note release];

      // remove old Task from DB
      [RTMPendingTask remove:task.iD fromDB:db];

      [progressView updateMessage:[NSString stringWithFormat:@"uploading %d/%d tasks", i, pendings.count] withProgress:(float)i/(float)pendings.count];
      i++;
   }

	[api_task release];
}

- (void) syncModifiedTasks:(ProgressView *)progressView
{
   RTMAPITask *api_task = [[RTMAPITask alloc] init];
   NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

   int i=0;
   NSArray *tasks = [RTMTask modifiedTasks:db];
   for (RTMExistingTask *task in tasks) {
      [progressView updateMessage:[NSString stringWithFormat:@"updating %d/%d, %@...", i,tasks.count, task.name] withProgress:(float)i/(float)tasks.count];
      int edit_bits = [task.edit_bits intValue];

      if (edit_bits & EB_TASK_DUE) {
         NSArray *keys = [NSArray arrayWithObjects:@"list_id", @"task_series_id", @"task_id", nil];
         NSArray *vals = [NSArray arrayWithObjects:
            [NSString stringWithFormat:@"%d", [task.list_id intValue]],
            [NSString stringWithFormat:@"%d", [task.task_series_id intValue]],
            [NSString stringWithFormat:@"%d", [task.iD intValue]],
            nil];
         NSDictionary *ids = [NSDictionary dictionaryWithObjects:vals forKeys:keys];

         NSString *due = [task.due stringByReplacingOccurrencesOfString:@" GMT" withString:@"Z"];
         due = [due stringByReplacingOccurrencesOfString:@"_" withString:@"T"];

         if ([api_task setDue:due forIDs:ids]) {
            LOG(@"setDue succeeded");
            [task flagDownEditBits:EB_TASK_DUE];
         }
      }
      if (edit_bits & EB_TASK_COMPLETED) {
         [task flagDownEditBits:EB_TASK_COMPLETED];
         if ([api_task complete:task]) {
            [RTMTask remove:task.iD fromDB:db]; // TODO: do not remove, keep it in DB to review completed tasks.
            i++;
            continue;
         }
      }
      if (edit_bits & EB_TASK_DELETED) {
         // TODO
      }
      if (edit_bits & EB_TASK_PRIORITY) {
         [task flagDownEditBits:EB_TASK_PRIORITY];

         NSArray *keys = [NSArray arrayWithObjects:@"list_id", @"task_series_id", @"task_id", nil];
         NSArray *vals = [NSArray arrayWithObjects:
            [NSString stringWithFormat:@"%d", [task.list_id intValue]],
            [NSString stringWithFormat:@"%d", [task.task_series_id intValue]],
            [NSString stringWithFormat:@"%d", [task.iD intValue]],
            nil];
         NSDictionary *ids = [NSDictionary dictionaryWithObjects:vals forKeys:keys];

         if ([api_task setPriority:[NSString stringWithFormat:@"%d", [task.priority intValue]] forIDs:ids]) {
            LOG(@"setPriority succeeded");
         }
      }

      i++;
   }

   [pool release];
   [api_task release];
}

@end
